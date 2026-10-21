import AppKit
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let capture = CaptureCoordinator()
    private let settings = HostingWindowController(title: "Glassine Settings") { SettingsView() }
    private lazy var welcome: HostingWindowController<WelcomeView> = HostingWindowController(
        title: "Welcome to Glassine"
    ) { [unowned self] in
        WelcomeView(
            openSettings: { [unowned self] in welcome.close(); settings.show() },
            close: { [unowned self] in welcome.close() }
        )
    }
    private lazy var statusItem = StatusItemController { [unowned self] in makeCaptureMenu() }
    private var defaultsObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()
        try? FileManager.default.removeItem(at: AppPaths.temporaryFiles)
        Log.app.notice("Launched; screen capture access: \(ScreenAccess.isGranted, privacy: .public)")

        NSApp.mainMenu = MainMenu.make(target: self)
        capture.onMissingPermission = { [weak self] in self?.welcome.show() }

        #if DEBUG
        if CommandLine.arguments.contains("--debug-preview") {
            capture.showDebugPreviews()
        }
        #endif

        KeyboardShortcuts.onKeyUp(for: .captureArea) { [weak self] in self?.capture.captureArea() }
        KeyboardShortcuts.onKeyUp(for: .captureScreen) { [weak self] in self?.capture.captureScreen() }
        KeyboardShortcuts.onKeyUp(for: .repeatLastArea) { [weak self] in self?.capture.repeatLastArea() }
        KeyboardShortcuts.onKeyUp(for: .timedCapture) { [weak self] in self?.capture.timedCapture() }
        KeyboardShortcuts.onKeyUp(for: .openSettings) { [weak self] in self?.settings.show() }

        syncStatusItem()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncStatusItem() }
        }

        // With no Dock icon and the menu bar icon off by default, introduce the app
        // on first launch so the user knows it is running and how to use it.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: PrefKey.hasLaunchedBefore) || !ScreenAccess.isGranted {
            defaults.set(true, forKey: PrefKey.hasLaunchedBefore)
            welcome.show()
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

    @objc private func captureArea() { capture.captureArea() }
    @objc private func captureScreen() { capture.captureScreen() }
    @objc private func repeatLastArea() { capture.repeatLastArea() }
    @objc private func timedCapture() { capture.timedCapture() }

    private func makeCaptureMenu() -> NSMenu {
        let menu = NSMenu()
        let items: [(String, Selector, KeyboardShortcuts.Name?)] = [
            ("Capture Area or Window", #selector(captureArea), .captureArea),
            ("Capture Screen", #selector(captureScreen), .captureScreen),
            ("Repeat Last Area", #selector(repeatLastArea), .repeatLastArea),
            ("Capture with Timer", #selector(timedCapture), .timedCapture),
        ]
        for (title, action, shortcut) in items {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
            if let shortcut { item.setShortcut(for: shortcut) }
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Quit Glassine", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private func syncStatusItem() {
        statusItem.isVisible = UserDefaults.standard.bool(forKey: PrefKey.showMenuBarIcon)
    }
}
