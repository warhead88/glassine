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
            let window = NSWindow(contentViewController: NSHostingController(rootView: makeContent().themed()))
            window.title = title
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        AppActivation.bringToFront()
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

enum AppActivation {
    /// Makes Glassine the active app for a window the user explicitly asked for.
    ///
    /// Plain `NSApp.activate()` (macOS 14+) is declined when an agent app opens a window
    /// right after launch, leaving it inactive behind the frontmost app. Asking the frontmost
    /// app to hand over activation succeeds.
    @MainActor
    static func bringToFront() {
        if let frontmost = NSWorkspace.shared.frontmostApplication, frontmost != .current {
            NSRunningApplication.current.activate(from: frontmost, options: [])
        } else {
            NSApp.activate()
        }
    }
}
