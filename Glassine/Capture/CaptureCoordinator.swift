import AppKit

/// Entry point for every capture: area (with window click), whole screen, repeat, timed.
@MainActor
final class CaptureCoordinator {
    private var overlays: [SelectionOverlayWindow] = []
    private var countdown: CountdownHUD?
    private var isCapturing = false
    private let quickAccess = QuickAccessController()

    /// Called when capture is attempted without Screen Recording access.
    var onMissingPermission: () -> Void = {}

    /// The last area selection, to capture the same region again.
    private var lastArea: (displayID: CGDirectDisplayID, rect: NSRect)?

    var canRepeatLastArea: Bool { lastArea != nil }

    /// Freeze all screens and let the user select an area or click a window.
    func captureArea() {
        guard begin() else { return }
        Task {
            do {
                let snapshots = try await ScreenSnapshotter.snapshotAllScreens()
                presentOverlays(for: snapshots, windows: WindowList.onScreenWindows())
            } catch {
                fail(error)
            }
        }
    }

    /// Capture the screen under the pointer immediately.
    func captureScreen() {
        guard begin() else { return }
        Task {
            do {
                let snapshots = try await ScreenSnapshotter.snapshotAllScreens()
                let mouse = NSEvent.mouseLocation
                guard let snapshot = snapshots.first(where: { $0.screen.frame.contains(mouse) }) ?? snapshots.first else {
                    isCapturing = false
                    return
                }
                isCapturing = false
                deliver(snapshot.image, scale: snapshot.scale, on: snapshot.screen)
            } catch {
                fail(error)
            }
        }
    }

    /// Capture the previously selected area again, without the overlay.
    func repeatLastArea() {
        guard let lastArea else {
            NSSound.beep()
            return
        }
        guard begin() else { return }
        Task {
            do {
                let snapshots = try await ScreenSnapshotter.snapshotAllScreens()
                isCapturing = false
                guard let snapshot = snapshots.first(where: { $0.screen.displayID == lastArea.displayID }),
                      let image = snapshot.image.cropping(to: Self.pixelRect(lastArea.rect, in: snapshot))
                else {
                    NSSound.beep()
                    return
                }
                deliver(image, scale: snapshot.scale, on: snapshot.screen)
            } catch {
                fail(error)
            }
        }
    }

    /// Count down (so menus and hover states can be opened), then capture an area.
    func timedCapture() {
        guard !isCapturing, countdown == nil else { return }
        guard CGPreflightScreenCaptureAccess() else {
            onMissingPermission()
            return
        }
        let seconds = max(UserDefaults.standard.integer(forKey: PrefKey.timerDelay), 1)
        let hud = CountdownHUD(seconds: seconds) { [weak self] completed in
            self?.countdown = nil
            if completed { self?.captureArea() }
        }
        countdown = hud
        hud.start()
    }

    // MARK: Flow

    private func begin() -> Bool {
        guard !isCapturing else { return false }
        guard CGPreflightScreenCaptureAccess() else {
            onMissingPermission()
            return false
        }
        isCapturing = true
        return true
    }

    private func presentOverlays(for snapshots: [ScreenSnapshot], windows: [WindowCandidate]) {
        overlays = snapshots.map { snapshot in
            SelectionOverlayWindow(snapshot: snapshot, windows: windows) { [weak self] result in
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

    private func finish(with result: OverlayResult, from snapshot: ScreenSnapshot) {
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()
        isCapturing = false

        switch result {
        case .cancelled:
            return
        case .area(let image, let rect):
            if let displayID = snapshot.screen.displayID {
                lastArea = (displayID, rect)
            }
            deliver(image, scale: snapshot.scale, on: snapshot.screen)
        case .window(let id):
            Task {
                do {
                    let includeShadow = UserDefaults.standard.bool(forKey: PrefKey.windowShadow)
                    let (image, scale) = try await ScreenSnapshotter.captureWindow(id: id, includeShadow: includeShadow)
                    deliver(image, scale: scale, on: snapshot.screen)
                } catch {
                    presentError(error)
                }
            }
        }
    }

    private func deliver(_ image: CGImage, scale: CGFloat, on screen: NSScreen) {
        do {
            let capture = try CapturedImage(image: image, scale: scale)
            try CaptureOutput.deliver(capture)
            if UserDefaults.standard.bool(forKey: PrefKey.showQuickAccess) {
                quickAccess.show(capture, on: screen)
            }
        } catch {
            presentError(error)
        }
    }

    private func fail(_ error: Error) {
        isCapturing = false
        presentError(error)
    }

    private static func pixelRect(_ rect: NSRect, in snapshot: ScreenSnapshot) -> CGRect {
        let sx = CGFloat(snapshot.image.width) / snapshot.screen.frame.width
        let sy = CGFloat(snapshot.image.height) / snapshot.screen.frame.height
        return CGRect(x: rect.minX * sx, y: rect.minY * sy, width: rect.width * sx, height: rect.height * sy).integral
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
