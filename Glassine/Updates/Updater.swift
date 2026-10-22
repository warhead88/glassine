import AppKit
import Sparkle

/// Checks for, downloads and installs updates with Sparkle, shown in Glassine's own window.
///
/// The feed (`SUFeedURL` in Info.plist) is the appcast attached to the latest GitHub release;
/// every update is checked against `SUPublicEDKey` before it is installed. Automatic checks run
/// once a day and send nothing but the request itself.
///
/// The Developer ID build only: a future App Store build updates through the App Store and
/// leaves this folder out.
@MainActor
@Observable
final class Updater: NSObject, SPUUpdaterDelegate {
    @ObservationIgnored private var updater: SPUUpdater?
    @ObservationIgnored private let driver = UpdateDriver()

    /// Mirrors Sparkle's setting, which it keeps in Glassine's defaults (`SUEnableAutomaticChecks`).
    var automaticallyChecks = true {
        didSet { updater?.automaticallyChecksForUpdates = automaticallyChecks }
    }

    static var currentVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))"
    }

    func start() {
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: self)
        do {
            try updater.start()
            self.updater = updater
            automaticallyChecks = updater.automaticallyChecksForUpdates
        } catch {
            Log.app.error("Updater did not start: \(error.localizedDescription, privacy: .public)")
        }
    }

    func checkForUpdates() {
        guard let updater, updater.canCheckForUpdates else {
            driver.showInFocus()
            return
        }
        updater.checkForUpdates()
    }

    #if DEBUG
    /// Debug (`--debug-update`): the update window with sample notes; buttons only close it.
    func showDebugUpdate() { driver.showSample() }
    #endif

    // MARK: SPUUpdaterDelegate

    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        #if DEBUG
        // Debug (`--debug-feed <url>`): test updates against a local appcast.
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--debug-feed"), index + 1 < arguments.count {
            return arguments[index + 1]
        }
        #endif
        return nil
    }
}

/// Sparkle's user interface, as calls into `UpdateModel` and its window.
@MainActor
private final class UpdateDriver: NSObject, SPUUserDriver {
    private let model = UpdateModel()
    private lazy var window = UpdateWindowController(model: model)
    private var userInitiated = false

    func showInFocus() { window.show(activate: true) }

    #if DEBUG
    func showSample() {
        model.present(.available(UpdateModel.Release(
            version: "0.2.0", size: 4_200_000, notes: ReleaseNotes.parse(UpdateModel.sampleNotes), infoURL: nil
        )))
        model.respond = { [weak self] _ in self?.window.close() }
        window.show(activate: true)
    }
    #endif

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        // SUEnableAutomaticChecks in Info.plist decides; this is only asked without it.
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        userInitiated = true
        model.present(.checking)
        model.respond = { _ in cancellation() }
        window.show(activate: true)
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        let release = UpdateModel.Release(
            version: appcastItem.displayVersionString,
            size: appcastItem.contentLength > 0 ? appcastItem.contentLength : nil,
            notes: ReleaseNotes.parse(appcastItem.itemDescription ?? ""),
            infoURL: appcastItem.isInformationOnlyUpdate ? appcastItem.infoURL : nil
        )
        model.present(state.stage == .notDownloaded ? .available(release) : .ready(release))
        model.respond = { [weak self] action in
            switch action {
            case .install: reply(.install)
            case .skip:
                reply(.skip)
                self?.window.close()
            case .later, .cancel, .done:
                reply(.dismiss)
                self?.window.close()
            case .learnMore:
                if let url = release.infoURL { NSWorkspace.shared.open(url) }
                reply(.dismiss)
                self?.window.close()
            }
        }
        // A check the user didn't ask for must not take focus from what they are doing.
        window.show(activate: state.userInitiated || userInitiated)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        model.present(.upToDate)
        model.respond = { [weak self] _ in
            acknowledgement()
            self?.window.close()
        }
        window.show(activate: true)
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        Log.app.error("Update failed: \(error.localizedDescription, privacy: .public)")
        guard userInitiated || window.isVisible else {
            acknowledgement() // a background check failing (offline, say) isn't worth a window
            return
        }
        model.present(.failed(error.localizedDescription))
        model.respond = { [weak self] _ in
            acknowledgement()
            self?.window.close()
        }
        window.show(activate: true)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        model.present(.downloading(received: 0, expected: model.release?.size))
        model.respond = { [weak self] _ in
            cancellation()
            self?.window.close()
        }
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        if case .downloading(let received, _) = model.phase {
            model.phase = .downloading(received: received, expected: expectedContentLength > 0 ? expectedContentLength : nil)
        }
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        if case .downloading(let received, let expected) = model.phase {
            model.phase = .downloading(received: received + length, expected: expected)
        }
    }

    func showDownloadDidStartExtractingUpdate() {
        model.phase = .preparing
        model.respond = nil
    }

    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard let release = model.release else {
            reply(.install)
            return
        }
        model.present(.ready(release))
        model.respond = { [weak self] action in
            if action == .install {
                reply(.install)
            } else {
                reply(.dismiss) // installs when Glassine quits
                self?.window.close()
            }
        }
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        model.phase = .installing
        model.respond = nil
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
        window.close()
    }

    func showUpdateInFocus() { window.show(activate: true) }

    func dismissUpdateInstallation() {
        userInitiated = false
        model.respond = nil
        window.close()
    }
}

/// State of the update window.
@MainActor
@Observable
final class UpdateModel {
    struct Release {
        var version: String
        var size: UInt64?
        var notes: [ReleaseNotes.Section]
        /// Set for an update that is only a link (e.g. it needs a newer macOS).
        var infoURL: URL?
    }

    enum Phase {
        case checking
        case available(Release)
        case downloading(received: UInt64, expected: UInt64?)
        case preparing
        case ready(Release)
        case installing
        case upToDate
        case failed(String)
    }

    enum Action { case install, skip, later, learnMore, cancel, done }

    var phase = Phase.checking
    private(set) var release: Release?
    /// What the window's buttons (and closing it) do in the current phase; nil while nothing can be chosen.
    @ObservationIgnored var respond: ((Action) -> Void)?

    func present(_ phase: Phase) {
        switch phase {
        case .available(let release), .ready(let release): self.release = release
        case .checking, .upToDate, .failed: release = nil
        default: break
        }
        self.phase = phase
    }

    /// Answers once: later calls (closing the window after a button) do nothing.
    func send(_ action: Action) {
        let respond = respond
        self.respond = nil
        respond?(action)
    }

    #if DEBUG
    static let sampleNotes = """
    ### Added
    - Screen recording with system audio and the microphone
    - GIF export, with a size estimate before saving
    ### Fixed
    - The start sound now plays when area capture is reopened quickly
    ### Removed
    - QR codes in text capture — they appear in every capture's preview instead
    """
    #endif
}
