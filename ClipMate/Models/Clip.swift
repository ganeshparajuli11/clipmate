import AppKit
import Foundation

/// One entry in the clipboard history: plain text, a set of files, or an image.
///
/// Stored as JSON in `UserDefaults`. Image *bytes* are never stored here — only the
/// path to a PNG written by `ClipImageStore`, because a clipboard image is far too
/// large for a defaults domain.
struct Clip: Codable, Hashable, Identifiable {

    enum Kind: String, Codable {
        case text
        case files
        case image
    }

    let kind: Kind
    /// Text payload. Empty for files and images.
    let text: String
    /// File system paths. For `.image` this is the single stored PNG.
    let paths: [String]
    /// Pixel dimensions, images only. Optional so older history still decodes.
    let width: Int?
    let height: Int?

    // MARK: - Construction

    init(text: String) {
        self.kind = .text
        self.text = text
        self.paths = []
        self.width = nil
        self.height = nil
    }

    init(files urls: [URL]) {
        self.kind = .files
        self.text = ""
        self.paths = urls.map(\.path)
        self.width = nil
        self.height = nil
    }

    init(imageAt url: URL, width: Int, height: Int) {
        self.kind = .image
        self.text = ""
        self.paths = [url.path]
        self.width = width
        self.height = height
    }

    // MARK: - Identity

    /// Stable identity used both for `ForEach` and for de-duplication.
    ///
    /// The prefix keeps a text clip that happens to read like a path distinct from
    /// an actual file clip.
    var id: String {
        switch kind {
        case .text: "t:\(text)"
        case .files: "f:\(paths.joined(separator: "\n"))"
        case .image: "i:\(paths.first ?? "")"
        }
    }

    // MARK: - Files

    var urls: [URL] {
        paths.map { URL(fileURLWithPath: $0) }
    }

    /// Paths that still exist on disk. Files can be moved or deleted after being
    /// copied, and a stale entry should not silently put a dead reference on the
    /// pasteboard.
    var existingURLs: [URL] {
        urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// True when everything this clip refers to has since disappeared.
    var isDangling: Bool {
        (kind == .files || kind == .image) && existingURLs.isEmpty
    }

    // MARK: - Display

    /// One-line label for the panel.
    var preview: String {
        switch kind {
        case .text:
            return text.singleLinePreview
        case .files:
            guard let first = paths.first else { return "No files" }
            let name = URL(fileURLWithPath: first).lastPathComponent
            return paths.count == 1 ? name : "\(name)  +\(paths.count - 1) more"
        case .image:
            guard let width, let height else { return "Image" }
            return "Image  \(width) × \(height)"
        }
    }

    /// Full text for the row's hover tooltip.
    var tooltip: String {
        switch kind {
        case .text: return text
        case .files: return paths.joined(separator: "\n")
        case .image: return preview
        }
    }

    /// Only text clips can be pinned — pins are plain strings that get copied as
    /// text, so a pinned file or image would paste as a path rather than content.
    var isPinnable: Bool {
        kind == .text
    }

    /// Icon for the row. Files use the real Finder icon; images use a thumbnail.
    var icon: RowIcon {
        switch kind {
        case .text:
            return .symbol("doc.on.clipboard")
        case .files:
            guard paths.count == 1, let path = paths.first,
                  FileManager.default.fileExists(atPath: path) else {
                return .symbol(isDangling ? "questionmark.folder" : "doc.on.doc.fill")
            }
            return .image(NSWorkspace.shared.icon(forFile: path))
        case .image:
            guard let path = paths.first, let thumb = ClipThumbnailCache.thumbnail(forPath: path) else {
                return .symbol("photo")
            }
            return .image(thumb)
        }
    }
}

/// Either an SF Symbol or a concrete image (Finder icons, image-clip thumbnails).
enum RowIcon: Hashable {
    case symbol(String)
    case image(NSImage)
}

/// Small in-memory cache of image-clip thumbnails.
///
/// SwiftUI re-evaluates a row's body often; decoding a multi-megabyte PNG each time
/// would make scrolling the panel visibly stutter.
enum ClipThumbnailCache {
    private static let cache = NSCache<NSString, NSImage>()
    private static let side: CGFloat = 32 // 16pt at 2x

    static func thumbnail(forPath path: String) -> NSImage? {
        if let cached = cache.object(forKey: path as NSString) { return cached }
        guard FileManager.default.fileExists(atPath: path),
              let full = NSImage(contentsOfFile: path) else { return nil }

        let thumb = NSImage(size: NSSize(width: side, height: side))
        thumb.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        full.draw(
            in: NSRect(x: 0, y: 0, width: side, height: side),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        thumb.unlockFocus()

        cache.setObject(thumb, forKey: path as NSString)
        return thumb
    }

    static func forget(path: String) {
        cache.removeObject(forKey: path as NSString)
    }
}
