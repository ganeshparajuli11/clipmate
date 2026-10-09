import SwiftUI

/// Banners ClipMate hid, newest first — so muting an app never means missing what
/// it said. Click a row to copy its text; right-click to show that app again.
///
/// Kept in memory only. `PanelView` omits the section entirely when it's empty.
struct HiddenNotificationsSection: View {
    @EnvironmentObject private var notifications: NotificationFilterService
    @EnvironmentObject private var clipboard: ClipboardManager

    /// The panel doesn't scroll, so only the newest few are listed.
    private let visibleLimit = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionHeader(title: "Hidden notifications", trailing: AnyView(clearButton))

            ForEach(notifications.inbox.prefix(visibleLimit)) { item in
                RowView(
                    icon: .symbol("bell.slash"),
                    title: "\(item.app): \(item.preview)",
                    tooltip: tooltip(for: item)
                ) {
                    clipboard.copy(text: item.copyText)
                    return true
                }
                .contextMenu {
                    Button("Show banners from \(item.app) again") {
                        notifications.setApp(item.app, hidden: false)
                    }
                    Button("Remove") {
                        notifications.remove(item)
                    }
                }
            }

            if notifications.inbox.count > visibleLimit {
                Text("+\(notifications.inbox.count - visibleLimit) more")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, Theme.rowHorizontalPadding)
            }
        }
        .animation(Theme.subtle, value: notifications.inbox)
    }

    private func tooltip(for item: CapturedNotification) -> String {
        let time = item.date.formatted(date: .omitted, time: .shortened)
        return "\(item.app) · \(time)\n\(item.copyText)"
    }

    private var clearButton: some View {
        Button("Clear") {
            notifications.clearInbox()
        }
        .buttonStyle(.plain)
        .font(.system(size: 9.5, weight: .medium))
        .foregroundStyle(.tertiary)
        .help("Forget all hidden notifications")
    }
}
