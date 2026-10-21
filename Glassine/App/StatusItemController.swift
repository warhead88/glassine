import AppKit

/// Optional menu bar icon. Off by default; toggled in settings.
@MainActor
final class StatusItemController {
    private var item: NSStatusItem?
    private let makeMenu: () -> NSMenu

    init(menu: @escaping () -> NSMenu) {
        self.makeMenu = menu
    }

    var isVisible: Bool {
        get { item != nil }
        set {
            guard newValue != isVisible else { return }
            if newValue {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                item.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Glassine")
                item.menu = makeMenu()
                self.item = item
            } else if let item {
                NSStatusBar.system.removeStatusItem(item)
                self.item = nil
            }
        }
    }
}
