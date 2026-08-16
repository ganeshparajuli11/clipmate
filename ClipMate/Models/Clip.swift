import AppKit
import Foundation

/// One entry in the clipboard history: either plain text or a set of files.
///
/// Stored as JSON in `UserDefaults` rather than a bare `[String]` so that a file
/// clip can keep its list of paths intact.
struct Clip: Codable, Hashable, Identifiable {

    enum Kind: String, Codable {
        case text
        case files
    }

    let kind: Kind
    /// Text payload. Empty for file clips.
    let text: String
    /// File system paths. Empty for text clips.
    let paths: [String]

    // MARK: - Construction

    init(text: String) {
        self.kind = .text
        self.text = text
        self.paths = []
    }

    init(files urls: [URL]) {
        self.kind = .files
        self.text = ""
        self.paths = urls.map(\.path)
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
        }
    }

    // MARK: - Display

    var urls: [URL] {
        paths.map { URL(fileURLWithPath: $0) }
    }

    /// Paths that still exist on disk. Files can be moved or deleted after being
    /// copied, and a stale entry should not silently put a dead reference on the
    /// pasteboard.
    var existingURLs: [URL] {
        urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// True when every file this clip refers to has since disappeared.
    var isDangling: Bool {
        kind == .files && existingURLs.isEmpty
    }

    /// One-line label for the panel.
    var preview: String {
        switch kind {
        case .text:
            return text.singleLinePreview
        case .files:
            guard let first = paths.first else { return "No files" }
            let name = URL(fileURLWithPath: first).lastPathComponent
            if paths.count == 1 { return name }
            return "\(name)  +\(paths.count - 1) more"
        }
    }

    /// Full text for the row's hover tooltip.
    var tooltip: String {
        switch kind {
        case .text: return text
        case .files: return paths.joined(separator: "\n")
        }
    }

    /// Only text clips can be pinned — pins are plain strings that get copied as
    /// text, and a pinned file path would paste as text rather than as a file.
    var isPinnable: Bool {
        kind == .text
    }

    /// Icon for the row. File clips use the real Finder icon, which makes a folder
    /// obviously a folder and an image obviously an image.
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
        }
    }
}

/// Either an SF Symbol or a concrete image (used for Finder file icons).
enum RowIcon: Hashable {
    case symbol(String)
    case image(NSImage)
}
