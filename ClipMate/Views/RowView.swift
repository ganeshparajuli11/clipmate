import SwiftUI

/// Describes the pin button shown at the trailing edge of a clip row.
///
/// Deliberately not a slot picker: pinning fills the first free slot, so it is a
/// single click. When the clip is already pinned the same button un-pins it.
struct PinAffordance {
    /// The clip is currently in one of the pin slots.
    let isPinned: Bool
    /// There is at least one free slot (only consulted when `isPinned` is false).
    let hasFreeSlot: Bool
    /// Pin or un-pin, depending on `isPinned`.
    let toggle: () -> Void
}

/// One tappable line in the panel — used for pinned texts and for recent clips,
/// whether those clips are text or files.
struct RowView: View {
    /// SF Symbol, or a concrete image such as a Finder file icon.
    let icon: RowIcon
    /// One-line label.
    let title: String
    /// Full text shown on hover, since the label is truncated.
    var tooltip: String = ""
    /// Text clips render monospaced; file names and pins use the UI font.
    var monospaced: Bool = false
    /// Filenames truncate in the middle so the extension stays visible; prose and
    /// code read better truncated at the end.
    var truncation: Text.TruncationMode = .tail
    /// Greyed out and non-copying — used for file clips whose files are gone.
    var isUnavailable: Bool = false
    /// When non-nil, a pin button is shown at the trailing edge.
    var pin: PinAffordance?
    /// Return `false` to signal the copy did not happen.
    let action: () -> Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    /// Inline confirmation ("Copied ✓", "Pinned ✓", …), or nil when idle.
    @State private var confirmation: String?

    /// Tracks the pending reset so rapid clicks don't leave a stale badge behind.
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 4) {
            // The copy target fills the row, so clicking anywhere except the pin
            // button copies.
            Button(action: handleTap) {
                HStack(spacing: 8) {
                    iconView

                    Text(title)
                        .font(monospaced
                              ? .system(size: 11.5, design: .monospaced)
                              : .system(size: 12.5))
                        .foregroundStyle(isUnavailable ? Color.secondary : Color.primary)
                        .strikethrough(isUnavailable, color: .secondary)
                        .lineLimit(1)
                        .truncationMode(truncation)

                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(tooltip.isEmpty ? title : tooltip)

            trailingAccessory
        }
        .padding(.vertical, Theme.rowVerticalPadding)
        .padding(.horizontal, Theme.rowHorizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous)
                .fill(isHovering ? Theme.rowHover(colorScheme) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(Theme.subtle) { isHovering = hovering }
        }
        .onDisappear { resetTask?.cancel() }
    }

    // MARK: - Icon

    @ViewBuilder
    private var iconView: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isHovering ? Theme.accent : Color.secondary)
                .frame(width: 16)
        case .image(let nsImage):
            // Real Finder icon, so a folder looks like a folder.
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
                .opacity(isUnavailable ? 0.4 : 1)
        }
    }

    // MARK: - Trailing accessory

    @ViewBuilder
    private var trailingAccessory: some View {
        if let confirmation {
            Text(confirmation)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.confirmation)
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
                .fixedSize()
        } else if let pin {
            pinButton(pin)
        }
    }

    private func pinButton(_ pin: PinAffordance) -> some View {
        let enabled = pin.isPinned || pin.hasFreeSlot

        return Button {
            guard enabled else {
                // Nothing is overwritten silently — say why instead.
                showConfirmation("Pins full")
                return
            }
            pin.toggle()
            showConfirmation(pin.isPinned ? "Unpinned" : "Pinned ✓")
        } label: {
            Image(systemName: pin.isPinned ? "pin.fill" : "pin")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(pinTint(pin, enabled: enabled))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(pinHelp(pin, enabled: enabled))
    }

    private func pinTint(_ pin: PinAffordance, enabled: Bool) -> Color {
        if pin.isPinned { return Theme.accent }
        if !enabled { return Color.secondary.opacity(0.25) }
        // Faintly visible when not hovered so the affordance stays discoverable.
        return isHovering ? Theme.accent : Color.secondary.opacity(0.40)
    }

    private func pinHelp(_ pin: PinAffordance, enabled: Bool) -> String {
        if pin.isPinned { return "Un-pin this clip" }
        if !enabled { return "All \(AppSettings.pinCount) pin slots are full — clear one in Settings" }
        return "Pin this clip"
    }

    // MARK: - Actions

    private func handleTap() {
        showConfirmation(action() ? "Copied ✓" : "File missing")
    }

    private func showConfirmation(_ message: String) {
        withAnimation(Theme.subtle) { confirmation = message }

        resetTask?.cancel()
        resetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Theme.copyConfirmationDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(Theme.subtle) { confirmation = nil }
        }
    }
}
