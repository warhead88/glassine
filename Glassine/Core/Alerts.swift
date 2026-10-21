import AppKit
import OSLog

@MainActor
enum Alerts {
    static func present(_ error: Error, log: Logger = Log.app) {
        log.error("\(error.localizedDescription, privacy: .public)")
        NSApp.activate()
        NSAlert(error: error).runModal()
    }
}
