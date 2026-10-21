import AppKit
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let capture = CaptureCoordinator()
    private let settings = SettingsWindowController()
    private lazy var statusItem = StatusItemController(
        onCapture: { [weak self] in self?.startAreaCapture() },
        onSettings: { [weak self] in self?.settings.show() }
    )
    private var defaultsObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()
        try? FileManager.default.removeItem(at: AppPaths.temporaryFiles)
        Log.app.notice("Launched; screen capture access: \(CGPreflightScreenCaptureAccess(), privacy: .public)")

        NSApp.mainMenu = MainMenu.make(target: self)

        #if DEBUG
        if CommandLine.arguments.contains("--debug-preview") {
            capture.showDebugPreviews()
        }
        #endif

        KeyboardShortcuts.onKeyUp(for: .captureArea) { [weak self] in
            self?.startAreaCapture()
        }
        KeyboardShortcuts.onKeyUp(for: .openSettings) { [weak self] in
            self?.settings.show()
        }

        syncStatusItem()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncStatusItem() }
        }

        // With no Dock icon and the menu bar icon off by default, show settings
        // on first launch so the user knows the app is running and how to use it.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: PrefKey.hasLaunchedBefore) {
            defaults.set(true, forKey: PrefKey.hasLaunchedBefore)
            settings.show()
        }
    }

    /// Launching Glassine again (Finder, Spotlight, Launchpad) opens settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.show()
        return true
    }

    @objc func showSettings(_ sender: Any?) {
        settings.show()
    }

    private func startAreaCapture() {
        capture.captureArea()
    }

    private func syncStatusItem() {
        statusItem.isVisible = UserDefaults.standard.bool(forKey: PrefKey.showMenuBarIcon)
    }
}
