import AppKit
import Combine
import Foundation

/// Watches the system pasteboard and keeps a short, de-duplicated history of
/// recent clips — plain text or copied files.
///
/// ## How capture works
/// macOS has no "the clipboard changed" notification, so polling is the only
/// reliable approach. `NSPasteboard.changeCount` is a cheap monotonically-increasing
/// counter the system bumps on every write, so the 1-second timer compares it and
/// does *nothing at all* unless it moved. The pasteboard is only actually read once
/// per real copy, not once per second.
///
/// Because this watches the pasteboard rather than keystrokes, it captures cuts as
/// well as copies, from Finder, menus, right-click, or any other app.
///
/// History always starts **empty**. Nothing is ever seeded or pre-filled.
@MainActor
final class ClipboardManager: ObservableObject {

    /// Most-recent-first list of captured clips, free of duplicates.
    @Published private(set) var history: [Clip] = []

    private let defaults: UserDefaults
    private unowned let settings: AppSettings
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    /// The last `changeCount` we have already accounted for.
    private var lastChangeCount: Int

    /// One second is imperceptible and, thanks to the `changeCount` guard, free.
    private let pollInterval: TimeInterval = 1.0

    init(settings: AppSettings, defaults: UserDefaults = .standard) {
        self.settings = settings
        self.defaults = defaults
        // Start from the current value so whatever is already on the pasteboard at
        // launch is not re-captured as if it were new.
        self.lastChangeCount = NSPasteboard.general.changeCount
        self.history = Self.loadHistory(from: defaults)

        trimHistory()

        // Lowering the cap in Settings should take effect right away.
        settings.$historySize
            .receive(on: RunLoop.main)
            .sink { [weak self] newSize in
                self?.trimHistory(to: newSize)
                self?.persistHistory()
            }
            .store(in: &cancellables)
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - Persistence

    /// Loads history, migrating the old plain-`[String]` format if present.
    private static func loadHistory(from defaults: UserDefaults) -> [Clip] {
        // Current format: JSON-encoded `[Clip]`.
        if let data = defaults.data(forKey: AppSettings.Keys.history),
           let clips = try? JSONDecoder().decode([Clip].self, from: data) {
            return clips
        }

        // Legacy format: a plain string array from before file clips existed.
        // Convert rather than discard, so upgrading does not wipe the user's list.
        if let legacy = defaults.stringArray(forKey: AppSettings.Keys.history) {
            return legacy.map { Clip(text: $0) }
        }

        return []
    }

    private func persistHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        defaults.set(data, forKey: AppSettings.Keys.history)
    }

    // MARK: - Monitoring

    /// Begins polling the pasteboard. Safe to call more than once.
    func startMonitoring() {
        guard timer == nil else { return }

        let timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            // The timer fires on the main run loop, but hop explicitly so the
            // main-actor isolation is checked rather than assumed.
            Task { @MainActor in
                self?.pollPasteboard()
            }
        }
        // Keep firing while menus are open or a window is being resized.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    /// The whole hot path: one integer comparison in the common case.
    private func pollPasteboard() {
        let changeCount = NSPasteboard.general.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        guard let clip = Pasteboard.currentClip() else { return }
        record(clip)
    }

    // MARK: - History

    /// Inserts a clip at the front, moving it there if it was already present.
    private func record(_ clip: Clip) {
        // Remove-then-insert keeps the list duplicate-free and makes re-copying an
        // old clip promote it back to the top.
        history.removeAll { $0.id == clip.id }
        history.insert(clip, at: 0)
        trimHistory()
        persistHistory()
    }

    private func trimHistory(to size: Int? = nil) {
        let cap = size ?? settings.historySize
        if history.count > cap {
            history = Array(history.prefix(cap))
        }
    }

    /// Clears every stored clip. Pinned texts are untouched.
    func clearHistory() {
        history.removeAll()
        persistHistory()
    }

    /// Drops a single clip, e.g. one whose files have all been deleted.
    func remove(_ clip: Clip) {
        history.removeAll { $0.id == clip.id }
        persistHistory()
    }

    // MARK: - Copying

    /// Puts a clip back on the pasteboard and promotes it to the top of history.
    ///
    /// `lastChangeCount` is advanced past our own write so the panel updates
    /// instantly rather than waiting for the next poll, and the clip is not
    /// processed twice.
    ///
    /// - Returns: `false` if this was a file clip whose files have all gone
    ///   missing, in which case nothing is written to the pasteboard.
    @discardableResult
    func copy(_ clip: Clip) -> Bool {
        if clip.isDangling { return false }

        Pasteboard.copy(clip)
        lastChangeCount = NSPasteboard.general.changeCount

        // Re-record from what actually landed on the pasteboard, so a file clip
        // whose missing entries were filtered out is stored in its trimmed form.
        record(clip.kind == .files ? Clip(files: clip.existingURLs) : clip)
        return true
    }

    /// Convenience for pinned texts, which are plain strings.
    func copy(text: String) {
        Pasteboard.copy(text)
        lastChangeCount = NSPasteboard.general.changeCount
        record(Clip(text: text))
    }
}
