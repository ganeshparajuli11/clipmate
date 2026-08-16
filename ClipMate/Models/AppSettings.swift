import Foundation
import ServiceManagement
import SwiftUI

/// Where a captured screenshot should end up.
enum ScreenshotDestination: String, CaseIterable, Identifiable {
    /// Save a timestamped PNG to the user's Desktop.
    case desktop
    /// Put the image straight onto the clipboard. No file is written at all.
    case clipboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .desktop: "Save to Desktop"
        case .clipboard: "Copy to clipboard"
        }
    }

    /// Short label used on the mini-prompt's buttons.
    var shortTitle: String {
        switch self {
        case .desktop: "Save"
        case .clipboard: "Copy"
        }
    }
}

/// Every user-tweakable value in ClipMate, persisted to `UserDefaults`.
///
/// Each `@Published` property writes through on `didSet`, so a change made in
/// Settings is on disk before the user's next keystroke — quitting, relaunching, or
/// updating the app never loses pins.
@MainActor
final class AppSettings: ObservableObject {

    /// Namespaced `UserDefaults` keys.
    enum Keys {
        static let pins = "clipmate.pins"
        static let history = "clipmate.history"
        static let historySize = "clipmate.historySize"
        static let screenshotToClipboard = "clipmate.screenshotToClipboard"
        static let screenshotAskFirst = "clipmate.screenshotAskFirst"
        static let screenshotChoiceRemembered = "clipmate.screenshotChoiceRemembered"
        static let finderCutEnabled = "clipmate.finderCutEnabled"
    }

    /// ClipMate always offers this many pinned slots in Settings.
    static let pinCount = 4

    /// Allowed range for the clipboard history cap.
    ///
    /// The panel sizes itself to its content rather than scrolling, so the upper
    /// bound keeps the popover from growing taller than a small laptop display.
    static let historySizeRange = 3...12

    private let defaults: UserDefaults

    // MARK: - Pins

    /// The four pin slots, in Settings order. Always exactly `pinCount` entries;
    /// empty strings mean "unused" and are simply not rendered in the panel.
    ///
    /// There is no seeded or sample content — a fresh install starts completely
    /// empty and the app never injects placeholder text.
    @Published var pins: [String] {
        didSet { defaults.set(pins, forKey: Keys.pins) }
    }

    /// Pins that actually have text, in slot order, with the gaps closed up.
    ///
    /// This is what the panel renders: set pin 1 and pin 3 and you get two rows,
    /// no empty row between them.
    var visiblePins: [String] {
        pins.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Index of the first unused pin slot, or `nil` when all four are taken.
    var firstEmptyPinSlot: Int? {
        pins.firstIndex { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Whether `text` is already sitting in one of the pin slots.
    func isPinned(_ text: String) -> Bool {
        pins.contains(text)
    }

    /// Pins `text` into the first free slot. Returns `false` if all slots are full,
    /// so the caller can say so rather than overwriting something silently.
    @discardableResult
    func pin(_ text: String) -> Bool {
        guard !isPinned(text) else { return true }
        guard let slot = firstEmptyPinSlot else { return false }
        pins[slot] = text
        return true
    }

    /// Clears whichever slots hold `text`.
    func unpin(_ text: String) {
        for index in pins.indices where pins[index] == text {
            pins[index] = ""
        }
    }

    // MARK: - Clipboard history

    /// How many recent clips to keep. Clamped to `historySizeRange`.
    @Published var historySize: Int {
        didSet {
            // Assigning here does not re-enter `didSet`, so this settles in one pass.
            let clamped = historySize.clamped(to: Self.historySizeRange)
            if clamped != historySize {
                historySize = clamped
            }
            defaults.set(clamped, forKey: Keys.historySize)
        }
    }

    // MARK: - Screenshots

    /// The effective destination, and the one the radio group in Settings shows.
    @Published var screenshotDestination: ScreenshotDestination {
        didSet {
            defaults.set(
                screenshotDestination == .clipboard,
                forKey: Keys.screenshotToClipboard
            )
        }
    }

    /// "Ask me the first time, then remember my choice."
    ///
    /// Turning this on (or off) resets the remembered answer, so the next capture
    /// asks once more.
    @Published var askScreenshotDestinationFirstTime: Bool {
        didSet {
            defaults.set(askScreenshotDestinationFirstTime, forKey: Keys.screenshotAskFirst)
            guard !isSyncingScreenshotChoice else { return }
            hasRememberedScreenshotChoice = false
        }
    }

    /// Whether the user has answered the prompt since the toggle was last flipped.
    @Published private(set) var hasRememberedScreenshotChoice: Bool {
        didSet {
            defaults.set(hasRememberedScreenshotChoice, forKey: Keys.screenshotChoiceRemembered)
        }
    }

    private var isSyncingScreenshotChoice = false

    /// True when the next capture should show the Copy / Save mini-prompt.
    var shouldAskForScreenshotDestination: Bool {
        askScreenshotDestinationFirstTime && !hasRememberedScreenshotChoice
    }

    /// Stores the answer from the mini-prompt. Also moves the radio selection in
    /// Settings so the two never disagree.
    func rememberScreenshotChoice(_ destination: ScreenshotDestination) {
        isSyncingScreenshotChoice = true
        screenshotDestination = destination
        hasRememberedScreenshotChoice = true
        isSyncingScreenshotChoice = false
    }

    // MARK: - Finder cut & paste

    /// Opt-in: make ⌘X cut and ⌘V move inside Finder, Windows style.
    ///
    /// Off by default and deliberately so — turning it on is what triggers the
    /// Accessibility request. A user who leaves it alone is never asked for
    /// anything beyond the one-off Screen Recording prompt for screenshots.
    @Published var finderCutEnabled: Bool {
        didSet { defaults.set(finderCutEnabled, forKey: Keys.finderCutEnabled) }
    }

    // MARK: - Launch at login

    /// Mirrors the app's `SMAppService` registration state.
    ///
    /// Not persisted to `UserDefaults` — the login-item database is the source of
    /// truth, so we read it back rather than keeping a copy that could drift.
    @Published var launchAtLogin: Bool {
        didSet {
            guard !isSyncingLaunchAtLogin else { return }
            applyLaunchAtLogin(launchAtLogin)
        }
    }

    /// Set when registering/unregistering the login item fails, so Settings can
    /// explain instead of silently snapping the toggle back.
    @Published private(set) var launchAtLoginError: String?

    private var isSyncingLaunchAtLogin = false

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedPins = defaults.stringArray(forKey: Keys.pins) ?? []
        self.pins = Self.normalisePins(storedPins)

        let storedSize = defaults.object(forKey: Keys.historySize) as? Int
        self.historySize = (storedSize ?? 6).clamped(to: Self.historySizeRange)

        let toClipboard = defaults.bool(forKey: Keys.screenshotToClipboard)
        self.screenshotDestination = toClipboard ? .clipboard : .desktop

        self.askScreenshotDestinationFirstTime = defaults.bool(forKey: Keys.screenshotAskFirst)
        self.hasRememberedScreenshotChoice = defaults.bool(forKey: Keys.screenshotChoiceRemembered)

        self.finderCutEnabled = defaults.bool(forKey: Keys.finderCutEnabled)
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Pads or trims a stored pin array to exactly `pinCount` entries, padding with
    /// empty slots — never with sample text.
    private static func normalisePins(_ stored: [String]) -> [String] {
        var pins = stored
        if pins.count > pinCount {
            pins = Array(pins.prefix(pinCount))
        }
        while pins.count < pinCount {
            pins.append("")
        }
        return pins
    }

    // MARK: - Login item

    /// Re-reads login-item state from the system, in case the user removed ClipMate
    /// from System Settings ▸ General ▸ Login Items behind our back.
    func refreshLaunchAtLoginStatus() {
        let isEnabled = SMAppService.mainApp.status == .enabled
        guard isEnabled != launchAtLogin else { return }
        isSyncingLaunchAtLogin = true
        launchAtLogin = isEnabled
        isSyncingLaunchAtLogin = false
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                // `register()` throws if already registered, so check first.
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            launchAtLoginError = nil
        } catch {
            // Usually means the app is running from Xcode's DerivedData rather than
            // a stable location such as /Applications.
            launchAtLoginError = error.localizedDescription
            isSyncingLaunchAtLogin = true
            launchAtLogin = !enabled
            isSyncingLaunchAtLogin = false
        }
    }
}

extension Comparable {
    /// Clamps a value into a closed range.
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
