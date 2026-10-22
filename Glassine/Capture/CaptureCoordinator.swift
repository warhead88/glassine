import AppKit

/// Entry point for every capture: area (with window click), whole screen, repeat, timed.
@MainActor
final class CaptureCoordinator {
    private var overlays: [SelectionOverlayWindow] = []
    private var countdown: CountdownHUD?
    private var isCapturing = false
    private var overlayMode = OverlayMode.capture
    private let quickAccess = QuickAccessController()
    private let recording = RecordingController()

    /// Called when capture is attempted without Screen Recording access.
    var onMissingPermission: () -> Void = {}

    /// The last area selection, to capture the same region again.
    private var lastArea: (displayID: CGDirectDisplayID, rect: NSRect)?

    var canRepeatLastArea: Bool { lastArea != nil }

    init() {
        recording.onFinished = { [quickAccess] recording, screen in quickAccess.show(recording, on: screen) }
    }

    /// Called when the user pins a capture from its preview.
    var onPin: (CapturedImage) -> Void {
        get { quickAccess.onPin }
        set { quickAccess.onPin = newValue }
    }

    /// Called when the user opens a capture from its preview in the editor.
    var onEdit: (CapturedImage) -> Void {
        get { quickAccess.onEdit }
        set { quickAccess.onEdit = newValue }
    }

    /// Freeze all screens and let the user select an area or click a window.
    func captureArea() { startOverlay(.capture) }

    /// Click the window under the pointer to capture it.
    func captureWindow() { startOverlay(.window) }

    /// Select an area or click a window; its text goes to the clipboard.
    func captureText() { startOverlay(.text) }

    /// Pick an area, a window or the whole screen to record. Pressed again: records what's
    /// picked, or stops the recording.
    func record() {
        guard recording.isIdle else {
            recording.shortcutPressed()
            return
        }
        startOverlay(.record)
    }

    /// Click anywhere to copy the color under the pointer.
    func pickColor() { startOverlay(.color) }

    /// Measure distances on screen.
    func measure() { startOverlay(.measure) }

    private func startOverlay(_ mode: OverlayMode) {
        guard begin() else { return }
        overlayMode = mode
        let start = ContinuousClock.now
        Task {
            do {
                let snapshots = try await ScreenSnapshotter.snapshotAllScreens()
                let snapshotted = ContinuousClock.now
                presentOverlays(for: snapshots, windows: mode == .color || mode == .measure ? [] : WindowList.onScreenWindows())
                Log.capture.notice(
                    "Overlay ready in \(Self.ms(start), privacy: .public) ms (snapshot \(Self.ms(start, snapshotted), privacy: .public) ms, \(snapshots.count, privacy: .public) screens)"
                )
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
                deliver(snapshot.image, scale: snapshot.scale, on: snapshot.screen, sourceFrame: snapshot.screen.frame)
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
                deliver(
                    image, scale: snapshot.scale, on: snapshot.screen,
                    sourceFrame: snapshot.screen.globalRect(fromLocalFlipped: lastArea.rect)
                )
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
            SelectionOverlayWindow(snapshot: snapshot, windows: windows, mode: overlayMode) { [weak self] result in
                self?.finish(with: result, from: snapshot)
            }
        }

        // The overlays are non-activating panels: they take keyboard focus (Esc) without
        // activating Glassine. Activating would leave Glassine frontmost after the capture
        // and pull any open Glassine window (e.g. Settings) over the user's app.
        let defaults = UserDefaults.standard
        let isArea = overlayMode == .capture
        let animate = isArea
        let mouse = NSEvent.mouseLocation
        for overlay in overlays {
            if animate { overlay.alphaValue = 0 }
            overlay.orderFrontRegardless()
            if overlay.frame.contains(mouse) {
                overlay.makeKey()
            }
        }
        if animate {
            // The frozen screen equals the live one, so only the dimming visibly fades in.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                overlays.forEach { $0.animator().alphaValue = 1 }
            }
        }
        if isArea && defaults.bool(forKey: PrefKey.captureStartSound) {
            SoundEffects.play("Pop", volume: 0.35) // a soft click
        }
    }

    private func finish(with result: OverlayResult, from snapshot: ScreenSnapshot) {
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()
        isCapturing = false

        switch result {
        case .cancelled:
            return
        case .color(let color):
            SmartActions.copyColor(color)
        case .measurement(let text):
            SmartActions.copyMeasurement(text)
        case .area(let image, _) where overlayMode == .text:
            SmartActions.copyText(from: image)
        case .area(_, let rect) where overlayMode == .record:
            recording.prepare(.area(display: snapshot.screen, rect: rect),
                              area: snapshot.screen.globalRect(fromLocalFlipped: rect), on: snapshot.screen)
        case .window(let id) where overlayMode == .record:
            recording.prepare(.window(id), area: WindowList.frame(of: id) ?? snapshot.screen.frame, on: snapshot.screen)
        case .area(let image, let rect):
            if let displayID = snapshot.screen.displayID {
                lastArea = (displayID, rect)
            }
            deliver(
                image, scale: snapshot.scale, on: snapshot.screen,
                sourceFrame: snapshot.screen.globalRect(fromLocalFlipped: rect)
            )
        case .window(let id):
            Task {
                do {
                    let includeShadow = UserDefaults.standard.bool(forKey: PrefKey.windowShadow)
                    let (image, scale) = try await ScreenSnapshotter.captureWindow(id: id, includeShadow: includeShadow)
                    deliver(image, scale: scale, on: snapshot.screen, sourceFrame: WindowList.frame(of: id))
                } catch {
                    presentError(error)
                }
            }
        }
    }

    private func deliver(_ image: CGImage, scale: CGFloat, on screen: NSScreen, sourceFrame: NSRect?) {
        do {
            let capture = try CapturedImage(image: image, scale: scale)
            capture.sourceFrame = sourceFrame
            try CaptureOutput.deliver(capture)
            if UserDefaults.standard.bool(forKey: PrefKey.showQuickAccess) {
                quickAccess.show(capture, on: screen)
            }
        } catch {
            presentError(error)
        }
    }

    private static func ms(_ from: ContinuousClock.Instant, _ to: ContinuousClock.Instant = .now) -> Int {
        let (seconds, attoseconds) = (to - from).components
        return Int(seconds) * 1000 + Int(attoseconds / 1_000_000_000_000_000)
    }

    private func fail(_ error: Error) {
        isCapturing = false
        presentError(error)
    }

    private static func pixelRect(_ rect: NSRect, in snapshot: ScreenSnapshot) -> CGRect {
        SelectionGeometry.pixelRect(
            rect, viewSize: snapshot.screen.frame.size,
            imageSize: CGSize(width: snapshot.image.width, height: snapshot.image.height)
        )
    }

    #if DEBUG
    /// Debug hooks: `--debug-record-panel [full]` shows the recording controls for the middle of
    /// the main screen (or all of it); `--debug-record <seconds>` also records with the saved
    /// options and stops by itself (`pause`: pauses 1.5 s in, for 2 s). No overlay, no input needed.
    func debugRecord(seconds: Double?, fullScreen: Bool, pause: Bool = false) {
        guard let screen = NSScreen.main else { return }
        let size = screen.frame.size
        let rect = fullScreen ? CGRect(origin: .zero, size: size)
            : CGRect(x: size.width / 4, y: size.height / 4, width: size.width / 2, height: size.height / 2)
        recording.prepare(.area(display: screen, rect: rect), area: screen.globalRect(fromLocalFlipped: rect), on: screen)
        if CommandLine.arguments.contains("audio") {
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                recording.debugOpenAudioEditor()
            }
        }
        guard let seconds else { return }
        recording.record()
        Task {
            if CommandLine.arguments.contains("move") {
                try? await Task.sleep(for: .seconds(3.5 + 1.5))
                recording.debugMoveArea()
                try? await Task.sleep(for: .seconds(seconds - 1.5))
            } else if pause {
                try? await Task.sleep(for: .seconds(3.5 + 1.5))
                recording.debugTogglePause()
                try? await Task.sleep(for: .seconds(2))
                recording.debugTogglePause()
                try? await Task.sleep(for: .seconds(seconds - 1.5))
            } else {
                try? await Task.sleep(for: .seconds(3.5 + seconds)) // after the countdown
            }
            recording.stop()
        }
    }

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
