import AppKit
import SwiftUI

/// Owns the Settings window.
///
/// ClipMate manages this window itself rather than using SwiftUI's `Settings`
/// scene. For an `LSUIElement` app there is no menu bar to open Settings from, and
/// the usual workaround — `NSApp.sendAction(Selector(("showSettingsWindow:")))` —
/// depends on a private selector whose name has already changed once between macOS
/// releases. A plain `NSWindowController` has no such moving parts.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    convenience init(settings: AppSettings, clipboard: ClipboardManager) {
        let root = SettingsView()
            .environmentObject(settings)
            .environmentObject(clipboard)

        let hostingController = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "ClipMate Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        // Keep the controller alive across close/reopen cycles.
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("ClipMateSettingsWindow")

        self.init(window: window)
        window.delegate = self
    }

    /// Brings the window forward, activating the app first.
    ///
    /// An agent app is not frontmost by default, so without the explicit activation
    /// the window would appear behind whatever the user was working in.
    func present() {
        NSApp.activateForPanel()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Hand focus back to the app the user came from rather than leaving an
        // invisible agent app "active" with no windows.
        NSApp.hide(nil)
    }
}

extension NSApplication {
    /// Activates the app, using the modern API where available.
    ///
    /// `activate(ignoringOtherApps:)` is deprecated from macOS 14 onward but is
    /// still the only option on our macOS 13 deployment target.
    func activateForPanel() {
        if #available(macOS 14.0, *) {
            activate()
        } else {
            activate(ignoringOtherApps: true)
        }
    }
}
