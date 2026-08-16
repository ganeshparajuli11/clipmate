import AppKit
import ApplicationServices
import Foundation

/// Makes ⌘X / ⌘V behave like Windows cut-and-paste **inside Finder**.
///
/// Finder has no ⌘X of its own: the Mac convention is ⌘C then ⌥⌘V ("Move Item
/// Here"). When the user opts in, this service intercepts ⌘X and ⌘V while Finder
/// is frontmost and performs a real move on paste.
///
/// ## Why this needs Accessibility
/// Deciding *not* to deliver a keystroke to the app that would otherwise receive it
/// is only possible with a `CGEventTap`, and macOS gates event taps behind the
/// Accessibility permission. There is no lighter-weight way: a Carbon hotkey would
/// swallow ⌘X in *every* app, including text fields, which would be far worse.
///
/// This is why the whole feature is opt-in and off by default — a user who never
/// turns it on is never asked for anything.
///
/// ## Scope of interception
/// The tap is deliberately narrow. It only consumes an event when **all** of these
/// hold, and otherwise passes it straight through untouched:
/// - the feature is enabled,
/// - Finder is the frontmost application,
/// - focus is not in a text field (so renaming a file with ⌘X still cuts text),
/// - and for ⌘V, a cut is actually pending.
///
/// - Note: Main-thread only. The tap is installed on the main run loop, so the
///   callback arrives on the main thread and `@Published` updates are safe.
final class FinderCutService: ObservableObject {

    /// Files marked for moving by the last ⌘X, or empty when no cut is pending.
    @Published private(set) var pendingCut: [URL] = []

    /// True while the event tap is installed and running.
    @Published private(set) var isRunning = false

    /// Last failure worth showing the user (permission lost, move failed, …).
    @Published private(set) var lastError: String?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private static let finderBundleID = "com.apple.finder"

    /// Virtual key codes we care about.
    private enum KeyCode {
        static let x: Int64 = 7
        static let v: Int64 = 9
        static let escape: Int64 = 53
    }

    // MARK: - Permission

    /// Whether ClipMate currently holds the Accessibility permission.
    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Asks macOS to show the "grant Accessibility" prompt.
    ///
    /// The system only shows the prompt once per app; afterwards it silently
    /// returns the current state, which is why Settings also offers a button that
    /// opens the relevant System Settings pane directly.
    @discardableResult
    static func requestAccessibilityPermission() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Lifecycle

    /// Installs the event tap. Returns false if Accessibility has not been granted.
    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        guard Self.hasAccessibilityPermission else {
            lastError = "ClipMate needs Accessibility permission to intercept ⌘X in Finder."
            isRunning = false
            return false
        }

        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.tapDisabledByTimeout.rawValue)
            | (1 << CGEventType.tapDisabledByUserInput.rawValue)

        // `defaultTap` (rather than `listenOnly`) is what allows returning nil to
        // swallow an event.
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<FinderCutService>.fromOpaque(refcon).takeUnretainedValue()
                return service.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            lastError = "Could not install the keyboard tap. Try toggling Accessibility off and on."
            isRunning = false
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        isRunning = true
        lastError = nil
        return true
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isRunning = false
        pendingCut = []
    }

    deinit {
        stop()
    }

    // MARK: - Event handling

    /// Returns `nil` to swallow the event, or the event to let it through.
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system disables a tap that takes too long or on certain user input.
        // Re-enable rather than silently dying.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return nil
        }

        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Escape clears a pending cut, mirroring how Windows abandons one.
        if keyCode == KeyCode.escape, !pendingCut.isEmpty {
            pendingCut = []
            return Unmanaged.passUnretained(event) // still let Finder see Escape
        }

        guard keyCode == KeyCode.x || keyCode == KeyCode.v else {
            return Unmanaged.passUnretained(event)
        }

        // Command must be down, and no Option — ⌥⌘V is Finder's own Move Item Here
        // and should keep working untouched.
        guard flags.contains(.maskCommand), !flags.contains(.maskAlternate) else {
            return Unmanaged.passUnretained(event)
        }

        guard let finder = NSWorkspace.shared.frontmostApplication,
              finder.bundleIdentifier == Self.finderBundleID else {
            return Unmanaged.passUnretained(event)
        }

        // Renaming a file puts focus in a text field, where ⌘X must still cut text.
        if hasTextFocus(pid: finder.processIdentifier) {
            return Unmanaged.passUnretained(event)
        }

        if keyCode == KeyCode.x {
            // Swallow now and do the slow work afterwards: an event-tap callback
            // that blocks for too long gets disabled by the system.
            DispatchQueue.main.async { [weak self] in self?.performCut() }
            return nil
        }

        // ⌘V with nothing cut is an ordinary paste — leave it to Finder.
        guard !pendingCut.isEmpty else { return Unmanaged.passUnretained(event) }

        DispatchQueue.main.async { [weak self] in self?.performPasteMove() }
        return nil
    }

    /// True when Finder's focused element accepts text, e.g. an inline rename.
    private func hasTextFocus(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)

        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            app, kAXFocusedUIElementAttribute as CFString, &focusedValue
        ) == .success, let focusedValue else { return false }

        // Safe: the focused-UI-element attribute always yields an AXUIElement.
        let element = unsafeDowncast(focusedValue as AnyObject, to: AXUIElement.self)

        var roleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXRoleAttribute as CFString, &roleValue
        ) == .success, let role = roleValue as? String else { return false }

        return role == (kAXTextFieldRole as String) || role == (kAXTextAreaRole as String)
    }

    // MARK: - Cut and paste

    private func performCut() {
        let selection = Self.finderSelection()

        guard !selection.isEmpty else {
            // Nothing selected: ⌘X in Finder normally does nothing anyway, so
            // swallowing it changed no behaviour.
            pendingCut = []
            return
        }

        pendingCut = selection

        // Also put the files on the pasteboard, so they show up in ClipMate's
        // history and ⌥⌘V keeps working as a fallback.
        Pasteboard.copy(files: selection)
    }

    private func performPasteMove() {
        let sources = pendingCut.filter { FileManager.default.fileExists(atPath: $0.path) }
        pendingCut = []

        guard !sources.isEmpty else {
            lastError = "Those files have moved or been deleted."
            return
        }

        guard let destination = Self.finderInsertionLocation() else {
            lastError = "Could not work out which folder to move into."
            return
        }

        var failures: [String] = []
        for source in sources {
            // Moving into the folder it already lives in is a no-op, not an error.
            if source.deletingLastPathComponent().standardizedFileURL == destination.standardizedFileURL {
                continue
            }
            do {
                try Self.move(source, into: destination)
            } catch {
                failures.append("\(source.lastPathComponent): \(error.localizedDescription)")
            }
        }

        lastError = failures.isEmpty
            ? nil
            : "Couldn't move \(failures.count) item(s). \(failures.first ?? "")"
    }

    /// Moves one item into a folder, renaming rather than overwriting on collision.
    ///
    /// Internal rather than private so it can be exercised directly in testing —
    /// this is the one destructive operation in the app.
    static func move(_ source: URL, into folder: URL) throws {
        let fileManager = FileManager.default
        var target = folder.appendingPathComponent(source.lastPathComponent)

        if fileManager.fileExists(atPath: target.path) {
            let base = source.deletingPathExtension().lastPathComponent
            let ext = source.pathExtension
            var index = 2
            repeat {
                let name = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
                target = folder.appendingPathComponent(name)
                index += 1
            } while fileManager.fileExists(atPath: target.path)
        }

        try fileManager.moveItem(at: source, to: target)
    }

    // MARK: - Talking to Finder

    /// The paths currently selected in Finder.
    private static func finderSelection() -> [URL] {
        let script = """
        tell application "Finder"
            set out to ""
            repeat with anItem in (get selection)
                set out to out & (POSIX path of (anItem as alias)) & linefeed
            end repeat
            return out
        end tell
        """
        guard let raw = runAppleScript(script) else { return [] }
        return raw
            .split(separator: "\n")
            .map { URL(fileURLWithPath: String($0)) }
    }

    /// The folder a paste would land in — the front window's folder, or the Desktop.
    private static func finderInsertionLocation() -> URL? {
        let script = """
        tell application "Finder"
            return POSIX path of (insertion location as alias)
        end tell
        """
        guard let path = runAppleScript(script)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Runs AppleScript on the main thread and returns its string result.
    ///
    /// The first call triggers the one-time "ClipMate wants to control Finder"
    /// Automation prompt, which is why `NSAppleEventsUsageDescription` is set in
    /// `Info.plist`.
    private static func runAppleScript(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if error != nil { return nil }
        return result.stringValue
    }
}
