import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let captureArea = Self("captureArea", default: .init(.two, modifiers: [.command, .shift]))
    static let captureWindow = Self("captureWindow", default: .init(.two, modifiers: [.command, .option, .shift]))
    static let captureScreen = Self("captureScreen", default: .init(.one, modifiers: [.command, .shift]))
    static let repeatLastArea = Self("repeatLastArea")
    static let timedCapture = Self("timedCapture")
    static let pinFromClipboard = Self("pinFromClipboard")
    /// Has a default so a click-through pin can always be hidden, even with the menu bar icon off.
    static let togglePins = Self("togglePins", default: .init(.p, modifiers: [.command, .option, .shift]))
    static let captureText = Self("captureText", default: .init(.t, modifiers: [.command, .option, .shift]))
    static let pickColor = Self("pickColor", default: .init(.c, modifiers: [.command, .option, .shift]))
    static let measure = Self("measure", default: .init(.m, modifiers: [.command, .option, .shift]))
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
    /// The system Screen Recording prompt has been shown (macOS shows it only once).
    static let screenAccessPrompted = "screenAccessPrompted"
    /// "You're all set" was shown after permission arrived.
    static let screenAccessConfirmed = "screenAccessConfirmed"

    static let showMagnifier = "showMagnifier"
    /// When on, releasing the mouse leaves an adjustable selection; Return captures it.
    static let adjustBeforeCapture = "adjustBeforeCapture"
    static let windowShadow = "windowShadow"
    static let timerDelay = "timerDelay"
    static let playSound = "playSound"
    static let captureStartSound = "captureStartSound"
    static let colorFormat = "colorFormat"
    static let areaFrameStyle = "areaFrameStyle"

    static let imageFormat = "imageFormat"
    static let fileNamePrefix = "fileNamePrefix"
    /// Downscale Retina captures to their point size.
    static let saveAtStandardResolution = "saveAtStandardResolution"
}

enum ImageFormat: String, CaseIterable, Identifiable {
    case png, jpeg, heic

    var id: Self { self }

    var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        case .heic: "heic"
        }
    }
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
            PrefKey.captureStartSound: true,
            PrefKey.colorFormat: ColorFormat.hex.rawValue,
            PrefKey.areaFrameStyle: AreaFrameStyle.notch.rawValue,
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

    static var areaFrameStyle: AreaFrameStyle {
        AreaFrameStyle(rawValue: defaults.string(forKey: PrefKey.areaFrameStyle) ?? "") ?? .notch
    }

    static var colorFormat: ColorFormat {
        ColorFormat(rawValue: defaults.string(forKey: PrefKey.colorFormat) ?? "") ?? .hex
    }

    static var imageFormat: ImageFormat {
        ImageFormat(rawValue: defaults.string(forKey: PrefKey.imageFormat) ?? "") ?? .png
    }

    static var fileNamePrefix: String {
        FileNaming.sanitizedPrefix(defaults.string(forKey: PrefKey.fileNamePrefix))
    }
}
