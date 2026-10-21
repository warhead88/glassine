import AppKit

/// Runs one area capture: freeze every display, let the user drag a region, deliver the crop.
@MainActor
final class CaptureCoordinator {
    private var overlays: [SelectionOverlayWindow] = []
    private var isCapturing = false
    private let quickAccess = QuickAccessController()

    func captureArea() {
        guard !isCapturing else { return }

        guard CGPreflightScreenCaptureAccess() else {
            // Shows the system prompt the first time; afterwards the user has to
            // grant access in System Settings and relaunch.
            CGRequestScreenCaptureAccess()
            return
        }

        isCapturing = true
        Task {
            do {
                let snapshots = try await ScreenSnapshotter.snapshotAllScreens()
                presentOverlays(for: snapshots)
            } catch {
                isCapturing = false
                presentError(error)
            }
        }
    }

    private func presentOverlays(for snapshots: [ScreenSnapshot]) {
        overlays = snapshots.map { snapshot in
            SelectionOverlayWindow(snapshot: snapshot) { [weak self] result in
                self?.finish(with: result, from: snapshot)
            }
        }

        // The overlays are non-activating panels: they take keyboard focus (Esc) without
        // activating Glassine. Activating would leave Glassine frontmost after the capture
        // and pull any open Glassine window (e.g. Settings) over the user's app.
        let mouse = NSEvent.mouseLocation
        for overlay in overlays {
            overlay.orderFrontRegardless()
            if overlay.frame.contains(mouse) {
                overlay.makeKey()
            }
        }
    }

    private func finish(with image: CGImage?, from snapshot: ScreenSnapshot) {
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()
        isCapturing = false

        guard let image else { return }
        do {
            let capture = try CapturedImage(image: image, scale: snapshot.scale)
            try CaptureOutput.deliver(capture)
            if UserDefaults.standard.bool(forKey: PrefKey.showQuickAccess) {
                quickAccess.show(capture, on: snapshot.screen)
            }
        } catch {
            presentError(error)
        }
    }

    #if DEBUG
    /// Debug hook (`--debug-preview`): shows previews of a few crops of the main screen
    /// without the hotkey or touching the clipboard and save folder.
    func showDebugPreviews() {
        Task {
            guard let snapshot = try? await ScreenSnapshotter.snapshotAllScreens().first else { return }
            let w = snapshot.image.width, h = snapshot.image.height
            let crops = [
                CGRect(x: 0, y: 0, width: w / 2, height: h / 2),
                CGRect(x: w / 4, y: h / 4, width: w / 6, height: h / 2),
                CGRect(x: 0, y: 0, width: 40, height: 40),
            ]
            for crop in crops {
                guard let image = snapshot.image.cropping(to: crop),
                      let capture = try? CapturedImage(image: image, scale: snapshot.scale) else { continue }
                quickAccess.show(capture, on: snapshot.screen)
            }
        }
    }
    #endif

    private func presentError(_ error: Error) {
        Alerts.present(error, log: Log.capture)
    }
}
