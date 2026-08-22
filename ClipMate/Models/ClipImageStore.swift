import AppKit
import Foundation

/// On-disk storage for image clips.
///
/// ## Why images are not kept in `UserDefaults`
/// A single Retina screenshot is several megabytes. `UserDefaults` is loaded into
/// memory wholesale and synced by the system, so putting image bytes there would
/// bloat every launch. Images therefore live as ordinary PNG files, and the history
/// entry in `UserDefaults` stores only the path.
///
/// This mirrors the split between the clipboard and real storage: the pasteboard is
/// volatile OS memory that a copy never persists, so anything that must survive a
/// reboot has to be written somewhere itself.
enum ClipImageStore {

    /// `~/Library/Application Support/ClipMate/Images`
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent("ClipMate", isDirectory: true)
            .appendingPathComponent("Images", isDirectory: true)
    }

    /// Writes PNG data and returns its file URL, or nil if the write failed.
    static func save(_ pngData: Data) -> URL? {
        let folder = directory
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let url = folder.appendingPathComponent("\(UUID().uuidString).png")
        do {
            // `.atomic` so a crash mid-write can never leave a truncated PNG that
            // would later render as a broken thumbnail.
            try pngData.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    static func delete(_ url: URL) {
        // Only ever delete inside our own directory — a malformed history entry
        // must not be able to point the app at an arbitrary file.
        guard url.standardizedFileURL.path.hasPrefix(directory.standardizedFileURL.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Removes stored images no longer referenced by any clip.
    ///
    /// Called after the history is trimmed or cleared, so dropping a clip does not
    /// leave its megabytes behind forever.
    static func pruneOrphans(keeping referenced: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return }

        for file in files where !referenced.contains(file.standardizedFileURL.path) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Total bytes currently used, for display in Settings.
    static func diskUsage() -> Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }

        return files.reduce(into: Int64(0)) { total, file in
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
    }
}
