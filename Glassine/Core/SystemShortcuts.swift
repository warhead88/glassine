import AppKit
import KeyboardShortcuts

/// macOS's own screenshot shortcuts. Glassine's defaults (⇧⌘3, ⇧⌘4, ⇧⌘5) are the same keys,
/// and macOS keeps them while its shortcuts are on, so Glassine says so and points to the setting.
enum SystemScreenshotShortcuts {
    /// IDs in `com.apple.symbolichotkeys` for the conflicting shortcuts and how they read.
    static let all: [(id: Int, label: String, shortcut: KeyboardShortcuts.Shortcut)] = [
        (28, "⇧⌘3", .init(.three, modifiers: [.command, .shift])),
        (30, "⇧⌘4", .init(.four, modifiers: [.command, .shift])),
        (184, "⇧⌘5", .init(.five, modifiers: [.command, .shift])),
    ]

    /// Which of `ids` are on. A shortcut missing from the plist has never been changed: on.
    static func enabledIDs(_ ids: [Int], in hotkeys: [String: Any]?) -> Set<Int> {
        Set(ids.filter { id in
            guard let entry = hotkeys?[String(id)] as? [String: Any] else { return true }
            if let enabled = entry["enabled"] as? Bool { return enabled }
            if let enabled = entry["enabled"] as? Int { return enabled != 0 }
            return true
        })
    }

    /// Labels of system shortcuts that are on and also assigned in Glassine, e.g. ["⇧⌘4"].
    static var conflicts: [String] {
        let hotkeys = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys")
        let enabled = enabledIDs(all.map(\.id), in: hotkeys)
        let ours = Set(KeyboardShortcuts.Name.captureNames.compactMap { KeyboardShortcuts.getShortcut(for: $0) })
        return all.filter { enabled.contains($0.id) && ours.contains($0.shortcut) }.map(\.label)
    }

    /// System Settings → Keyboard, where Keyboard Shortcuts… → Screenshots lives.
    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

extension KeyboardShortcuts.Name {
    /// The shortcuts that may collide with macOS's screenshot keys.
    static let captureNames: [Self] = [.captureArea, .captureWindow, .captureScreen]
}
