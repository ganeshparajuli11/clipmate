import AppKit

/// Builds the application's main menu.
///
/// ## Why an agent app still needs a menu
/// ClipMate is `LSUIElement`, so no menu bar is ever drawn. It would be easy to
/// conclude a main menu is therefore pointless — but AppKit routes **key
/// equivalents** through `NSApp.mainMenu`, not directly to the focused control.
/// With no main menu, ⌘C / ⌘V / ⌘X / ⌘A / ⌘Z simply do nothing in every text
/// field the app owns: the pin fields in Settings and the shortcut recorders.
///
/// ## The nil-target trick
/// None of these items set a `target`. A nil target tells AppKit to walk the
/// responder chain and deliver the selector to whatever currently has focus, so a
/// single Edit menu makes editing work in every text field with no per-field code
/// and no wiring to maintain.
enum MainMenuBuilder {

    static func build() -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(applicationMenuItem())
        mainMenu.addItem(editMenuItem())
        return mainMenu
    }

    // MARK: - Application menu

    /// The first menu is the application menu by convention. It is never drawn for
    /// an agent app, but it gives ⌘Q and ⌘, somewhere to live.
    private static func applicationMenuItem() -> NSMenuItem {
        let appName = ProcessInfo.processInfo.processName
        let item = NSMenuItem()
        let menu = NSMenu(title: appName)

        menu.addItem(
            withTitle: "About \(appName)",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        menu.addItem(.separator())

        // Target stays nil so this reaches AppDelegate through the responder chain.
        menu.addItem(
            withTitle: "Settings…",
            action: Selector(("openSettingsFromMenu:")),
            keyEquivalent: ","
        )
        menu.addItem(.separator())

        let hide = menu.addItem(
            withTitle: "Hide \(appName)",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        hide.target = NSApp

        menu.addItem(.separator())

        let quit = menu.addItem(
            withTitle: "Quit \(appName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.target = NSApp

        item.submenu = menu
        return item
    }

    // MARK: - Edit menu

    /// The menu that actually matters: every item here has **no target**, so AppKit
    /// delivers it down the responder chain to the focused text field.
    private static func editMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Edit")

        // `undo:` and `redo:` are not exposed as typed selectors, hence the
        // string form. They still resolve correctly on NSUndoManager's client.
        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")

        let redo = menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]

        menu.addItem(.separator())

        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")

        let pasteMatch = menu.addItem(
            withTitle: "Paste and Match Style",
            action: #selector(NSTextView.pasteAsPlainText(_:)),
            keyEquivalent: "v"
        )
        pasteMatch.keyEquivalentModifierMask = [.command, .option, .shift]

        menu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        item.submenu = menu
        return item
    }
}
