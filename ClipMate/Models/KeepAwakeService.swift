import Foundation
import IOKit.ps
import IOKit.pwr_mgt

/// How long Keep Awake should stay on.
enum KeepAwakeDuration: Int, CaseIterable, Identifiable {
    case indefinitely = 0
    case minutes15 = 900
    case minutes30 = 1800
    case hour1 = 3600
    case hours2 = 7200
    case hours5 = 18000

    var id: Int { rawValue }

    /// `nil` means "until turned off".
    var interval: TimeInterval? {
        self == .indefinitely ? nil : TimeInterval(rawValue)
    }

    var title: String {
        switch self {
        case .indefinitely: "Until I turn it off"
        case .minutes15: "15 minutes"
        case .minutes30: "30 minutes"
        case .hour1: "1 hour"
        case .hours2: "2 hours"
        case .hours5: "5 hours"
        }
    }
}

/// Keeps the Mac (and optionally the display) awake — the same thing the
/// `caffeinate` command and apps like KeepingYouAwake / Amphetamine do.
///
/// Implemented with an IOKit power-management assertion, which is the official,
/// permission-free way to do it. The assertion is released automatically if
/// ClipMate quits or crashes, so the Mac can never get "stuck" awake.
@MainActor
final class KeepAwakeService: ObservableObject {

    enum Keys {
        static let keepDisplayOn = "clipmate.keepAwake.displayOn"
        static let defaultDuration = "clipmate.keepAwake.defaultDuration"
        static let activateAtLaunch = "clipmate.keepAwake.activateAtLaunch"
        static let batteryCutoffEnabled = "clipmate.keepAwake.batteryCutoffEnabled"
        static let batteryCutoffPercent = "clipmate.keepAwake.batteryCutoffPercent"
    }

    // MARK: - State

    @Published private(set) var isActive = false

    /// When the current session ends, or `nil` for "until turned off".
    @Published private(set) var endsAt: Date?

    // MARK: - Preferences

    /// Keep the *screen* on too (default). Off means only the Mac stays awake —
    /// downloads and builds keep running while the display is allowed to sleep.
    @Published var keepDisplayOn: Bool {
        didSet {
            defaults.set(keepDisplayOn, forKey: Keys.keepDisplayOn)
            // Re-take the assertion with the new type if a session is running.
            if isActive { createAssertion() }
        }
    }

    /// Duration used by the panel toggle, the menu bar ⌥-click, and the hotkey.
    @Published var defaultDuration: KeepAwakeDuration {
        didSet { defaults.set(defaultDuration.rawValue, forKey: Keys.defaultDuration) }
    }

    @Published var activateAtLaunch: Bool {
        didSet { defaults.set(activateAtLaunch, forKey: Keys.activateAtLaunch) }
    }

    /// Turn Keep Awake off when running on battery below `batteryCutoffPercent`.
    @Published var batteryCutoffEnabled: Bool {
        didSet { defaults.set(batteryCutoffEnabled, forKey: Keys.batteryCutoffEnabled) }
    }

    @Published var batteryCutoffPercent: Int {
        didSet { defaults.set(batteryCutoffPercent, forKey: Keys.batteryCutoffPercent) }
    }

    // MARK: - Private

    private let defaults: UserDefaults
    private var assertionID: IOPMAssertionID = 0
    private var hasAssertion = false
    private var expiryTimer: Timer?
    private var batteryTimer: Timer?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.keepDisplayOn = defaults.object(forKey: Keys.keepDisplayOn) as? Bool ?? true
        self.defaultDuration = KeepAwakeDuration(
            rawValue: defaults.integer(forKey: Keys.defaultDuration)
        ) ?? .indefinitely
        self.activateAtLaunch = defaults.bool(forKey: Keys.activateAtLaunch)
        self.batteryCutoffEnabled = defaults.object(forKey: Keys.batteryCutoffEnabled) as? Bool ?? true
        self.batteryCutoffPercent = defaults.object(forKey: Keys.batteryCutoffPercent) as? Int ?? 20
    }

    // MARK: - Control

    func toggle() {
        if isActive {
            deactivate()
        } else {
            activate(for: defaultDuration)
        }
    }

    /// Starts (or restarts) a session for the given duration.
    func activate(for duration: KeepAwakeDuration) {
        createAssertion()
        guard hasAssertion else { return }

        isActive = true
        expiryTimer?.invalidate()
        expiryTimer = nil

        if let interval = duration.interval {
            endsAt = Date().addingTimeInterval(interval)
            let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.deactivate() }
            }
            RunLoop.main.add(timer, forMode: .common)
            expiryTimer = timer
        } else {
            endsAt = nil
        }

        startBatteryWatch()
    }

    func deactivate() {
        releaseAssertion()
        expiryTimer?.invalidate()
        expiryTimer = nil
        batteryTimer?.invalidate()
        batteryTimer = nil
        isActive = false
        endsAt = nil
    }

    /// Short human description for the panel, e.g. "On · 42 min left".
    var statusText: String {
        guard isActive else { return "Off" }
        guard let endsAt else { return "On" }
        let remaining = max(0, endsAt.timeIntervalSinceNow)
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = remaining >= 3600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .abbreviated
        let text = formatter.string(from: max(60, remaining)) ?? ""
        return "On · \(text) left"
    }

    // MARK: - Assertion

    private func createAssertion() {
        releaseAssertion()

        // "PreventUserIdleDisplaySleep" also keeps the system awake; the
        // system-only variant lets the screen dim and sleep as usual.
        let type = keepDisplayOn
            ? kIOPMAssertionTypePreventUserIdleDisplaySleep
            : kIOPMAssertionTypePreventUserIdleSystemSleep

        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "ClipMate Keep Awake" as CFString,
            &assertionID
        )
        hasAssertion = (result == kIOReturnSuccess)
    }

    private func releaseAssertion() {
        guard hasAssertion else { return }
        _ = IOPMAssertionRelease(assertionID)
        hasAssertion = false
        assertionID = 0
    }

    // MARK: - Battery

    private func startBatteryWatch() {
        batteryTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkBattery() }
        }
        RunLoop.main.add(timer, forMode: .common)
        batteryTimer = timer
        checkBattery()
    }

    private func checkBattery() {
        guard isActive, batteryCutoffEnabled,
              let battery = Self.batteryState(),
              !battery.isCharging,
              battery.percent < batteryCutoffPercent else { return }
        deactivate()
    }

    /// Current internal-battery level, or `nil` on a desktop Mac.
    static func batteryState() -> (percent: Int, isCharging: Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                    .takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let onAC = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            return (current * 100 / max, onAC)
        }
        return nil
    }
}
