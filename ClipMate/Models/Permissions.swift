import AppKit
import ApplicationServices
import CoreGraphics

/// The macOS permissions ClipMate can use, what each one is for, and how to ask.
///
/// ClipMate's rule: **explain first, then ask.** No permission is requested at
/// launch. Each is requested only when you use the feature that needs it, and only
/// after ClipMate has said in plain words what it will be able to see.
///
/// ## Why a switch can be "on" but ClipMate still isn't allowed
/// macOS remembers a permission against the app's *code signature*, not its name.
/// ClipMate isn't signed with a paid Apple Developer ID, so every new build has a
/// new signature — and to macOS the new copy is a different app. System Settings
/// keeps showing the old "ClipMate" switched on, while the copy you are running is
/// not allowed, so macOS keeps asking. `repair()` fixes that by clearing ClipMate's
/// stale entries and asking again for the copy that is actually running.
enum Permission: String, CaseIterable, Identifiable {
    case screenRecording
    case accessibility

    var id: String { rawValue }

    var title: String {
        switch self {
        case .screenRecording: "Screen Recording"
        case .accessibility: "Accessibility"
        }
    }

    var symbol: String {
        switch self {
        case .screenRecording: "rectangle.dashed.badge.record"
        case .accessibility: "accessibility"
        }
    }

    /// Which features need it.
    var usedFor: String {
        switch self {
        case .screenRecording:
            "Screenshots and “Copy text from screen”."
        case .accessibility:
            "Notification control, and the optional Finder ⌘X / ⌘V."
        }
    }

    /// Exactly what ClipMate can see once this is granted — and what it does with it.
    var whatWeAccess: String {
        switch self {
        case .screenRecording:
            "Only the area you drag-select, only when you press the shortcut or button. The image stays on this Mac — copied or saved where you choose, or deleted straight after reading its text."
        case .accessibility:
            "Notification control reads the app name, title and text of pop-up banners so it can close the ones you've hidden. Hidden banners are kept in memory only and forgotten when ClipMate quits. Finder cut & paste reads the selected files and open folder. Nothing else on screen is read, and nothing is sent anywhere."
        }
    }

    /// Name of the System Settings list, as the user sees it.
    var settingsPaneName: String {
        switch self {
        case .screenRecording: "Screen & System Audio Recording"
        case .accessibility: "Accessibility"
        }
    }

    /// The service name `tccutil` uses.
    private var tccService: String {
        switch self {
        case .screenRecording: "ScreenCapture"
        case .accessibility: "Accessibility"
        }
    }

    /// Whether the copy of ClipMate that is *running right now* is allowed.
    ///
    /// Accessibility updates live. Screen Recording is only picked up after
    /// ClipMate is reopened — macOS's rule, not ClipMate's.
    var isGranted: Bool {
        switch self {
        case .screenRecording: CGPreflightScreenCaptureAccess()
        case .accessibility: AXIsProcessTrusted()
        }
    }

    /// Shows the system prompt (first time) and opens the right System Settings pane.
    func request() {
        switch self {
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
        case .accessibility:
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        }
        openSystemSettings()
    }

    func openSystemSettings() {
        let anchor = switch self {
        case .screenRecording: "Privacy_ScreenCapture"
        case .accessibility: "Privacy_Accessibility"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Removes every ClipMate entry for this permission — including ones left by
    /// older copies — so the next request registers the copy that is running.
    ///
    /// Uses Apple's `tccutil`, which may reset an app's own entries without admin
    /// rights. Returns whether it succeeded.
    @discardableResult
    func reset() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", tccService, bundleID]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// The one-click fix for "it's switched on but ClipMate keeps asking":
    /// clear stale entries, then ask again for this copy.
    func repair() {
        reset()
        // Give the TCC database a moment before re-adding the app.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            request()
        }
    }
}

// MARK: - Relaunch

enum AppRelauncher {
    /// Quits and reopens ClipMate — needed after allowing Screen Recording, which
    /// macOS only applies to a freshly launched app.
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", path]
        try? process.run()
        NSApp.terminate(nil)
    }
}

// MARK: - Explain-then-ask prompts

/// One-off "here's what this will access" prompts shown before a permission is
/// requested, and a clear way out when a permission still isn't working.
@MainActor
enum PermissionExplainer {

    private enum Keys {
        static let screenRecordingExplained = "clipmate.permissions.screenRecordingExplained"
        static let notificationsConsented = "clipmate.permissions.notificationsConsented"
    }

    /// Call before a screenshot or screen-text capture.
    ///
    /// - Returns: `true` to go ahead with the capture. When the running copy of
    ///   ClipMate isn't allowed, the capture is **not** started — starting it would
    ///   just make macOS show its own prompt again and again. Instead ClipMate
    ///   explains (first time) or offers to reopen / repair (afterwards).
    static func prepareForScreenCapture() -> Bool {
        if Permission.screenRecording.isGranted { return true }

        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: Keys.screenRecordingExplained) {
            defaults.set(true, forKey: Keys.screenRecordingExplained)

            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "ClipMate needs Screen Recording permission"
            alert.informativeText = """
                To take a screenshot or copy text from the screen, macOS requires the Screen Recording permission.

                What ClipMate sees: \(Permission.screenRecording.whatWeAccess)

                Click Continue and switch ClipMate on in System Settings ▸ Privacy & Security ▸ \(Permission.screenRecording.settingsPaneName). Then reopen ClipMate — macOS only applies this permission after a restart.
                """
            alert.addButton(withTitle: "Continue")
            alert.addButton(withTitle: "Not Now")
            NSApp.activateForPanel()
            if alert.runModal() == .alertFirstButtonReturn {
                Permission.screenRecording.request()
            }
            return false
        }

        showNotWorking(.screenRecording, needsRelaunch: true)
        return false
    }

    /// Call before turning on notification control.
    ///
    /// Asks once for consent to read notification banners (even if Accessibility
    /// was already granted for Finder cut & paste — it's a different use of it),
    /// then makes sure Accessibility actually works for this copy of ClipMate.
    ///
    /// - Returns: whether the user agreed.
    static func confirmNotificationAccess() -> Bool {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: Keys.notificationsConsented) {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Allow ClipMate to read notification banners?"
            alert.informativeText = """
                To hide notifications from the apps you choose, ClipMate reads each pop-up banner's app name, title and message, and closes the ones you've hidden.

                • Hidden notifications are kept in memory only, so you can read them in the panel, and are forgotten when ClipMate quits.
                • Only the list of app names and your on/off choices are saved.
                • Nothing is sent anywhere — ClipMate has no network code.

                This uses the Accessibility permission. You can turn it off at any time in System Settings ▸ Privacy & Security ▸ Accessibility.
                """
            alert.addButton(withTitle: "Allow")
            alert.addButton(withTitle: "Cancel")
            NSApp.activateForPanel()
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
            defaults.set(true, forKey: Keys.notificationsConsented)

            if !Permission.accessibility.isGranted {
                Permission.accessibility.request()
            }
            return true
        }

        if !Permission.accessibility.isGranted {
            showNotWorking(.accessibility, needsRelaunch: false)
        }
        return true
    }

    /// Shown when a permission still isn't active for the running copy.
    ///
    /// Most often the System Settings switch belongs to an *older* ClipMate, so the
    /// main action clears those entries and asks again.
    static func showNotWorking(_ permission: Permission, needsRelaunch: Bool) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(permission.title) isn't active for this copy of ClipMate"

        var text = """
            If ClipMate already looks switched on in System Settings ▸ Privacy & Security ▸ \(permission.settingsPaneName), that switch belongs to an older copy of ClipMate — each update is a new app to macOS.

            Click “Fix Permission” to remove the old entries and ask again, then switch ClipMate on.
            """
        if needsRelaunch {
            text += "\n\nIf you've only just switched it on, click “Reopen ClipMate” — macOS applies \(permission.title) after a restart."
        }
        alert.informativeText = text

        alert.addButton(withTitle: "Fix Permission")
        if needsRelaunch { alert.addButton(withTitle: "Reopen ClipMate") }
        alert.addButton(withTitle: "Cancel")
        NSApp.activateForPanel()

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            permission.repair()
        case .alertSecondButtonReturn where needsRelaunch:
            AppRelauncher.relaunch()
        default:
            break
        }
    }
}
