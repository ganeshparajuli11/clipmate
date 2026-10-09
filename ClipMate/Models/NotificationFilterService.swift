import AppKit
import ApplicationServices
import Foundation

/// What ClipMate does with notification banners.
enum NotificationMode: String, CaseIterable, Identifiable {
    /// Hands off — macOS behaves exactly as normal.
    case showAll
    /// Hide banners from the apps you've switched off, show everything else.
    case filter
    /// Hide every banner (a one-click "quiet mode").
    case hideAll

    var id: String { rawValue }

    var title: String {
        switch self {
        case .showAll: "Show all"
        case .filter: "Choose apps"
        case .hideAll: "Hide all"
        }
    }
}

/// A banner ClipMate hid, kept so nothing is lost — it shows up in the panel's
/// "Hidden notifications" list, and clicking it copies its text.
struct CapturedNotification: Identifiable, Hashable {
    let id = UUID()
    let app: String
    let title: String
    let body: String
    let date: Date

    /// Text put on the clipboard when the row is clicked.
    var copyText: String {
        [title, body].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    var preview: String {
        let parts = [title, body].filter { !$0.isEmpty }
        return parts.joined(separator: " — ").singleLinePreview
    }
}

/// Hides notification banners per app — including the ones your **iPhone** forwards
/// to the Mac (Instagram, Messenger, WhatsApp…) via iPhone Mirroring / Continuity.
///
/// ## How it works (and why it needs Accessibility)
/// macOS has **no public API** that lets one app filter another app's
/// notifications. What *is* possible is reading Notification Center's on-screen
/// banners through the Accessibility API and pressing their own "Close" action —
/// exactly what a person clicking the ✕ would do. So this service:
///
/// 1. watches the Notification Center process (`com.apple.notificationcenterui`)
///    for new windows, plus a light 0.35 s check while a banner is on screen,
/// 2. reads each banner's app name, title and body,
/// 3. closes it if that app is switched off (or everything is hidden), and
/// 4. keeps a copy in memory so it can be read later from the panel.
///
/// A hidden banner may be visible for a split second before it is closed. Nothing
/// is written to disk, nothing leaves the Mac.
///
/// The Notification Center **sidebar** (opened by clicking the clock) is never
/// touched — only pop-up banners are — so your notification history stays intact.
@MainActor
final class NotificationFilterService: ObservableObject {

    enum Keys {
        static let mode = "clipmate.notifications.mode"
        static let knownApps = "clipmate.notifications.knownApps"
        static let hiddenApps = "clipmate.notifications.hiddenApps"
        static let keepHiddenInPanel = "clipmate.notifications.keepHiddenInPanel"
    }

    /// Notification Center's own bundle identifier.
    private static let notificationCenterBundleID = "com.apple.notificationcenterui"

    // MARK: - Published state

    @Published var mode: NotificationMode {
        didSet {
            defaults.set(mode.rawValue, forKey: Keys.mode)
            applyMode()

            // Turning the feature on for the first time explains exactly what will
            // be read and asks for consent before Accessibility is requested.
            // Deferred a tick so the alert isn't shown from inside a SwiftUI
            // binding update. Declining puts everything back to "Show all".
            if oldValue == .showAll, mode != .showAll {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if !PermissionExplainer.confirmNotificationAccess() {
                        self.mode = .showAll
                    }
                }
            }
        }
    }

    /// Every app ClipMate has seen a banner from, so Settings can list them with a
    /// show/hide switch. Also accepts names typed in by hand.
    @Published private(set) var knownApps: [String] {
        didSet { defaults.set(knownApps, forKey: Keys.knownApps) }
    }

    /// Apps whose banners are hidden in `.filter` mode. Compared case-insensitively.
    @Published private(set) var hiddenApps: Set<String> {
        didSet { defaults.set(Array(hiddenApps), forKey: Keys.hiddenApps) }
    }

    /// Keep hidden banners in the panel so they can be read later.
    @Published var keepHiddenInPanel: Bool {
        didSet {
            defaults.set(keepHiddenInPanel, forKey: Keys.keepHiddenInPanel)
            if !keepHiddenInPanel { inbox.removeAll() }
        }
    }

    /// Hidden banners, newest first. Memory only — cleared on quit.
    @Published private(set) var inbox: [CapturedNotification] = []

    /// True while ClipMate is actively watching Notification Center.
    @Published private(set) var isRunning = false

    /// How many banners were hidden since launch (shown in Settings).
    @Published private(set) var hiddenCount = 0

    static let inboxLimit = 30
    private static let knownAppsLimit = 60

    // MARK: - Private

    private let defaults: UserDefaults
    private var timer: Timer?
    private var observer: AXObserver?
    private var appElement: AXUIElement?
    private var notificationCenterPID: pid_t = 0

    /// Banners we have already logged, so one that refuses to close is not added
    /// to the inbox once per tick.
    private var recentlyHandled: [String: Date] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.mode = NotificationMode(rawValue: defaults.string(forKey: Keys.mode) ?? "") ?? .showAll
        self.knownApps = defaults.stringArray(forKey: Keys.knownApps) ?? []
        self.hiddenApps = Set(defaults.stringArray(forKey: Keys.hiddenApps) ?? [])
        self.keepHiddenInPanel = defaults.object(forKey: Keys.keepHiddenInPanel) as? Bool ?? true
    }

    // MARK: - Permission

    static var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }

    /// Opens System Settings ▸ Notifications, where macOS's own per-app switches
    /// (including "Allow notifications from iPhone") live.
    static func openSystemNotificationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - App list

    func isHidden(_ app: String) -> Bool {
        hiddenApps.contains { $0.caseInsensitiveCompare(app) == .orderedSame }
    }

    /// Show or hide one app's banners.
    func setApp(_ app: String, hidden: Bool) {
        hiddenApps = hiddenApps.filter { $0.caseInsensitiveCompare(app) != .orderedSame }
        if hidden { hiddenApps.insert(app) }
    }

    /// Adds an app by name (e.g. "Instagram") before any of its banners arrive.
    func addApp(_ name: String, hidden: Bool = true) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        learn(trimmed)
        setApp(trimmed, hidden: hidden)
    }

    func forgetApp(_ app: String) {
        knownApps.removeAll { $0.caseInsensitiveCompare(app) == .orderedSame }
        setApp(app, hidden: false)
    }

    private func learn(_ app: String) {
        guard !knownApps.contains(where: { $0.caseInsensitiveCompare(app) == .orderedSame }) else { return }
        knownApps.append(app)
        knownApps.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        if knownApps.count > Self.knownAppsLimit {
            knownApps = Array(knownApps.prefix(Self.knownAppsLimit))
        }
    }

    // MARK: - Inbox

    func clearInbox() {
        inbox.removeAll()
    }

    func remove(_ notification: CapturedNotification) {
        inbox.removeAll { $0.id == notification.id }
    }

    // MARK: - Lifecycle

    /// Starts or stops watching to match `mode`. Call once at launch.
    func applyMode() {
        if mode == .showAll {
            stop()
        } else {
            start()
        }
    }

    func start() {
        guard Self.hasAccessibilityPermission else {
            stop()
            return
        }
        guard timer == nil else { return }

        attachToNotificationCenter()

        let timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        isRunning = true
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        detachFromNotificationCenter()
        isRunning = false
    }

    private func tick() {
        // Notification Center can be relaunched by the system (or crash); follow it.
        let currentPID = NSRunningApplication
            .runningApplications(withBundleIdentifier: Self.notificationCenterBundleID)
            .first?.processIdentifier ?? 0
        if currentPID != notificationCenterPID {
            attachToNotificationCenter()
        }
        scan()
    }

    // MARK: - Attaching

    private func attachToNotificationCenter() {
        detachFromNotificationCenter()

        guard let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: Self.notificationCenterBundleID)
            .first else { return }

        let pid = app.processIdentifier
        let element = AXUIElementCreateApplication(pid)
        // Never let a busy Notification Center stall ClipMate's main thread.
        _ = AXUIElementSetMessagingTimeout(element, 0.25)

        notificationCenterPID = pid
        appElement = element

        // An observer reacts the instant a banner window appears, so most hidden
        // banners are gone before they finish sliding in. The timer covers banners
        // added to a window that already exists.
        var newObserver: AXObserver?
        guard AXObserverCreate(pid, notificationObserverCallback, &newObserver) == .success,
              let newObserver else { return }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        _ = AXObserverAddNotification(newObserver, element, kAXWindowCreatedNotification as CFString, refcon)
        _ = AXObserverAddNotification(newObserver, element, kAXCreatedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .defaultMode)
        observer = newObserver
    }

    private func detachFromNotificationCenter() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        appElement = nil
        notificationCenterPID = 0
    }

    // MARK: - Scanning

    fileprivate func scan() {
        guard mode != .showAll, let appElement else { return }
        let windows: [AXUIElement] = AX.attribute(appElement, kAXWindowsAttribute) ?? []
        guard !windows.isEmpty else { return }

        pruneRecentlyHandled()

        for window in windows where !isNotificationCenterSidebar(window) {
            var banners: [AXUIElement] = []
            collectBanners(in: window, depth: 0, into: &banners)
            for banner in banners {
                handle(banner)
            }
        }
    }

    /// The Notification Center sidebar (click the clock) holds your notification
    /// history and widgets. Leave it alone — only transient banners are filtered.
    ///
    /// Window size can't tell them apart: on macOS 15/26 the pop-up banner lives
    /// in a full-screen window. Nor can the word "widget" on its own — that same
    /// banner window always carries an empty `widgets-overlay-view`, and desktop
    /// widgets are separate Notification Center windows. What only the sidebar
    /// has is an actual widget (`widget-local:…`) in the same window as
    /// notifications.
    private func isNotificationCenterSidebar(_ window: AXUIElement) -> Bool {
        containsRealWidget(window, depth: 0)
    }

    private func containsRealWidget(_ element: AXUIElement, depth: Int) -> Bool {
        guard depth < 7 else { return false }
        let identifier: String = AX.attribute(element, kAXIdentifierAttribute) ?? ""
        if Self.isRealWidgetIdentifier(identifier) { return true }
        let children: [AXUIElement] = AX.attribute(element, kAXChildrenAttribute) ?? []
        return children.contains { containsRealWidget($0, depth: depth + 1) }
    }

    /// `widget-local:com.apple.weather:…` is a widget; `widgets-overlay-view` is
    /// just an empty layer on the banner window.
    static func isRealWidgetIdentifier(_ identifier: String) -> Bool {
        let lower = identifier.lowercased()
        guard lower.contains("widget"), !lower.contains("overlay") else { return false }
        return lower.hasPrefix("widget-") || lower.hasPrefix("widget:") || lower.contains(".widget")
    }

    private func collectBanners(in element: AXUIElement, depth: Int, into result: inout [AXUIElement]) {
        guard depth < 10 else { return }

        let subrole: String? = AX.attribute(element, kAXSubroleAttribute)
        if let subrole, subrole.hasPrefix("AXNotificationCenter"), !subrole.contains("Stack") {
            result.append(element)
            return
        }

        // Fallback for macOS versions that don't tag banners with a subrole: any
        // group offering its own "Close" action is a single banner. (Stacks offer
        // "Clear All" instead, so they are descended into, not closed whole.)
        let role: String? = AX.attribute(element, kAXRoleAttribute)
        if subrole == nil, role == (kAXGroupRole as String), Self.closeActionName(for: element) != nil {
            result.append(element)
            return
        }

        let children: [AXUIElement] = AX.attribute(element, kAXChildrenAttribute) ?? []
        for child in children {
            collectBanners(in: child, depth: depth + 1, into: &result)
        }
    }

    private func handle(_ banner: AXUIElement) {
        let info = Self.readBanner(banner)
        guard !info.app.isEmpty else { return }

        learn(info.app)

        guard shouldHide(info) else { return }

        let key = "\(info.app)|\(info.title)|\(info.body)"
        let alreadyLogged = recentlyHandled[key] != nil

        if Self.close(banner), !alreadyLogged {
            hiddenCount += 1
        }

        guard !alreadyLogged else { return }
        recentlyHandled[key] = Date()

        if keepHiddenInPanel {
            inbox.insert(
                CapturedNotification(app: info.app, title: info.title, body: info.body, date: Date()),
                at: 0
            )
            if inbox.count > Self.inboxLimit {
                inbox = Array(inbox.prefix(Self.inboxLimit))
            }
        }
    }

    private func shouldHide(_ info: BannerInfo) -> Bool {
        switch mode {
        case .showAll:
            return false
        case .hideAll:
            return true
        case .filter:
            // Match on the app name, or on the title — for some forwarded iPhone
            // banners the app's name is shown as the title instead.
            return isHidden(info.app) || (!info.title.isEmpty && isHidden(info.title))
        }
    }

    private func pruneRecentlyHandled() {
        let cutoff = Date().addingTimeInterval(-30)
        recentlyHandled = recentlyHandled.filter { $0.value > cutoff }
    }

    // MARK: - Diagnostics

    /// Posts a harmless test banner (from Script Editor, via AppleScript), so the
    /// filter can be tried without waiting for a real notification. ClipMate
    /// itself never posts notifications, so it never needs that permission.
    func sendTestBanner() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "display notification \"If you can read this for more than a moment, ClipMate did not hide it.\" with title \"ClipMate test\""
        ]
        try? process.run()
    }

    /// A text dump of what Notification Center exposes right now — roles,
    /// subroles, descriptions and actions, **no notification text beyond the
    /// first 40 characters**. Used to adapt the filter to a new macOS version.
    func diagnosticReport() -> String {
        var lines: [String] = []
        let version = ProcessInfo.processInfo.operatingSystemVersionString
        lines.append("ClipMate \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") — macOS \(version)")
        lines.append("Accessibility allowed: \(Self.hasAccessibilityPermission)")
        lines.append("Mode: \(mode.rawValue), running: \(isRunning), hidden so far: \(hiddenCount)")

        guard let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: Self.notificationCenterBundleID).first else {
            lines.append("Notification Center process not found.")
            return lines.joined(separator: "\n")
        }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        _ = AXUIElementSetMessagingTimeout(element, 0.5)
        let windows: [AXUIElement] = AX.attribute(element, kAXWindowsAttribute) ?? []
        lines.append("Windows: \(windows.count)")
        for (index, window) in windows.enumerated() {
            let size = AX.size(of: window).map { "\(Int($0.width))×\(Int($0.height))" } ?? "?"
            lines.append("Window \(index) \(size) sidebar=\(isNotificationCenterSidebar(window))")
            dump(window, depth: 1, into: &lines)
            var banners: [AXUIElement] = []
            collectBanners(in: window, depth: 0, into: &banners)
            lines.append("  → banners detected: \(banners.count)")
            for banner in banners {
                let info = Self.readBanner(banner)
                lines.append("    app=\"\(info.app)\" title=\"\(info.title.prefix(40))\" closeAction=\(Self.closeActionName(for: banner) ?? "none")")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func dump(_ element: AXUIElement, depth: Int, into lines: inout [String]) {
        guard depth < 12, lines.count < 400 else { return }
        let role: String = AX.attribute(element, kAXRoleAttribute) ?? "?"
        let subrole: String = AX.attribute(element, kAXSubroleAttribute) ?? ""
        let identifier: String = AX.attribute(element, kAXIdentifierAttribute) ?? ""
        let description: String = AX.attribute(element, kAXDescriptionAttribute) ?? ""
        var namesRef: CFArray?
        _ = AXUIElementCopyActionNames(element, &namesRef)
        let actions = ((namesRef as? [String]) ?? [])
            .map { $0.components(separatedBy: "\n").first ?? $0 }
            .joined(separator: ",")
        let indent = String(repeating: "  ", count: depth)
        lines.append("\(indent)\(role) [\(subrole)] id=\(identifier) desc=\"\(description.prefix(40))\" actions=\(actions)")
        let children: [AXUIElement] = AX.attribute(element, kAXChildrenAttribute) ?? []
        for child in children {
            dump(child, depth: depth + 1, into: &lines)
        }
    }

    // MARK: - Reading a banner

    private struct BannerInfo {
        var app: String
        var title: String
        var body: String
    }

    /// Pulls the app name, title and body out of a banner.
    ///
    /// Notification Center labels each banner with an accessibility description of
    /// the form "App, Title, Body". The text fields inside carry identifiers
    /// `title`, `subtitle` and `body`. Both are read; whichever is present wins.
    private static func readBanner(_ banner: AXUIElement) -> BannerInfo {
        let description: String = AX.attribute(banner, kAXDescriptionAttribute) ?? ""

        var title = ""
        var subtitle = ""
        var body = ""
        var otherTexts: [String] = []
        collectTexts(in: banner, depth: 0) { identifier, value in
            switch identifier {
            case "title": title = value
            case "subtitle": subtitle = value
            case "body": body = value
            default: otherTexts.append(value)
            }
        }

        let descriptionParts = description
            .components(separatedBy: ", ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var app = descriptionParts.first ?? ""
        // If the description just repeats the title, it is not the app name.
        if app == title, descriptionParts.count == 1 { app = "" }
        if app.isEmpty { app = otherTexts.first ?? title }

        if title.isEmpty, descriptionParts.count > 1 { title = descriptionParts[1] }
        if body.isEmpty {
            body = descriptionParts.count > 2
                ? descriptionParts.dropFirst(2).joined(separator: ", ")
                : otherTexts.dropFirst().joined(separator: " ")
        }
        if !subtitle.isEmpty {
            body = body.isEmpty ? subtitle : "\(subtitle) — \(body)"
        }

        return BannerInfo(
            app: String(app.prefix(40)),
            title: title,
            body: body
        )
    }

    private static func collectTexts(
        in element: AXUIElement,
        depth: Int,
        _ visit: (_ identifier: String, _ value: String) -> Void
    ) {
        guard depth < 6 else { return }
        let children: [AXUIElement] = AX.attribute(element, kAXChildrenAttribute) ?? []
        for child in children {
            let role: String? = AX.attribute(child, kAXRoleAttribute)
            if role == (kAXStaticTextRole as String),
               let value: String = AX.attribute(child, kAXValueAttribute),
               !value.isEmpty {
                let identifier: String = AX.attribute(child, kAXIdentifierAttribute) ?? ""
                visit(identifier, value)
            } else {
                collectTexts(in: child, depth: depth + 1, visit)
            }
        }
    }

    // MARK: - Closing a banner

    /// Performs the banner's own "Close" action — the ✕ that appears on hover.
    /// Returns whether a close action was found and performed.
    @discardableResult
    private static func close(_ banner: AXUIElement) -> Bool {
        if let name = closeActionName(for: banner) {
            return AXUIElementPerformAction(banner, name as CFString) == .success
        }

        // Fallback: a close button inside the banner.
        let children: [AXUIElement] = AX.attribute(banner, kAXChildrenAttribute) ?? []
        for child in children {
            let role: String? = AX.attribute(child, kAXRoleAttribute)
            guard role == (kAXButtonRole as String) else { continue }
            let label = [
                AX.attribute(child, kAXDescriptionAttribute) as String?,
                AX.attribute(child, kAXIdentifierAttribute) as String?,
                AX.attribute(child, kAXTitleAttribute) as String?
            ].compactMap { $0 }.joined(separator: " ").lowercased()
            if label.contains("close") {
                return AXUIElementPerformAction(child, kAXPressAction as CFString) == .success
            }
        }
        return false
    }

    /// The name of an element's own "Close" action, if it has one.
    ///
    /// Custom actions are named like "Name:Close\nTarget:0x0\nSelector:(null)".
    /// The description is checked too, in case the name is localised.
    private static func closeActionName(for element: AXUIElement) -> String? {
        var namesRef: CFArray?
        guard AXUIElementCopyActionNames(element, &namesRef) == .success,
              let names = namesRef as? [String] else { return nil }

        for name in names {
            var descriptionRef: CFString?
            _ = AXUIElementCopyActionDescription(element, name as CFString, &descriptionRef)
            let description = (descriptionRef as String?) ?? ""
            if "\(name) \(description)".lowercased().contains("close") {
                return name
            }
        }
        return nil
    }
}

/// Called by the AX observer on the main run loop whenever Notification Center
/// creates a window or element. Must be a context-free closure (C function pointer).
private let notificationObserverCallback: AXObserverCallback = { _, _, _, refcon in
    guard let refcon else { return }
    let service = Unmanaged<NotificationFilterService>.fromOpaque(refcon).takeUnretainedValue()
    Task { @MainActor in service.scan() }
}

// MARK: - Accessibility helpers

/// Tiny typed wrappers around the C Accessibility API.
enum AX {
    static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value else { return nil }
        return value as? T
    }

    static func size(of element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        // swiftlint:disable:next force_cast
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }
}
