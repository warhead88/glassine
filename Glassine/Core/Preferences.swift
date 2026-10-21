import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let captureArea = Self("captureArea", default: .init(.two, modifiers: [.command, .shift]))
    static let openSettings = Self("openSettings", default: .init(.comma, modifiers: [.command, .option, .shift]))
}

/// Keys for `UserDefaults.standard`, shared by `@AppStorage` in the UI and plain reads elsewhere.
enum PrefKey {
    static let showMenuBarIcon = "showMenuBarIcon"
    static let copyToClipboard = "copyToClipboard"
    static let saveToFile = "saveToFile"
    static let saveFolder = "saveFolder"
    static let showQuickAccess = "showQuickAccess"
    /// Seconds before the preview closes itself; 0 keeps it until closed.
    static let quickAccessAutoClose = "quickAccessAutoClose"
    static let hasLaunchedBefore = "hasLaunchedBefore"
}

enum Preferences {
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            PrefKey.showMenuBarIcon: false,
            PrefKey.copyToClipboard: true,
            PrefKey.saveToFile: true,
            PrefKey.saveFolder: AppPaths.defaultSaveFolder.path,
            PrefKey.showQuickAccess: true,
            PrefKey.quickAccessAutoClose: 10,
        ])
    }

    static var saveFolder: URL {
        let path = UserDefaults.standard.string(forKey: PrefKey.saveFolder) ?? AppPaths.defaultSaveFolder.path
        return URL(filePath: path, directoryHint: .isDirectory)
    }
}
