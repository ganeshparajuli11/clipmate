import AppKit
import Foundation

/// Thin wrapper around macOS's built-in `/usr/sbin/screencapture` tool.
///
/// Shelling out is deliberate. The alternative — `ScreenCaptureKit` — would mean
/// building our own region-selection overlay and would still need the same Screen
/// Recording permission. `screencapture -i` gives us Apple's own crosshair
/// selection, Escape-to-cancel, and space-to-grab-a-window for free.
///
/// This is the *only* part of ClipMate that can trigger a permission prompt, and
/// only the first time the user takes a screenshot. macOS presents that prompt
/// itself; the app never asks up front.
enum ScreenshotService {

    /// Exit code `screencapture` returns when the user presses Escape.
    private static let userCancelledExitCode: Int32 = 1

    private static let executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")

    enum Result {
        case savedToFile(URL)
        case copiedToClipboard
        /// User pressed Escape. Not an error.
        case cancelled
        case failed(String)
    }

    /// Starts an interactive region capture.
    ///
    /// Returns immediately; the process runs off the main thread so the crosshair
    /// never blocks the UI. `completion` is delivered on the main actor.
    ///
    /// - Parameter destination: read at capture time, so a choice made in the
    ///   mini-prompt moments earlier is always the one that applies.
    static func captureInteractive(
        to destination: ScreenshotDestination,
        completion: @escaping @MainActor (Result) -> Void
    ) {
        var arguments = ["-i"] // interactive region selection
        var fileURL: URL?

        switch destination {
        case .clipboard:
            // `-c` sends the image straight to the clipboard. Combined with `-i`
            // this writes nothing to disk at all, so there is no temporary file to
            // clean up whether the user completes or cancels.
            arguments.append("-c")
        case .desktop:
            guard let url = makeDesktopFileURL() else {
                Task { @MainActor in completion(.failed("Could not locate the Desktop folder.")) }
                return
            }
            fileURL = url
            arguments.append(url.path)
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        process.terminationHandler = { process in
            let status = process.terminationStatus

            // Belt and braces: if a capture did not succeed, make sure we never
            // leave a stray or zero-byte file behind on the Desktop.
            defer {
                if status != 0, let fileURL {
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }

            Task { @MainActor in
                if status == 0 {
                    if let fileURL {
                        completion(.savedToFile(fileURL))
                    } else {
                        completion(.copiedToClipboard)
                    }
                } else if status == userCancelledExitCode {
                    completion(.cancelled)
                } else {
                    completion(.failed("screencapture exited with code \(status)."))
                }
            }
        }

        do {
            try process.run()
        } catch {
            if let fileURL {
                try? FileManager.default.removeItem(at: fileURL)
            }
            Task { @MainActor in completion(.failed(error.localizedDescription)) }
        }
    }

    /// Builds a timestamped, collision-free PNG path on the Desktop, e.g.
    /// `ClipMate 2026-08-15 at 17.42.09.png`.
    private static func makeDesktopFileURL() -> URL? {
        guard let desktop = FileManager.default.urls(
            for: .desktopDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        let formatter = DateFormatter()
        // Fixed locale so the filename is stable regardless of the user's region.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let stamp = formatter.string(from: Date())

        var candidate = desktop.appendingPathComponent("ClipMate \(stamp).png")

        // Two captures inside the same second would otherwise collide.
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = desktop.appendingPathComponent("ClipMate \(stamp) (\(suffix)).png")
            suffix += 1
        }
        return candidate
    }
}
