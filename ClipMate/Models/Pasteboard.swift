import AppKit

/// Writes to the system pasteboard.
///
/// ClipMate only ever *writes*. There is no timer, no `changeCount` watching, and
/// no background reading of the clipboard anywhere in the app — copying a pin is
/// the only interaction with the pasteboard.
enum Pasteboard {
    /// Puts `text` on the general pasteboard, replacing its contents.
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
