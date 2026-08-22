import KeyboardShortcuts

/// Strongly-typed names for ClipMate's global keyboard shortcuts.
///
/// `KeyboardShortcuts` registers these through Carbon's hotkey API, which — unlike
/// an `NSEvent` global monitor — does **not** require the Accessibility permission.
/// Both shortcuts are re-recordable in Settings and take effect immediately.
extension KeyboardShortcuts.Name {

    /// Shows or hides the panel — ClipMate's answer to Windows' Win+V.
    ///
    /// Defaults to ⇧⌘E. Function-key and plain ⌘-digit combinations were avoided
    /// deliberately: ⌘F1 is claimed by the system for display mirroring, and
    /// ⌘-digit is taken by tab switching in most browsers and editors.
    static let togglePanel = Self(
        "togglePanel",
        default: .init(.e, modifiers: [.command, .shift])
    )

    /// Starts an area screenshot immediately, without opening the panel first.
    ///
    /// Defaults to ⇧⌘D. Note this shadows Finder's "go to Desktop" shortcut while
    /// ClipMate is running; re-record it in Settings if you use that.
    static let takeScreenshot = Self(
        "takeScreenshot",
        default: .init(.d, modifiers: [.command, .shift])
    )
}
