import SwiftUI

/// Two small switches at the top of the panel: **Keep Awake** and **Notifications**.
///
/// Meant to be glanceable — one click to keep the Mac awake for a call or a
/// download, one click to silence banners — with the details in Settings.
struct QuickTogglesSection: View {
    @EnvironmentObject private var keepAwake: KeepAwakeService
    @EnvironmentObject private var notifications: NotificationFilterService

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            keepAwakeRow
            notificationsRow
        }
    }

    // MARK: - Keep Awake

    private var keepAwakeRow: some View {
        ToggleRow(
            icon: keepAwake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer",
            isHighlighted: keepAwake.isActive,
            title: "Keep Awake",
            // Re-render once a minute so "42m left" counts down while open.
            subtitle: nil,
            liveSubtitle: { keepAwake.statusText },
            help: keepAwake.keepDisplayOn
                ? "Stop the Mac and the display from sleeping"
                : "Stop the Mac from sleeping (the display may still sleep)"
        ) {
            Menu {
                ForEach(KeepAwakeDuration.allCases) { duration in
                    Button(duration.title) { keepAwake.activate(for: duration) }
                }
                if keepAwake.isActive {
                    Divider()
                    Button("Turn off") { keepAwake.deactivate() }
                }
            } label: {
                Image(systemName: "clock")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Keep awake for a set time")

            Toggle("", isOn: Binding(
                get: { keepAwake.isActive },
                set: { $0 ? keepAwake.activate(for: keepAwake.defaultDuration) : keepAwake.deactivate() }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
        }
    }

    // MARK: - Notifications

    private var notificationsRow: some View {
        ToggleRow(
            icon: notificationIcon,
            isHighlighted: notifications.mode != .showAll,
            title: "Notifications",
            subtitle: notificationSubtitle,
            liveSubtitle: nil,
            help: "Hide pop-up banners from apps you choose — including your iPhone's"
        ) {
            Picker("", selection: $notifications.mode) {
                ForEach(NotificationMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .fixedSize()
        }
    }

    private var notificationIcon: String {
        switch notifications.mode {
        case .showAll: "bell"
        case .filter: "bell.badge"
        case .hideAll: "bell.slash.fill"
        }
    }

    private var notificationSubtitle: String? {
        guard notifications.mode != .showAll else { return nil }
        if !NotificationFilterService.hasAccessibilityPermission {
            return "Needs Accessibility — see Settings"
        }
        if notifications.mode == .filter {
            let count = notifications.hiddenApps.count
            return count == 0 ? "No apps hidden yet" : "\(count) app\(count == 1 ? "" : "s") hidden"
        }
        return "All banners hidden"
    }
}

/// A row with an icon, a title, an optional subtitle and trailing controls.
private struct ToggleRow<Trailing: View>: View {
    let icon: String
    let isHighlighted: Bool
    let title: String
    let subtitle: String?
    let liveSubtitle: (() -> String)?
    let help: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isHighlighted ? Theme.accent : Color.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12.5))
                if let liveSubtitle {
                    TimelineView(.periodic(from: .now, by: 30)) { _ in
                        subtitleText(liveSubtitle())
                    }
                } else if let subtitle {
                    subtitleText(subtitle)
                }
            }

            Spacer(minLength: 4)

            trailing()
        }
        .padding(.vertical, 5)
        .padding(.horizontal, Theme.rowHorizontalPadding)
        .help(help)
    }

    private func subtitleText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}
