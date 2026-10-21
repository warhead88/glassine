import Foundation

/// Every location Glassine writes to lives here, named after the bundle ID.
/// Keeping them in one place lets AppCleaner find our leftovers and lets
/// the future built-in uninstaller remove them without guessing.
enum AppPaths {
    static let bundleID = Bundle.main.bundleIdentifier ?? "com.warhead88.glassine"

    static var applicationSupport: URL { library("Application Support") }
    static var caches: URL { library("Caches") }
    static var logs: URL { library("Logs") }

    /// Short-lived files handed to other apps (drag & drop). Inside Caches; cleared on launch.
    static var temporaryFiles: URL { caches.appending(path: "Shared", directoryHint: .isDirectory) }

    /// Preferences plist written by `UserDefaults.standard`.
    static var preferences: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Preferences/\(bundleID).plist")
    }

    /// Everything the app owns. User content (saved screenshots) is deliberately not listed.
    static var owned: [URL] { [applicationSupport, caches, logs, preferences] }

    /// Default folder for saved screenshots. This is user content, never removed on uninstall.
    static var defaultSaveFolder: URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appending(path: "Glassine", directoryHint: .isDirectory)
    }

    private static func library(_ name: String) -> URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appending(path: name, directoryHint: .isDirectory)
            .appending(path: bundleID, directoryHint: .isDirectory)
    }
}
