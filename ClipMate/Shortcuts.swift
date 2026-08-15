import KeyboardShortcuts

/// Strongly-typed names for ClipMate's global keyboard shortcuts.
///
/// `KeyboardShortcuts` registers these through Carbon's hotkey API, which — unlike
/// an `NSEvent` global monitor — does **not** require the Accessibility permission.
/// Both shortcuts are re-recordable in Settings and take effect immediately.
extension KeyboardShortcuts.Name {
    /// Shows or hides the ClipMate panel. Same action as clicking the menu bar icon.
    ///
    /// Defaults to ⌘2, echoing the Windows clipboard-history shortcut.
    static let togglePanel = Self(
        "togglePanel",
        default: .init(.two, modifiers: [.command])
    )

    /// Starts an area screenshot immediately, without opening the panel first.
    ///
    /// Defaults to ⌘F1.
    static let takeScreenshot = Self(
        "takeScreenshot",
        default: .init(.f1, modifiers: [.command])
    )
}
