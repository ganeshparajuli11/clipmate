import AppKit
import Combine
import KeyboardShortcuts
import SwiftUI

/// Owns every piece of AppKit state in ClipMate: the menu bar item, the panel
/// popover, both global hotkeys, and the Settings window.
///
/// Panel toggling funnels through a single `togglePanel()`, so the menu bar click
/// and the hotkey behave identically. Screenshots funnel through a single
/// `takeScreenshot()`, so the footer button and the screenshot hotkey share one
/// code path including the ask-once prompt.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Model

    private let settings = AppSettings()
    private lazy var clipboard = ClipboardManager(settings: settings)
    private let finderCut = FinderCutService()

    // MARK: - AppKit state

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var settingsWindowController: SettingsWindowController?
    private let screenshotChoice = ScreenshotChoiceController()

    /// Closes the panel when the user clicks outside it.
    ///
    /// `NSPopover.behavior = .transient` handles most cases, but a popover shown
    /// from a global hotkey while another app is frontmost does not always get the
    /// dismissal event.
    private var globalEventMonitor: Any?

    /// Handles Escape while the panel is open.
    private var escapeMonitor: Any?

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Must come first: without a main menu, ⌘C/⌘V/⌘X/⌘A/⌘Z do nothing in the
        // app's own text fields, because AppKit routes key equivalents through
        // the menu rather than straight to the focused control.
        NSApp.mainMenu = MainMenuBuilder.build()

        configureStatusItem()
        configurePopover()
        configureHotkeys()
        clipboard.startMonitoring()
        configureFinderCut()
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboard.stopMonitoring()
        finderCut.stop()
        removePanelMonitors()
    }

    // MARK: - Status item

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = item.button {
            // TODO: Drop a custom pink glyph in here.
            // Add it to Assets.xcassets as a template image named "MenuBarIcon" and
            // swap the two lines below for:
            //     button.image = NSImage(named: "MenuBarIcon")
            // Keeping `isTemplate = true` is what lets macOS tint the glyph
            // automatically for light and dark menu bars.
            let image = NSImage(
                systemSymbolName: "doc.on.clipboard",
                accessibilityDescription: "ClipMate"
            )
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(statusItemClicked)
            button.toolTip = "ClipMate — pinned texts and clipboard history"
        }

        statusItem = item
    }

    @objc private func statusItemClicked() {
        togglePanel()
    }

    // MARK: - Popover

    private func configurePopover() {
        let panel = PanelView(
            onScreenshot: { [weak self] in self?.takeScreenshot() },
            onOpenSettings: { [weak self] in self?.openSettings() }
        )
        .environmentObject(settings)
        .environmentObject(clipboard)

        let hostingController = NSHostingController(rootView: panel)
        // Let the popover shrink and grow with its content — with no pins set it
        // collapses to just the footer.
        hostingController.sizingOptions = [.preferredContentSize]

        popover.contentViewController = hostingController
        popover.behavior = .transient
        popover.animates = true
    }

    /// The single entry point used by both the status item and the panel hotkey.
    func togglePanel() {
        if popover.isShown {
            closePanel()
        } else {
            openPanel()
        }
    }

    func openPanel() {
        guard let button = statusItem?.button else { return }

        // Bring ClipMate forward first, otherwise the popover cannot take keyboard
        // focus when it is summoned from another app via the hotkey.
        NSApp.activateForPanel()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()

        installPanelMonitors()
    }

    func closePanel() {
        popover.performClose(nil)
        removePanelMonitors()
    }

    private func installPanelMonitors() {
        if globalEventMonitor == nil {
            globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] _ in
                Task { @MainActor in self?.closePanel() }
            }
        }

        if escapeMonitor == nil {
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53 else { return event } // 53 = Escape
                guard let self, self.popover.isShown else { return event }
                self.closePanel()
                return nil
            }
        }
    }

    private func removePanelMonitors() {
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
    }

    // MARK: - Hotkeys

    private func configureHotkeys() {
        migrateLegacyPanelShortcutIfNeeded()

        // Carbon-based registration: system-wide, and no Accessibility permission.
        // Re-recording either shortcut in Settings re-registers it automatically.
        KeyboardShortcuts.onKeyDown(for: .togglePanel) { [weak self] in
            self?.togglePanel()
        }

        KeyboardShortcuts.onKeyDown(for: .takeScreenshot) { [weak self] in
            self?.takeScreenshot()
        }
    }

    /// Earlier builds shipped ⌥⌘V as the panel shortcut and persisted it, which
    /// would otherwise shadow the new ⌘2 default forever on an upgraded install.
    ///
    /// Runs once, and only replaces the shortcut if it still matches that old
    /// default — anything the user deliberately recorded is left alone.
    private func migrateLegacyPanelShortcutIfNeeded() {
        let migrationKey = "clipmate.didMigratePanelShortcut"
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migrationKey) else { return }
        defaults.set(true, forKey: migrationKey)

        let legacyDefault = KeyboardShortcuts.Shortcut(.v, modifiers: [.option, .command])
        if KeyboardShortcuts.getShortcut(for: .togglePanel) == legacyDefault {
            KeyboardShortcuts.reset(.togglePanel)
        }
    }

    // MARK: - Finder cut & paste

    /// Starts or stops the Finder event tap to match the setting, now and whenever
    /// the user toggles it.
    private func configureFinderCut() {
        applyFinderCutSetting()
        settings.$finderCutEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                self?.applyFinderCutSetting(enabled)
            }
            .store(in: &cancellables)
    }

    private func applyFinderCutSetting(_ enabled: Bool? = nil) {
        if enabled ?? settings.finderCutEnabled {
            // Prompts for Accessibility the first time; a refusal just leaves the
            // tap uninstalled and Settings explains why.
            if !FinderCutService.hasAccessibilityPermission {
                FinderCutService.requestAccessibilityPermission()
            }
            finderCut.start()
        } else {
            finderCut.stop()
        }
    }

    // MARK: - Actions

    /// Reached from the app menu's Settings… item via the responder chain.
    @objc func openSettingsFromMenu(_ sender: Any?) {
        openSettings()
    }

    private func openSettings() {
        closePanel()

        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(settings: settings, clipboard: clipboard, finderCut: finderCut)
        }
        settingsWindowController?.present()
    }

    /// Shared by the footer button and the screenshot hotkey.
    ///
    /// The destination is resolved at capture time, so an answer given in the
    /// mini-prompt moments earlier is the one that applies.
    private func takeScreenshot() {
        // The panel would otherwise sit on top of the area being captured.
        closePanel()

        guard settings.shouldAskForScreenshotDestination else {
            performCapture(to: settings.screenshotDestination)
            return
        }

        screenshotChoice.present { [weak self] choice in
            guard let self else { return }
            // Dismissing the prompt without choosing cancels the capture entirely.
            guard let choice else { return }
            self.settings.rememberScreenshotChoice(choice)
            self.performCapture(to: choice)
        }
    }

    private func performCapture(to destination: ScreenshotDestination) {
        ScreenshotService.captureInteractive(to: destination) { result in
            switch result {
            case .savedToFile, .copiedToClipboard, .cancelled:
                // Success and cancellation are both self-evident — the file lands
                // on the Desktop, the image lands on the clipboard, or nothing
                // happens. No notification permission needed.
                break
            case .failed(let message):
                Self.presentScreenshotFailure(message)
            }
        }
    }

    /// Failures are rare but worth surfacing — most often the Screen Recording
    /// permission being declined the first time.
    @MainActor
    private static func presentScreenshotFailure(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't take the screenshot"
        alert.informativeText = """
            \(message)

            If this is the first capture, macOS may need Screen Recording permission \
            for ClipMate in System Settings ▸ Privacy & Security ▸ Screen Recording.
            """
        alert.addButton(withTitle: "OK")
        NSApp.activateForPanel()
        alert.runModal()
    }
}
