import SwiftUI

/// The most recent clipboard items, newest first.
///
/// Populated by `ClipboardManager`, which watches the pasteboard — so this fills up
/// from ⌘C, ⌘X, right-click ▸ Copy, or any other app, without ClipMate observing
/// keystrokes. It starts empty on a fresh install and is never seeded.
///
/// `PanelView` omits this section entirely while the history is empty, so there is
/// no lonely header and no placeholder text.
struct HistorySection: View {
    @EnvironmentObject private var clipboard: ClipboardManager
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionHeader(title: "Recent", trailing: AnyView(clearButton))

            // History is de-duplicated by `ClipboardManager`, so the text itself is
            // a stable, unique identity for each row.
            ForEach(clipboard.history, id: \.self) { clip in
                RowView(
                    icon: "doc.on.clipboard",
                    text: clip,
                    monospaced: true,
                    pin: PinAffordance(
                        isPinned: settings.isPinned(clip),
                        hasFreeSlot: settings.firstEmptyPinSlot != nil,
                        toggle: {
                            if settings.isPinned(clip) {
                                settings.unpin(clip)
                            } else {
                                settings.pin(clip)
                            }
                        }
                    )
                ) {
                    clipboard.copy(clip)
                }
            }
        }
        .animation(Theme.subtle, value: clipboard.history)
    }

    private var clearButton: some View {
        Button("Clear") {
            clipboard.clearHistory()
        }
        .buttonStyle(.plain)
        .font(.system(size: 9.5, weight: .medium))
        .foregroundStyle(.tertiary)
        .help("Remove every saved clip. Pinned texts are kept.")
    }
}
