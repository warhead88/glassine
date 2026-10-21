import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let captureArea = Self("captureArea", default: .init(.two, modifiers: [.command, .shift]))
    static let captureScreen = Self("captureScreen", default: .init(.one, modifiers: [.command, .shift]))
    static let repeatLastArea = Self("repeatLastArea")
    static let timedCapture = Self("timedCapture")
    static let pinFromClipboard = Self("pinFromClipboard")
    static let togglePins = Self("togglePins")
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

    static let showMagnifier = "showMagnifier"
    /// When on, releasing the mouse leaves an adjustable selection; Return captures it.
    static let adjustBeforeCapture = "adjustBeforeCapture"
    static let windowShadow = "windowShadow"
    static let timerDelay = "timerDelay"
    static let playSound = "playSound"

    static let imageFormat = "imageFormat"
    static let fileNamePrefix = "fileNamePrefix"
    /// Downscale Retina captures to their point size.
    static let saveAtStandardResolution = "saveAtStandardResolution"
}

enum ImageFormat: String, CaseIterable, Identifiable {
    case png, jpeg, heic

    var id: Self { self }
    var title: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        case .heic: "HEIC"
        }
    }
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
            PrefKey.showMagnifier: true,
            PrefKey.adjustBeforeCapture: false,
            PrefKey.windowShadow: true,
            PrefKey.timerDelay: 5,
            PrefKey.playSound: true,
            PrefKey.imageFormat: ImageFormat.png.rawValue,
            PrefKey.fileNamePrefix: "Glassine",
            PrefKey.saveAtStandardResolution: false,
        ])
    }

    private static var defaults: UserDefaults { .standard }

    static var saveFolder: URL {
        let path = defaults.string(forKey: PrefKey.saveFolder) ?? AppPaths.defaultSaveFolder.path
        return URL(filePath: path, directoryHint: .isDirectory)
    }

    static var imageFormat: ImageFormat {
        ImageFormat(rawValue: defaults.string(forKey: PrefKey.imageFormat) ?? "") ?? .png
    }

    static var fileNamePrefix: String {
        let prefix = defaults.string(forKey: PrefKey.fileNamePrefix)?.trimmingCharacters(in: .whitespaces) ?? ""
        // Keep names valid on disk: no path separators or Finder-hostile colons.
        let cleaned = prefix.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return cleaned.isEmpty ? "Glassine" : cleaned
    }
}
