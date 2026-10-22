import AppKit
import ServiceManagement

/// Removes Glassine completely: login item, Screen Recording permission, everything in
/// `AppPaths`, and the app itself. Files go to the Trash, never straight to deletion,
/// so a mistake can be undone. Saved screenshots stay unless the user asks otherwise.
@MainActor
enum Uninstaller {
    struct Plan: Equatable {
        /// Existing items to move to the Trash, app bundle last.
        var trash: [URL]
        var resetsScreenRecording = true
        var unregistersLoginItem = true
    }

    /// The screenshots folder the uninstaller may offer to remove: only the default
    /// `~/Pictures/Glassine`, never a folder the user picked (it could be the Desktop).
    static func removableScreenshotFolder(saveFolder: URL, defaultFolder: URL) -> URL? {
        saveFolder.standardizedFileURL == defaultFolder.standardizedFileURL ? defaultFolder : nil
    }

    static func plan(
        owned: [URL] = AppPaths.owned,
        appBundle: URL = Bundle.main.bundleURL,
        screenshots: URL? = nil,
        exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> Plan {
        var trash = owned.filter(exists)
        if let screenshots, exists(screenshots) { trash.append(screenshots) }
        // Only remove an installed app (in an Applications folder), never a build it was run from.
        if appBundle.pathExtension == "app", appBundle.deletingLastPathComponent().lastPathComponent == "Applications",
           exists(appBundle) {
            trash.append(appBundle)
        }
        return Plan(trash: trash)
    }

    /// Carries out the plan and quits. Each step is best-effort: a failure is logged and
    /// the rest still runs, so a half-broken install can still be cleaned up.
    static func run(_ plan: Plan) {
        Log.app.notice("Uninstalling: \(plan.trash.map(\.path).joined(separator: ", "), privacy: .public)")

        if plan.unregistersLoginItem, SMAppService.mainApp.status == .enabled {
            do { try SMAppService.mainApp.unregister() } catch {
                Log.app.error("Login item: \(error.localizedDescription, privacy: .public)")
            }
        }

        if plan.resetsScreenRecording {
            let tccutil = Process()
            tccutil.executableURL = URL(filePath: "/usr/bin/tccutil")
            tccutil.arguments = ["reset", "ScreenCapture", AppPaths.bundleID]
            do { try tccutil.run(); tccutil.waitUntilExit() } catch {
                Log.app.error("tccutil: \(error.localizedDescription, privacy: .public)")
            }
        }

        // Stop UserDefaults from writing the preferences file back after it's trashed.
        UserDefaults.standard.removePersistentDomain(forName: AppPaths.bundleID)
        UserDefaults.standard.synchronize()

        NSWorkspace.shared.recycle(plan.trash) { _, error in
            if let error {
                Log.app.error("Trash: \(error.localizedDescription, privacy: .public)")
            }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    /// Asks for confirmation, with an option to also remove screenshots from the default folder.
    static func confirmAndRun() {
        let screenshots = removableScreenshotFolder(saveFolder: Preferences.saveFolder, defaultFolder: AppPaths.defaultSaveFolder)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Uninstall Glassine?"
        alert.informativeText = """
        Glassine, its settings and caches will be moved to the Trash. \
        The login item and Screen Recording permission are removed too.
        """
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true

        var checkbox: NSButton?
        if let screenshots, FileManager.default.fileExists(atPath: screenshots.path) {
            let box = NSButton(checkboxWithTitle: "Also move saved screenshots (\((screenshots.path as NSString).abbreviatingWithTildeInPath)) to the Trash",
                               target: nil, action: nil)
            box.state = .off
            alert.accessoryView = box
            checkbox = box
        } else {
            alert.informativeText += "\n\nSaved screenshots are kept."
        }

        AppActivation.bringToFront()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        run(plan(screenshots: checkbox?.state == .on ? screenshots : nil))
    }
}
