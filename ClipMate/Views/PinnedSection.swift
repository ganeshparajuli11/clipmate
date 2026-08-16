import SwiftUI

/// The pinned texts.
///
/// Only slots that actually have text are rendered, with the gaps closed up — set
/// pin 1 and pin 3 and you get two adjacent rows, never an "Empty" placeholder. If
/// no pins are set the whole section, header included, is omitted by `PanelView`.
struct PinnedSection: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var clipboard: ClipboardManager

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionHeader(title: "Pinned")

            ForEach(Array(settings.visiblePins.enumerated()), id: \.offset) { _, pinText in
                RowView(
                    icon: .symbol("pin.fill"),
                    title: pinText.singleLinePreview,
                    tooltip: pinText,
                    // The trailing button un-pins, which is the quickest way to
                    // free a slot without opening Settings.
                    pin: PinAffordance(
                        isPinned: true,
                        hasFreeSlot: true,
                        toggle: { settings.unpin(pinText) }
                    )
                ) {
                    clipboard.copy(text: pinText)
                    return true
                }
            }
        }
    }
}

/// Quiet caption-style heading used by both panel sections.
struct SectionHeader: View {
    let title: String
    /// Optional trailing control, e.g. the "Clear" button on the history section.
    var trailing: AnyView?

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(.tertiary)

            Spacer()

            if let trailing {
                trailing
            }
        }
        .padding(.horizontal, Theme.rowHorizontalPadding)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }
}
