import AppKit
import SwiftUI

/// "Privacy & Permissions" — shown once on first launch and any time from
/// Settings. Says in plain words what ClipMate stores, what it can read, and lets
/// the user grant each permission with its reason right next to it.
struct PrivacyView: View {
    let onDone: () -> Void

    /// Permission state lives in System Settings, outside the app, so it is
    /// re-checked every second while this window is open.
    @State private var granted: [Permission: Bool] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to ClipMate")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Here's exactly what ClipMate keeps and what it can see.")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("What ClipMate keeps").font(.headline)
                bullet("doc.on.clipboard", "Your recent clips and pins — text, copied file paths, and copied images — saved only on this Mac.")
                bullet("bell.slash", "Hidden notifications are kept in memory only and forgotten when ClipMate quits.")
                bullet("wifi.slash", "Nothing is ever sent anywhere. ClipMate has no network code, no accounts, no analytics.")
                bullet("trash", "Clear your history any time from the panel or Settings.")
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Permissions").font(.headline)
                Text("None are needed to start. ClipMate asks only when you first use a feature that needs one, and explains why first.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(Permission.allCases) { permission in
                    permissionRow(permission)
                }
            }

            HStack {
                Text("You can reopen this from Settings ▸ Privacy & Permissions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear(perform: refresh)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            refresh()
        }
    }

    private func refresh() {
        for permission in Permission.allCases {
            granted[permission] = permission.isGranted
        }
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Theme.accent)
                .frame(width: 18)
        }
        .font(.callout)
    }

    private func permissionRow(_ permission: Permission) -> some View {
        let isGranted = granted[permission] ?? false

        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: permission.symbol)
                .font(.system(size: 16))
                .foregroundStyle(Theme.accent)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(permission.title).font(.system(size: 13, weight: .semibold))
                    Text("· optional").font(.caption).foregroundStyle(.secondary)
                }
                Text("Used for: \(permission.usedFor)")
                    .font(.callout)
                Text(permission.whatWeAccess)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if isGranted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .fixedSize()
            } else {
                Button("Allow…") { permission.request() }
                    .fixedSize()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}

/// Owns the Privacy & Permissions window.
@MainActor
final class PrivacyWindowController: NSWindowController {

    /// One window for the whole app — opened at first launch and from Settings.
    static let shared = PrivacyWindowController()

    private static let shownKey = "clipmate.privacyWelcomeShown"

    /// True until the window has been shown once.
    static var shouldShowOnLaunch: Bool {
        !UserDefaults.standard.bool(forKey: shownKey)
    }

    convenience init() {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "ClipMate — Privacy & Permissions"
        window.isReleasedWhenClosed = false
        self.init(window: window)

        let root = PrivacyView { [weak self] in self?.close() }
        window.contentViewController = NSHostingController(rootView: root)
        window.center()
    }

    func present() {
        UserDefaults.standard.set(true, forKey: Self.shownKey)
        NSApp.activateForPanel()
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}
