import SwiftUI

/// The small set of design tokens ClipMate draws with.
enum Theme {

    // MARK: - Colour

    /// Warm pink accent, `#FF7A93`. Defined in `Assets.xcassets/AccentColor` so it
    /// can be retuned visually in Xcode without touching code.
    static let accent = Color("AccentColor")

    /// Soft blush, `#F8E1DF`. Used for hover fills in light appearance, where the
    /// full accent would be too loud.
    static let softTint = Color(red: 0xF8 / 255, green: 0xE1 / 255, blue: 0xDF / 255)

    /// Row hover fill.
    static func rowHover(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? accent.opacity(0.20) : softTint.opacity(0.90)
    }

    /// Colour of the "Copied ✓" confirmation.
    static let confirmation = accent

    // MARK: - Metrics

    /// Popover width. Compact by design — this is a glanceable panel, not a window.
    static let panelWidth: CGFloat = 300

    static let rowCornerRadius: CGFloat = 8
    /// Generous enough to be a comfortable click target.
    static let rowVerticalPadding: CGFloat = 8
    static let rowHorizontalPadding: CGFloat = 9
    static let panelPadding: CGFloat = 10

    /// How long the in-row "Copied ✓" badge stays visible.
    ///
    /// Confirmation is shown inside the panel rather than as a system notification,
    /// which avoids the Notifications permission entirely.
    static let copyConfirmationDuration: TimeInterval = 1.0

    // MARK: - Motion

    /// Deliberately gentle. Nothing here should draw attention to itself.
    static let subtle = Animation.easeOut(duration: 0.18)
}

/// Hosts an `NSVisualEffectView` so surfaces sit on real system material rather
/// than a flat fill.
///
/// Honours **Reduce Transparency**: when the user has asked for it, the material is
/// swapped for an opaque background instead of a blurred one.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: NSVisualEffectView) {
        let reduceTransparency = NSWorkspace.shared
            .accessibilityDisplayShouldReduceTransparency

        view.material = reduceTransparency ? .windowBackground : material
        // `withinWindow` against an opaque material gives a solid, fully legible
        // surface rather than a translucent one.
        view.blendingMode = reduceTransparency ? .withinWindow : blendingMode
    }
}

extension String {
    /// Collapses all runs of whitespace and newlines into single spaces, so a
    /// multi-line pin still reads sensibly on one line.
    var singleLinePreview: String {
        split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
