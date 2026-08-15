import SwiftUI

/// ClipMate is a menu-bar-only app (`LSUIElement` is `YES` in `Info.plist`), so this
/// `App` deliberately owns no visible windows.
///
/// Everything the user actually sees is created and owned by `AppDelegate`:
/// the `NSStatusItem` in the menu bar, the `NSPopover` panel, and the Settings
/// window. Driving those from AppKit rather than SwiftUI scenes keeps the
/// behaviour predictable for an agent app — in particular, a popover that can be
/// toggled from a global hotkey while another app is frontmost.
@main
struct ClipMateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // A SwiftUI `App` must declare at least one scene. This empty `Settings`
        // scene satisfies that requirement without putting anything on screen at
        // launch — the real Settings window is managed by `SettingsWindowController`
        // so that it behaves correctly for an `LSUIElement` app.
        Settings {
            EmptyView()
        }
    }
}
