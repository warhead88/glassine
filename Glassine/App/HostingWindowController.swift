import AppKit
import SwiftUI

/// Owns one reusable SwiftUI window (Settings, Welcome). Managed manually because an
/// agent app has no SwiftUI scene or app menu to open windows from.
@MainActor
final class HostingWindowController<Content: View> {
    private let title: String
    private let makeContent: () -> Content
    private var window: NSWindow?

    init(title: String, content: @escaping () -> Content) {
        self.title = title
        self.makeContent = content
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: makeContent()))
            window.title = title
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        // Cooperative `NSApp.activate()` (macOS 14+) is declined when an agent app opens a
        // window right after launch, leaving it inactive behind the frontmost app. These windows
        // only open on an explicit request (hotkey, relaunch, first launch), so take focus.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()

        let title = title
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            let key = self?.window?.isKeyWindow ?? false
            let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-"
            Log.app.notice(
                "\(title, privacy: .public) shown: active \(NSApp.isActive, privacy: .public), key \(key, privacy: .public), frontmost \(frontmost, privacy: .public)"
            )
        }
    }

    func close() {
        window?.close()
    }
}
