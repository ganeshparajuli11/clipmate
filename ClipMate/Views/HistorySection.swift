import SwiftUI

/// The most recent clipboard items, newest first.
///
/// Populated by `ClipboardManager`, which watches the pasteboard — so this fills up
/// from ⌘C, ⌘X, right-click ▸ Copy, or a Finder file copy, without ClipMate
/// observing keystrokes. It starts empty on a fresh install and is never seeded.
///
/// `PanelView` omits this section entirely while the history is empty, so there is
/// no lonely header and no placeholder text.
struct HistorySection: View {
    @EnvironmentObject private var clipboard: ClipboardManager
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionHeader(title: "Recent", trailing: AnyView(clearButton))

            // Clips are de-duplicated by `ClipboardManager`, and `Clip.id` is a
            // stable key for both text and file entries.
            ForEach(clipboard.history) { clip in
                RowView(
                    icon: clip.icon,
                    title: clip.preview,
                    tooltip: clip.tooltip,
                    monospaced: clip.kind == .text,
                    truncation: clip.kind == .files ? .middle : .tail,
                    isUnavailable: clip.isDangling,
                    pin: pinAffordance(for: clip)
                ) {
                    clipboard.copy(clip)
                }
                .contextMenu {
                    if clip.kind == .files, !clip.existingURLs.isEmpty {
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting(clip.existingURLs)
                        }
                    }
                    Button("Remove from history") {
                        clipboard.remove(clip)
                    }
                }
            }
        }
        .animation(Theme.subtle, value: clipboard.history)
    }

    /// Only text clips are pinnable — a pin is a plain string, so a pinned file
    /// would paste as a path rather than as a file.
    private func pinAffordance(for clip: Clip) -> PinAffordance? {
        guard clip.isPinnable else { return nil }
        return PinAffordance(
            isPinned: settings.isPinned(clip.text),
            hasFreeSlot: settings.firstEmptyPinSlot != nil,
            toggle: {
                if settings.isPinned(clip.text) {
                    settings.unpin(clip.text)
                } else {
                    settings.pin(clip.text)
                }
            }
        )
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
