import AppKit

// Plain AppKit entry point: Glassine is an agent app (LSUIElement) that manages its own windows.
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    NSApplication.shared.delegate = delegate
    NSApplication.shared.run()
}
