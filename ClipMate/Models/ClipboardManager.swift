import AppKit
import Combine
import Foundation

/// Watches the system pasteboard and keeps a short, de-duplicated history of
/// plain-text clips.
///
/// ## How capture works
/// macOS has no "the clipboard changed" notification, so polling is the only
/// reliable approach. `NSPasteboard.changeCount` is a cheap monotonically-increasing
/// counter the system bumps on every write, so the 1-second timer compares it and
/// does *nothing at all* unless it moved. Reading pasteboard contents — the only
/// non-trivial work — happens once per actual copy, not once per second.
///
/// Because this watches the pasteboard rather than keystrokes, it captures
/// **⌘X (cut) exactly like ⌘C (copy)** — both write to the same pasteboard — along
/// with copies made from menus, right-click, or any other app entirely.
///
/// History always starts **empty**. Nothing is ever seeded or pre-filled; the list
/// only ever contains things the user actually copied.
@MainActor
final class ClipboardManager: ObservableObject {

    /// Most-recent-first list of captured clips. Guaranteed free of duplicates,
    /// which is what lets the views key rows by their text.
    @Published private(set) var history: [String] = []

    private let defaults: UserDefaults
    private unowned let settings: AppSettings
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    /// The last `changeCount` we have already accounted for.
    private var lastChangeCount: Int

    /// How often to check the pasteboard. One second is imperceptible and, thanks
    /// to the `changeCount` guard, essentially free.
    private let pollInterval: TimeInterval = 1.0

    init(settings: AppSettings, defaults: UserDefaults = .standard) {
        self.settings = settings
        self.defaults = defaults
        // Start from the current value so whatever happens to be on the pasteboard
        // at launch is not re-captured as if it were brand new.
        self.lastChangeCount = NSPasteboard.general.changeCount
        self.history = defaults.stringArray(forKey: AppSettings.Keys.history) ?? []

        trimHistory()

        // Lowering the cap in Settings should take effect right away, not after the
        // next copy.
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
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        // Text-only by design. Images and file promises are ignored rather than
        // stored, which keeps memory flat and `UserDefaults` small.
        guard let text = pasteboard.string(forType: .string) else { return }
        record(text)
    }

    // MARK: - History

    /// Inserts a clip at the front, moving it there if it was already present.
    private func record(_ text: String) {
        // Ignore clips that are empty or pure whitespace — usually an artefact of
        // an app clearing the pasteboard rather than something the user copied.
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Remove-then-insert is what keeps the list duplicate-free and makes
        // re-copying an old clip promote it back to the top.
        history.removeAll { $0 == text }
        history.insert(text, at: 0)
        trimHistory()
        persistHistory()
    }

    private func trimHistory(to size: Int? = nil) {
        let cap = size ?? settings.historySize
        if history.count > cap {
            history = Array(history.prefix(cap))
        }
    }

    private func persistHistory() {
        defaults.set(history, forKey: AppSettings.Keys.history)
    }

    /// Clears every stored clip. Pinned texts are untouched.
    func clearHistory() {
        history.removeAll()
        persistHistory()
    }

    /// Removes a single clip from history.
    func remove(_ text: String) {
        history.removeAll { $0 == text }
        persistHistory()
    }

    // MARK: - Copying

    /// Puts `text` on the system pasteboard and promotes it to the top of history.
    ///
    /// The write is recorded synchronously and `lastChangeCount` is advanced past
    /// our own write, so the panel updates instantly instead of waiting up to a
    /// second for the poll to notice — and the clip is not processed twice.
    func copy(_ text: String) {
        Pasteboard.copy(text)
        lastChangeCount = NSPasteboard.general.changeCount
        record(text)
    }
}
