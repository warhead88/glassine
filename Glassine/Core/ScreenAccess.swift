import AppKit

/// Screen Recording permission, asked for the macOS way, one step at a time:
/// 1. the system prompt (its "Open System Settings" lists Glassine, ready to switch on);
/// 2. the user turns Glassine on in System Settings;
/// 3. macOS offers "Quit & Reopen", and Glassine comes back with access.
/// macOS shows the prompt only once per app, so later requests open the settings pane directly.
enum ScreenAccess {
    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Whether the system prompt has been shown, i.e. step 1 is done.
    static var hasPrompted: Bool { UserDefaults.standard.bool(forKey: PrefKey.screenAccessPrompted) }

    /// The one action behind every "Allow…" button: the prompt the first time, the pane after.
    /// Never both — two windows for one permission is confusing.
    static func request() {
        if hasPrompted {
            openSettings()
        } else {
            UserDefaults.standard.set(true, forKey: PrefKey.screenAccessPrompted)
            _ = CGRequestScreenCaptureAccess()
        }
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Title for the request button, matching what clicking it will do.
    static var requestTitle: String { hasPrompted ? "Open System Settings…" : "Allow Screen Recording…" }
}
