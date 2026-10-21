import AppKit

/// Optional menu bar icon. Off by default; toggled in settings.
@MainActor
final class StatusItemController: NSObject {
    private var item: NSStatusItem?
    private let onCapture: () -> Void
    private let onSettings: () -> Void

    init(onCapture: @escaping () -> Void, onSettings: @escaping () -> Void) {
        self.onCapture = onCapture
        self.onSettings = onSettings
    }

    var isVisible: Bool {
        get { item != nil }
        set {
            guard newValue != isVisible else { return }
            if newValue {
                install()
            } else if let item {
                NSStatusBar.system.removeStatusItem(item)
                self.item = nil
            }
        }
    }

    private func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Glassine")

        let menu = NSMenu()
        menu.addItem(withTitle: "Capture Area", action: #selector(capture), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Quit Glassine", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu

        self.item = item
    }

    @objc private func capture() { onCapture() }
    @objc private func openSettings() { onSettings() }
}
