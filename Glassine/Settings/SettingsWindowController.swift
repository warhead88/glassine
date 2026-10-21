import AppKit
import SwiftUI

/// Owns the single settings window. Managed manually because an agent app has no
/// SwiftUI scene or app menu to open a `Settings` scene from.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "Glassine Settings"
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
}
