import AppKit
import SwiftUI

/// Borderless panel that can still take keyboard focus.
///
/// A borderless `NSPanel` refuses to become key by default, which would leave the
/// Return/Escape handling dead.
final class ScreenshotChoicePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Shows the one-time "Copy or Save?" prompt and reports the answer.
///
/// Only used when *Ask me the first time* is on and no choice has been remembered
/// yet; every capture after that goes straight to the stored destination.
@MainActor
final class ScreenshotChoiceController {

    private var panel: ScreenshotChoicePanel?
    private var escapeMonitor: Any?

    /// Presents the prompt. `completion` receives the chosen destination, or `nil`
    /// if the user dismissed without deciding (in which case no capture should run).
    func present(completion: @escaping (ScreenshotDestination?) -> Void) {
        // Never stack two prompts.
        dismiss()

        var finished = false
        let finish: (ScreenshotDestination?) -> Void = { [weak self] choice in
            guard !finished else { return }
            finished = true
            self?.dismiss()
            completion(choice)
        }

        let root = ScreenshotChoiceView(
            onChoose: { finish($0) },
            onCancel: { finish(nil) }
        )

        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: 300, height: 132)

        let panel = ScreenshotChoicePanel(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.center()

        self.panel = panel

        NSApp.activateForPanel()
        panel.makeKeyAndOrderFront(nil)

        // Escape dismisses without capturing.
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else { return event } // 53 = Escape
            finish(nil)
            return nil
        }
    }

    private func dismiss() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
        panel?.orderOut(nil)
        panel = nil
    }
}

/// Contents of the mini-prompt. Uses the same vibrancy treatment as the panel so
/// the two read as one app.
struct ScreenshotChoiceView: View {
    let onChoose: (ScreenshotDestination) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.accent)

                Text("Where should screenshots go?")
                    .font(.system(size: 12.5, weight: .semibold))

                Text("ClipMate will remember your choice.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                ChoiceButton(title: "Copy", symbol: "doc.on.clipboard") {
                    onChoose(.clipboard)
                }
                ChoiceButton(title: "Save", symbol: "arrow.down.doc") {
                    onChoose(.desktop)
                }
            }
        }
        .padding(16)
        .frame(width: 300, height: 132)
        .background(VisualEffectBackground(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        // Escape is also handled by a window-level monitor; this covers the case
        // where SwiftUI has first responder.
        .onExitCommand(perform: onCancel)
    }
}

private struct ChoiceButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isHovering ? Theme.rowHover(colorScheme) : Color.primary.opacity(0.06))
            )
            .foregroundStyle(isHovering ? Theme.accent : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Theme.subtle) { isHovering = hovering }
        }
    }
}
