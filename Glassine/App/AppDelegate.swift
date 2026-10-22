import AppKit
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let capture = CaptureCoordinator()
    private let pins = PinController()
    private let editor = EditorController()
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
        capture.onPin = { [weak self] in self?.pins.pin($0) }
        capture.onEdit = { [weak self] in self?.editor.open($0) }
        pins.onEdit = { [weak self] in self?.editor.open($0) }
        editor.onPin = { [weak self] in self?.pins.pin($0) }

        #if DEBUG
        if CommandLine.arguments.contains("--debug-preview") {
            capture.showDebugPreviews()
        }
        if CommandLine.arguments.contains("--debug-pins") {
            pins.showDebugPins()
        }
        if CommandLine.arguments.contains("--debug-editor") {
            editor.openDebugSample()
        }
        if CommandLine.arguments.contains("--debug-uninstall-plan") {
            // Dry run: lists what Uninstall would move to the Trash, changes nothing.
            let screenshots = Uninstaller.removableScreenshotFolder(saveFolder: Preferences.saveFolder,
                                                                    defaultFolder: AppPaths.defaultSaveFolder)
            for url in Uninstaller.plan(screenshots: screenshots).trash {
                Log.app.notice("Uninstall plan: \(url.path, privacy: .public)")
            }
        }
        #endif

        KeyboardShortcuts.onKeyUp(for: .captureArea) { [weak self] in self?.capture.captureArea() }
        KeyboardShortcuts.onKeyUp(for: .captureWindow) { [weak self] in self?.capture.captureWindow() }
        KeyboardShortcuts.onKeyUp(for: .captureScreen) { [weak self] in self?.capture.captureScreen() }
        KeyboardShortcuts.onKeyUp(for: .repeatLastArea) { [weak self] in self?.capture.repeatLastArea() }
        KeyboardShortcuts.onKeyUp(for: .timedCapture) { [weak self] in self?.capture.timedCapture() }
        KeyboardShortcuts.onKeyUp(for: .captureText) { [weak self] in self?.capture.captureText() }
        KeyboardShortcuts.onKeyUp(for: .pickColor) { [weak self] in self?.capture.pickColor() }
        KeyboardShortcuts.onKeyUp(for: .measure) { [weak self] in self?.capture.measure() }
        KeyboardShortcuts.onKeyUp(for: .pinFromClipboard) { [weak self] in self?.pins.pinFromClipboard() }
        KeyboardShortcuts.onKeyUp(for: .togglePins) { [weak self] in self?.pins.toggleVisibility() }
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

    /// Launching Glassine again (Finder, Spotlight) or clicking its Dock icon: bring back open
    /// editors, including minimized ones; with none open, show settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if editor.hasWindows {
            editor.showAll()
        } else {
            settings.show()
        }
        return false
    }

    @objc func showSettings(_ sender: Any?) {
        settings.show()
    }

    @objc private func captureArea() { capture.captureArea() }
    @objc private func captureWindow() { capture.captureWindow() }
    @objc private func captureScreen() { capture.captureScreen() }
    @objc private func repeatLastArea() { capture.repeatLastArea() }
    @objc private func timedCapture() { capture.timedCapture() }
    @objc private func captureText() { capture.captureText() }
    @objc private func pickColor() { capture.pickColor() }
    @objc private func measure() { capture.measure() }
    @objc private func pinFromClipboard() { pins.pinFromClipboard() }
    @objc private func togglePins() { pins.toggleVisibility() }
    @objc private func closeAllPins() { pins.closeAll() }

    private func makeCaptureMenu() -> NSMenu {
        let menu = NSMenu()
        let items: [(String, Selector, KeyboardShortcuts.Name?)] = [
            ("Capture Area", #selector(captureArea), .captureArea),
            ("Capture Window", #selector(captureWindow), .captureWindow),
            ("Capture Screen", #selector(captureScreen), .captureScreen),
            ("Repeat Last Area", #selector(repeatLastArea), .repeatLastArea),
            ("Capture with Timer", #selector(timedCapture), .timedCapture),
            ("Copy Text from Screen", #selector(captureText), .captureText),
            ("Pick Color", #selector(pickColor), .pickColor),
            ("Measure", #selector(measure), .measure),
            ("Pin from Clipboard", #selector(pinFromClipboard), .pinFromClipboard),
            ("Show/Hide Pins", #selector(togglePins), .togglePins),
            ("Close All Pins", #selector(closeAllPins), nil),
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
