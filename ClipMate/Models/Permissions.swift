import AppKit
import ApplicationServices
import CoreGraphics

/// The macOS permissions ClipMate can use, what each one is for, and how to ask.
///
/// ClipMate's rule: **explain first, then ask.** No permission is requested at
/// launch. Each is requested only when you use the feature that needs it, and only
/// after ClipMate has said in plain words what it will be able to see.
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
            // Shows the system prompt the first time; afterwards it does nothing,
            // so the Settings pane is opened as well.
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
}

/// One-off "here's what this will access" prompts shown before a permission is
/// requested, so the system dialog never comes out of nowhere.
@MainActor
enum PermissionExplainer {

    private enum Keys {
        static let screenRecordingExplained = "clipmate.permissions.screenRecordingExplained"
        static let notificationsConsented = "clipmate.permissions.notificationsConsented"
    }

    /// Call before a screenshot or screen-text capture.
    ///
    /// - Returns: `true` to go ahead with the capture now. The first time,
    ///   when the permission is missing, ClipMate explains what it will see; if the
    ///   user agrees, the system prompt is shown and the capture is skipped so they
    ///   can grant it first.
    static func prepareForScreenCapture() -> Bool {
        let defaults = UserDefaults.standard
        if Permission.screenRecording.isGranted { return true }
        // Explained once already — let macOS handle it from here. (Its permission
        // check can lag behind the switch in System Settings until relaunch, so
        // never block the capture on it a second time.)
        if defaults.bool(forKey: Keys.screenRecordingExplained) { return true }

        defaults.set(true, forKey: Keys.screenRecordingExplained)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "ClipMate needs Screen Recording permission"
        alert.informativeText = """
            To take a screenshot or copy text from the screen, macOS requires the Screen Recording permission.

            What ClipMate sees: \(Permission.screenRecording.whatWeAccess)

            Click Continue, switch ClipMate on in System Settings ▸ Privacy & Security ▸ Screen & System Audio Recording, then try again. macOS may ask you to reopen ClipMate.
            """
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Not Now")
        NSApp.activateForPanel()

        if alert.runModal() == .alertFirstButtonReturn {
            Permission.screenRecording.request()
        }
        return false
    }

    /// Call before turning on notification control.
    ///
    /// Asks once for consent to read notification banners (even if Accessibility
    /// was already granted for Finder cut & paste — it's a different use of it),
    /// then requests Accessibility if it is missing.
    ///
    /// - Returns: whether the user agreed.
    static func confirmNotificationAccess() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Keys.notificationsConsented) {
            if !Permission.accessibility.isGranted { Permission.accessibility.request() }
            return true
        }

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
}
