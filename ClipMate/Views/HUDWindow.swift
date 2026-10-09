import AppKit
import SwiftUI

/// A small, non-activating toast shown near the top of the screen — used to confirm
/// actions that happen without the panel open, such as "Copy text from screen" or
/// toggling Keep Awake from the hotkey.
///
/// Built in-app rather than as a system notification, so ClipMate still never needs
/// the Notifications permission.
@MainActor
enum HUD {

    private static var panel: NSPanel?
    private static var hideTask: Task<Void, Never>?

    /// Shows `message` for a moment, replacing any HUD already on screen.
    static func show(_ message: String, symbol: String = "checkmark.circle.fill", duration: TimeInterval = 1.4) {
        hideTask?.cancel()
        panel?.orderOut(nil)

        let host = NSHostingView(rootView: HUDContent(message: message, symbol: symbol))
        host.frame.size = host.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: host.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = host

        // Top-centre of the screen the mouse is on, just below the menu bar.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let origin = NSPoint(
                x: visible.midX - host.fittingSize.width / 2,
                y: visible.maxY - host.fittingSize.height - 16
            )
            panel.setFrameOrigin(origin)
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
        self.panel = panel

        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                panel.animator().alphaValue = 0
            }, completionHandler: {
                Task { @MainActor in panel.orderOut(nil) }
            })
        }
    }
}

private struct HUDContent: View {
    let message: String
    let symbol: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
                .frame(maxWidth: 320, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            VisualEffectBackground(material: .hudWindow)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        )
    }
}
