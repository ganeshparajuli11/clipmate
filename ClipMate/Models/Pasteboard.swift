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

    /// Puts an image on the pasteboard carrying **both PNG and TIFF** data.
    ///
    /// Receiving apps ask for different types — Preview and Finder reach for TIFF,
    /// browsers and chat apps reach for PNG. Publishing both representations on a
    /// *single* `NSPasteboardItem` lets the receiver pick whichever it understands,
    /// so a paste never silently fails. Two separate items would instead look like
    /// two separate images.
    ///
    /// `clearContents()` first is mandatory: without it, stale types left by the
    /// previous copy survive and a receiver can pick one of those instead.
    static func copy(imagePNG pngData: Data) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let item = NSPasteboardItem()
        item.setData(pngData, forType: .png)
        if let tiff = NSBitmapImageRep(data: pngData)?.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        pasteboard.writeObjects([item])
    }

    /// Writes a whole clip, dispatching on its kind.
    static func copy(_ clip: Clip) {
        switch clip.kind {
        case .text:
            copy(clip.text)
        case .files:
            // Only put files that still exist on the pasteboard.
            copy(files: clip.existingURLs)
        case .image:
            guard let path = clip.paths.first,
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return }
            copy(imagePNG: data)
        }
    }

    // MARK: - Reading

    /// PNG data plus pixel dimensions for an image currently on the pasteboard.
    static func currentImage() -> (png: Data, width: Int, height: Int)? {
        let pasteboard = NSPasteboard.general
        guard let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff),
              let rep = NSBitmapImageRep(data: data) else { return nil }

        // Normalise to PNG on the way in, so storage and the copy-back path only
        // ever deal with one format.
        let png = rep.representation(using: .png, properties: [:]) ?? data
        return (png, rep.pixelsWide, rep.pixelsHigh)
    }

    /// Snapshots whatever is currently on the pasteboard, or `nil` if it holds
    /// nothing ClipMate stores.
    ///
    /// Order matters. Files are checked **first** because copying in Finder also
    /// puts a text representation on the pasteboard, and testing for a string first
    /// would record every file copy as a path string. Text is checked **before**
    /// images because apps that copy an image often also supply its URL as text,
    /// and the text is usually what the user actually wanted; a genuine image copy
    /// (Preview, a screenshot) carries no string at all and falls through here.
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

        if let image = currentImage(), let stored = ClipImageStore.save(image.png) {
            return Clip(imageAt: stored, width: image.width, height: image.height)
        }

        return nil
    }
}
