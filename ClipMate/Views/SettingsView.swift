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

    /// Re-checked whenever Settings appears and while it is open, so the status
    /// line updates as soon as the user grants Accessibility in System Settings.
    @State private var hasAccessibility = FinderCutService.hasAccessibilityPermission

    /// Disk taken by stored image clips, refreshed when Settings appears.
    @State private var imageDiskUsage: Int64 = 0

    var body: some View {
        Form {
            Section {
                // Four plain fields. The user fills any of them in any order —
                // there is no slot picker anywhere in the app.
                ForEach(0..<AppSettings.pinCount, id: \.self) { index in
                    TextField(
                        "Pin \(index + 1)",
                        text: Binding(
                            get: { settings.pins[safe: index] ?? "" },
                            set: { newValue in
                                guard settings.pins.indices.contains(index) else { return }
                                settings.pins[index] = newValue
                            }
                        ),
                        prompt: Text("Leave empty to hide this slot")
                    )
                    .textFieldStyle(.roundedBorder)
                }
            } header: {
                Text("Pinned texts")
            } footer: {
                Text("Click a pin in the panel to copy it. Empty slots are hidden. You can also pin any recent clip straight from the panel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
            } header: {
                Text("Keyboard shortcuts")
            } footer: {
                Text("Both work system-wide and take effect immediately. ClipMate uses Carbon hotkeys, so neither needs Accessibility permission.")
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

            Section {
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
                Text("Startup")
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
        .frame(width: 430)
        .fixedSize(horizontal: false, vertical: true)
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
