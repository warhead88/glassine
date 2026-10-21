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
        // Activation is cooperative since macOS 14 and may be declined when triggered
        // by a global hotkey, so bring the window forward regardless.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func close() {
        window?.close()
    }
}
