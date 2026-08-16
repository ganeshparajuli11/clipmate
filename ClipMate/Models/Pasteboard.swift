import AppKit

/// Reads from and writes to the system pasteboard.
enum Pasteboard {

    // MARK: - Writing

    /// Puts plain text on the general pasteboard, replacing its contents.
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Puts file references on the pasteboard so Finder can paste them.
    ///
    /// `writeObjects` with `NSURL` publishes the file-URL representation Finder
    /// needs *and* a plain-text fallback, so pasting into a text field yields the
    /// path. Pasting in Finder with ⌘V copies; ⌥⌘V moves.
    static func copy(files urls: [URL]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls.map { $0 as NSURL })
    }

    /// Writes a whole clip, dispatching on its kind.
    static func copy(_ clip: Clip) {
        switch clip.kind {
        case .text:
            copy(clip.text)
        case .files:
            // Only put files that still exist on the pasteboard.
            copy(files: clip.existingURLs)
        }
    }

    // MARK: - Reading

    /// Snapshots whatever is currently on the pasteboard, or `nil` if it holds
    /// nothing ClipMate stores.
    ///
    /// Files are checked **first** on purpose: copying in Finder also puts a text
    /// representation on the pasteboard, so testing for a string first would
    /// record every file copy as a path string instead of as a real file clip.
    static func currentClip() -> Clip? {
        let pasteboard = NSPasteboard.general

        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            return Clip(files: urls)
        }

        if let text = pasteboard.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Clip(text: text)
        }

        return nil
    }
}
