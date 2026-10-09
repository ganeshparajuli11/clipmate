import KeyboardShortcuts
import ServiceManagement
import SwiftUI

/// Everything configurable in ClipMate, in one short form.
///
/// Pins are edited **only** here. Every control writes straight through to
/// `AppSettings`, which persists to `UserDefaults` on change — there is no Save
/// button because there is nothing to save.
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var clipboard: ClipboardManager
    @EnvironmentObject private var finderCut: FinderCutService
    @EnvironmentObject private var keepAwake: KeepAwakeService
    @EnvironmentObject private var notifications: NotificationFilterService

    /// Text field for adding an app to the notification list by name.
    @State private var newAppName = ""

    /// Re-checked whenever Settings appears and while it is open, so the status
    /// line updates as soon as the user grants Accessibility in System Settings.
    @State private var hasAccessibility = FinderCutService.hasAccessibilityPermission

    /// Disk taken by stored image clips, refreshed when Settings appears.
    @State private var imageDiskUsage: Int64 = 0

    var body: some View {
        Form {
            Section {
                Stepper(
                    "Keep \(settings.historySize) recent clips",
                    value: $settings.historySize,
                    in: AppSettings.historySizeRange
                )

                Button("Clear clipboard history") {
                    clipboard.clearHistory()
                }
                .disabled(clipboard.history.isEmpty)

                // Images are the only thing ClipMate writes outside UserDefaults,
                // so it is worth showing what that costs.
                if imageDiskUsage > 0 {
                    Text("Stored images: \(ByteCountFormatter.string(fromByteCount: imageDiskUsage, countStyle: .file))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Clipboard history")
            } footer: {
                Text("History fills automatically as you copy or cut in any app — nothing is pre-filled. Text, copied files, and images are all captured. Drag any row out to drop it into another app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                KeyboardShortcuts.Recorder("Show / hide panel:", name: .togglePanel)
                KeyboardShortcuts.Recorder("Take screenshot:", name: .takeScreenshot)
                KeyboardShortcuts.Recorder("Copy text from screen:", name: .captureText)
                KeyboardShortcuts.Recorder("Toggle Keep Awake:", name: .toggleKeepAwake)
                KeyboardShortcuts.Recorder("Hide all notifications:", name: .toggleHideAllNotifications)
            } header: {
                Text("Keyboard shortcuts")
            } footer: {
                Text("All work system-wide and take effect immediately. ClipMate uses Carbon hotkeys, so none of them needs Accessibility permission. The last two have no default — record one if you want it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(
                    "Ask me the first time, then remember my choice",
                    isOn: $settings.askScreenshotDestinationFirstTime
                )

                Picker("Screenshots:", selection: $settings.screenshotDestination) {
                    ForEach(ScreenshotDestination.allCases) { destination in
                        Text(destination.title).tag(destination)
                    }
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text("Screenshots")
            } footer: {
                Text(screenshotFooterText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Toggle(
                    "Use ⌘X to cut and ⌘V to move files in Finder",
                    isOn: $settings.finderCutEnabled
                )

                if settings.finderCutEnabled {
                    if hasAccessibility {
                        Label(
                            finderCut.isRunning
                                ? "Active — ⌘X cuts, ⌘V moves."
                                : "Starting…",
                            systemImage: finderCut.isRunning
                                ? "checkmark.circle.fill"
                                : "clock"
                        )
                        .font(.caption)
                        .foregroundStyle(finderCut.isRunning ? .green : .secondary)
                    } else {
                        Label(
                            "Needs Accessibility permission to intercept ⌘X.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)

                        Button("Open Accessibility Settings…") {
                            FinderCutService.requestAccessibilityPermission()
                            FinderCutService.openAccessibilitySettings()
                        }
                    }

                    if let error = finderCut.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } header: {
                Text("Finder cut & paste")
            } footer: {
                Text(finderFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            textRecognitionSection
            keepAwakeSection
            notificationsSection

            Section {
                Toggle("Show Keep Awake & Notifications switches in the panel", isOn: $settings.showQuickToggles)
                Toggle("Launch ClipMate at login", isOn: $settings.launchAtLogin)

                if let error = settings.launchAtLoginError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("This usually means ClipMate is running from Xcode's build folder. Move ClipMate.app to /Applications and try again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Panel & startup")
            }

            Section {
                HStack {
                    Spacer()
                    Button("Quit ClipMate") {
                        NSApp.terminate(nil)
                    }
                }
            }
        }
        .formStyle(.grouped)
        // With Keep Awake and Notifications the form is taller than a laptop
        // screen, so it gets a fixed height and scrolls instead of growing.
        .frame(width: 460, height: 680)
        .onAppear {
            // The user may have removed ClipMate from System Settings ▸ Login Items
            // behind our back, so re-read the real state each time this appears.
            settings.refreshLaunchAtLoginStatus()
            hasAccessibility = FinderCutService.hasAccessibilityPermission
            imageDiskUsage = ClipImageStore.diskUsage()
        }
        // Granting Accessibility happens in System Settings, outside this window,
        // so poll while Settings is open rather than leaving a stale status.
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            hasAccessibility = FinderCutService.hasAccessibilityPermission
        }
    }

    // MARK: - Text from images

    private var textRecognitionSection: some View {
        Section {
            Label("Hover an image in the panel and click its text-scan button, or right-click ▸ Copy Text from Image.", systemImage: "text.viewfinder")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Label("Press the “Copy text from screen” shortcut (⌃⇧⌘T by default) and drag over anything — a video, a PDF, an error dialog.", systemImage: "rectangle.dashed")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("Copy text from images")
        } footer: {
            Text("Uses Apple's on-device Vision text recognition — free, offline, and the same engine as Live Text. Languages are detected automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Keep Awake

    private var keepAwakeSection: some View {
        Section {
            Toggle(
                keepAwake.isActive ? "Keep Awake is on — \(keepAwake.statusText.replacingOccurrences(of: "On · ", with: ""))" : "Keep Awake",
                isOn: Binding(
                    get: { keepAwake.isActive },
                    set: { $0 ? keepAwake.activate(for: keepAwake.defaultDuration) : keepAwake.deactivate() }
                )
            )

            Picker("Default duration:", selection: $keepAwake.defaultDuration) {
                ForEach(KeepAwakeDuration.allCases) { duration in
                    Text(duration.title).tag(duration)
                }
            }

            Toggle("Keep the display on too", isOn: $keepAwake.keepDisplayOn)
            Toggle("Turn on when ClipMate launches", isOn: $keepAwake.activateAtLaunch)

            if KeepAwakeService.batteryState() != nil {
                Toggle("Turn off on battery below \(keepAwake.batteryCutoffPercent)%", isOn: $keepAwake.batteryCutoffEnabled)
                if keepAwake.batteryCutoffEnabled {
                    Stepper(
                        "Battery limit: \(keepAwake.batteryCutoffPercent)%",
                        value: $keepAwake.batteryCutoffPercent,
                        in: 5...80,
                        step: 5
                    )
                }
            }
        } header: {
            Text("Keep Awake")
        } footer: {
            Text("Stops your Mac from going to sleep, like the caffeinate command. ⌥-click or right-click the menu bar icon to toggle it; the icon turns into a coffee cup while it's on. Released automatically when ClipMate quits.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        Section {
            Picker("Notification banners:", selection: $notifications.mode) {
                Text("Show all (normal)").tag(NotificationMode.showAll)
                Text("Hide the apps I choose").tag(NotificationMode.filter)
                Text("Hide all").tag(NotificationMode.hideAll)
            }
            .pickerStyle(.radioGroup)

            if notifications.mode != .showAll {
                if hasAccessibility {
                    Label(
                        notifications.isRunning
                            ? "Active — \(notifications.hiddenCount) banner\(notifications.hiddenCount == 1 ? "" : "s") hidden since launch."
                            : "Starting…",
                        systemImage: notifications.isRunning ? "checkmark.circle.fill" : "clock"
                    )
                    .font(.caption)
                    .foregroundStyle(notifications.isRunning ? .green : .secondary)
                } else {
                    Label("Needs Accessibility permission to close banners.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button("Open Accessibility Settings…") {
                        FinderCutService.requestAccessibilityPermission()
                        FinderCutService.openAccessibilitySettings()
                    }
                }
            }

            if notifications.mode == .filter {
                if notifications.knownApps.isEmpty {
                    Text("Apps appear here as their notifications arrive. You can also add one by name below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(notifications.knownApps, id: \.self) { app in
                    Toggle(isOn: Binding(
                        get: { !notifications.isHidden(app) },
                        set: { notifications.setApp(app, hidden: !$0) }
                    )) {
                        Text(app)
                    }
                    .contextMenu {
                        Button("Remove from list") { notifications.forgetApp(app) }
                    }
                }

                HStack {
                    TextField("App name, e.g. Instagram", text: $newAppName)
                        .onSubmit(addApp)
                    Button("Hide", action: addApp)
                        .disabled(newAppName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Toggle("Keep hidden notifications in the panel", isOn: $notifications.keepHiddenInPanel)

            Button("Open macOS Notification Settings…") {
                NotificationFilterService.openSystemNotificationSettings()
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("Works for every app, including notifications your iPhone forwards to the Mac (Instagram, Messenger, WhatsApp…). Switched-off apps' banners are closed the moment they appear and kept in the panel so you can read them later — nothing is saved to disk. The Notification Center sidebar is never touched. To stop an iPhone app reaching the Mac at all, use macOS Notification Settings ▸ Allow notifications from iPhone.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func addApp() {
        notifications.addApp(newAppName, hidden: true)
        newAppName = ""
    }

    private var finderFooter: String {
        if !settings.finderCutEnabled {
            return "Off by default. macOS has no ⌘X for files — the Mac way is ⌘C then ⌥⌘V. Turn this on to use ⌘X and ⌘V instead, like Windows."
        }
        return "Only applies while Finder is frontmost, and never when you're renaming a file. ⌥⌘V keeps working as normal. Press Escape to abandon a cut. This is the one feature that needs Accessibility permission — there is no way to intercept ⌘X without it."
    }

    private var screenshotFooterText: String {
        if settings.askScreenshotDestinationFirstTime {
            return settings.hasRememberedScreenshotChoice
                ? "Your choice is remembered. Pick a different option above to change it, or switch the toggle off and on to be asked again."
                : "The next screenshot will ask once, then reuse your answer."
        }
        return "Copying puts the image straight on the clipboard — no file is written to disk."
    }
}

extension Array {
    /// Bounds-checked subscript, so a malformed defaults array can never crash the
    /// Settings form.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
