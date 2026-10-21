import AppKit

// Plain AppKit entry point: Glassine is an agent app (LSUIElement) that manages its own windows.
MainActor.assumeIsolated {
    // When hosting unit tests, run bare: no hotkeys, windows or cleanup of the real app's files.
    let isHostingTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    let delegate = isHostingTests ? nil : AppDelegate()
    NSApplication.shared.delegate = delegate
    NSApplication.shared.run()
}
