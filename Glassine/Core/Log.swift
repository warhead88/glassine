import OSLog

/// Unified logging; view with `log stream --predicate 'subsystem == "com.warhead88.glassine"'`.
/// Goes to the system log rather than files, so there is nothing to clean up on uninstall.
enum Log {
    static let app = Logger(subsystem: AppPaths.bundleID, category: "app")
    static let capture = Logger(subsystem: AppPaths.bundleID, category: "capture")
}
