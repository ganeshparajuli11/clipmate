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
            } header: {
                Text("Clipboard history")
            } footer: {
                Text("History fills automatically as you copy (⌘C) or cut (⌘X) in any app — nothing is pre-filled. Text only; images and files are ignored.")
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
        }
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
