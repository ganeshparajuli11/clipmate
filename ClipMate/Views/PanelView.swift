import SwiftUI

/// The whole popover: pinned texts, recent clips, and a slim action footer.
///
/// Each section only appears when it has something to show, so a fresh install is
/// just the footer, and it grows as the user pins things and copies things. No
/// placeholder rows, no empty-state copy.
///
/// Intentionally not scrollable — the content is bounded (at most four pins plus
/// `AppSettings.historySizeRange.upperBound` clips), so letting the popover size
/// itself keeps it compact without a scroll view fighting the auto-sizing.
struct PanelView: View {
    let onScreenshot: () -> Void
    let onOpenSettings: () -> Void

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var clipboard: ClipboardManager

    private var hasPins: Bool { !settings.visiblePins.isEmpty }
    private var hasHistory: Bool { !clipboard.history.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasPins {
                PinnedSection()
            }

            if hasPins && hasHistory {
                Divider()
                    .opacity(0.35)
                    .padding(.vertical, 4)
            }

            if hasHistory {
                HistorySection()
            }

            if hasPins || hasHistory {
                Divider()
                    .opacity(0.35)
                    .padding(.top, 6)
            }

            footer
        }
        .padding(Theme.panelPadding)
        .frame(width: Theme.panelWidth)
        .background(VisualEffectBackground())
    }

    private var footer: some View {
        HStack(spacing: 6) {
            FooterButton(
                icon: "camera.viewfinder",
                help: "Capture a screen area",
                action: onScreenshot
            )

            Spacer()

            FooterButton(
                icon: "gearshape",
                help: "Settings — edit pins, shortcuts, and quit",
                action: onOpenSettings
            )
        }
        .padding(.top, (hasPins || hasHistory) ? 8 : 0)
        .padding(.horizontal, 4)
    }
}

/// Small icon button used in the panel footer.
private struct FooterButton: View {
    let icon: String
    let help: String
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isHovering ? Theme.accent : Color.secondary)
                .frame(width: 28, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovering ? Theme.rowHover(colorScheme) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering in
            withAnimation(Theme.subtle) { isHovering = hovering }
        }
    }
}
