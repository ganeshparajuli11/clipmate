import AppKit
import Foundation
import Vision

/// On-device text recognition (OCR) using Apple's Vision framework.
///
/// Everything runs locally — Vision ships with macOS, is free, needs no network
/// and no permission. It is the same engine behind Live Text in Preview and Photos.
///
/// Recognition is CPU/Neural-Engine heavy (a Retina screenshot takes a few hundred
/// milliseconds), so every entry point here is `async` and does the work off the
/// main thread.
enum TextRecognizer {

    enum RecognitionError: LocalizedError {
        case unreadableImage
        case noTextFound

        var errorDescription: String? {
            switch self {
            case .unreadableImage: "The image could not be read."
            case .noTextFound: "No text was found in the image."
            }
        }
    }

    // MARK: - Public API

    /// Recognises the text in the image file at `url`.
    static func recognizeText(at url: URL) async throws -> String {
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw RecognitionError.unreadableImage
        }
        return try await recognizeText(in: cgImage)
    }

    /// Recognises the text in a `CGImage`, returned in natural reading order with
    /// one line of output per visual line of text.
    static func recognizeText(in cgImage: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try performRecognition(on: cgImage)
        }.value
    }

    /// Whether a file looks like an image Vision can read, judged by extension.
    static func isImageFile(_ url: URL) -> Bool {
        let imageExtensions: Set<String> = [
            "png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp"
        ]
        return imageExtensions.contains(url.pathExtension.lowercased())
    }

    // MARK: - Implementation

    private static func performRecognition(on cgImage: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        // `.accurate` is noticeably better on small UI text and screenshots; the
        // extra few hundred ms is fine for a user-initiated action.
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // Detects the language automatically (macOS 13+), so English, Spanish,
        // German, French, Chinese, etc. all work without a setting.
        request.automaticallyDetectsLanguage = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        let observations = request.results ?? []
        let text = assembleLines(from: observations)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RecognitionError.noTextFound
        }
        return text
    }

    /// Groups recognised fragments into visual lines and orders them
    /// top-to-bottom, left-to-right.
    ///
    /// Vision returns one observation per text *block*, and its order is not
    /// guaranteed to be reading order — two columns of a table can interleave. Vision
    /// coordinates are normalised with the origin at the **bottom-left**, so "top"
    /// means the largest `y`.
    private static func assembleLines(from observations: [VNRecognizedTextObservation]) -> String {
        struct Fragment {
            let text: String
            let box: CGRect
        }

        let fragments: [Fragment] = observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return Fragment(text: candidate.string, box: observation.boundingBox)
        }
        .sorted { $0.box.midY > $1.box.midY }

        var lines: [[Fragment]] = []
        for fragment in fragments {
            // Same line if the vertical centres are within half a line height.
            if let last = lines.last?.first,
               abs(last.box.midY - fragment.box.midY) < min(last.box.height, fragment.box.height) * 0.5 {
                lines[lines.count - 1].append(fragment)
            } else {
                lines.append([fragment])
            }
        }

        return lines
            .map { line in
                line.sorted { $0.box.minX < $1.box.minX }
                    .map(\.text)
                    .joined(separator: " ")
            }
            .joined(separator: "\n")
    }
}

// MARK: - Capturing text from the screen

extension TextRecognizer {

    enum ScreenCaptureResult {
        case recognized(String)
        case cancelled
        case failed(String)
    }

    /// Lets the user drag-select any area of the screen and returns the text in it.
    ///
    /// The capture goes to a temporary file rather than the clipboard, so the image
    /// itself never pollutes the clipboard history — only the recognised text does.
    static func captureTextFromScreen() async -> ScreenCaptureResult {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipmate-ocr-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let status: Int32 = await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            // -i interactive selection, -x no shutter sound.
            process.arguments = ["-i", "-x", tempURL.path]
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: -1)
            }
        }

        // screencapture exits 0 even when the user presses Escape in some macOS
        // versions, so the presence of the file is the real success signal.
        guard FileManager.default.fileExists(atPath: tempURL.path) else {
            return status == -1
                ? .failed("Could not start the screen capture tool.")
                : .cancelled
        }

        do {
            return .recognized(try await recognizeText(at: tempURL))
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
