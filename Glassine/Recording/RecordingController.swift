import AVFoundation
import AppKit

/// One recording at a time: the controls with the options, a countdown, the recording (with
/// pause), then saving (and making the GIF) and handing the file over like a screenshot —
/// clipboard, save folder, preview.
@MainActor
final class RecordingController {
    private enum State {
        case idle
        case setup(Setup)
        case recording(Session)
        case finishing
    }

    /// Picked, not yet recording.
    private struct Setup {
        var target: RecordingTarget
        let panel: RecordingPanel
        let screen: NSScreen
        var pointSize: CGSize
    }

    private struct Session {
        let recorder: ScreenRecorder
        let panel: RecordingPanel
        let options: RecordingOptions
        let screen: NSScreen
        let pointSize: CGSize
    }

    private var state = State.idle
    private var countdownTask: Task<Void, Never>?

    /// Called with the finished recording, to show its preview.
    var onFinished: (CapturedRecording, NSScreen) -> Void = { _, _ in }

    var isIdle: Bool {
        if case .idle = state { true } else { false }
    }

    /// The record shortcut pressed again: record what's set up, or stop the recording.
    func shortcutPressed() {
        switch state {
        case .setup: record()
        case .recording: stop()
        case .idle, .finishing: break
        }
    }

    /// Shows the controls for `target`; `area` is where it is on screen (global Cocoa coordinates).
    func prepare(_ target: RecordingTarget, area: NSRect, on screen: NSScreen) {
        guard isIdle else { return }
        let model = RecordingPanelModel(options: .current)
        // A frame marks a part of the screen; a window moves, and the whole screen needs none.
        let framed: Bool = if case .area = target { area.size != screen.frame.size } else { false }
        let panel = RecordingPanel(model: model, area: area, on: screen, framed: framed)
        model.onRecord = { [weak self] in self?.record() }
        model.onCancel = { [weak self] in self?.cancel() }
        model.onStop = { [weak self] in self?.stop() }
        model.onDiscard = { [weak self] in self?.discard() }
        panel.onAreaChange = { [weak self] rect in self?.areaChanged(to: rect) }
        state = .setup(Setup(target: target, panel: panel, screen: screen, pointSize: area.size))
        panel.show()
    }

    /// The frame was moved or resized: before recording, that's what will be recorded; while
    /// recording, the stream follows it.
    private func areaChanged(to rect: CGRect) {
        switch state {
        case .setup(var setup):
            setup.target = .area(display: setup.screen, rect: rect)
            setup.pointSize = rect.size
            state = .setup(setup)
        case .recording(let session):
            session.recorder.setSourceRect(rect)
        case .idle, .finishing:
            break
        }
    }

    /// Counts down in the record button, then records.
    func record() {
        guard case .setup(let setup) = state, countdownTask == nil else { return }
        let model = setup.panel.model
        countdownTask = Task { [weak self] in
            var options = model.options
            let wantsMicrophone = options.recordedTracks.contains { $0.sources.contains(where: \.isMicrophone) }
            let microphoneAllowed = wantsMicrophone && model.microphoneAvailable ? await Self.microphoneAllowed() : false
            if wantsMicrophone, !microphoneAllowed {
                options.audioTracks = AudioTrackPlan.removing(\.isMicrophone, from: options.audioTracks)
                HUD.show("Recording without the microphone",
                         detail: "Allow Glassine in System Settings → Privacy & Security → Microphone.",
                         symbol: "mic.slash")
            }
            for second in stride(from: 3, through: 1, by: -1) {
                model.phase = .countdown(second)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            self?.countdownTask = nil
            guard let self, case .setup(let current) = state else { return }
            await start(current, options: options) // with the area as it is now
        }
    }

    func cancel() {
        guard case .setup(let setup) = state else { return }
        countdownTask?.cancel()
        countdownTask = nil
        setup.panel.close()
        state = .idle
    }

    private func start(_ setup: Setup, options: RecordingOptions) async {
        guard case .setup = state else { return }
        state = .finishing
        do {
            try FileManager.default.createDirectory(at: AppPaths.temporaryFiles, withIntermediateDirectories: true)
            let baseName = FileNaming.baseName(prefix: Preferences.fileNamePrefix, date: .now)
            let url = FileNaming.uniqueURL(in: AppPaths.temporaryFiles, baseName: baseName,
                                          fileExtension: options.codec.fileExtension) {
                FileManager.default.fileExists(atPath: $0.path)
            }
            let recorder = try await ScreenRecorder.make(setup.target, options: options, url: url)
            recorder.onInterrupted = { [weak self] error in
                Log.capture.error("Recording stopped by the system: \(error.localizedDescription, privacy: .public)")
                self?.stop()
            }
            try await recorder.start()

            let model = setup.panel.model
            model.onPause = { recorder.setPaused($0) }
            model.startClock()
            setup.panel.startRecording()
            state = .recording(Session(recorder: recorder, panel: setup.panel, options: options,
                                       screen: setup.screen, pointSize: setup.pointSize))
            Log.capture.notice("Recording \(recorder.pixelSize.width, privacy: .public)×\(recorder.pixelSize.height, privacy: .public) at \(options.framesPerSecond, privacy: .public) fps")
        } catch {
            setup.panel.close()
            state = .idle
            Alerts.present(error, log: Log.capture)
        }
    }

    func stop() {
        guard case .recording(let session) = state else { return }
        state = .finishing
        let model = session.panel.model
        session.panel.hideOutline()
        model.phase = .saving

        Task {
            defer {
                session.panel.close()
                state = .idle
            }
            do {
                let video = session.recorder.url
                let duration = try await session.recorder.stop()
                let thumbnail = await CapturedRecording.firstFrame(of: video)

                var file = video
                if session.options.format == .gif {
                    file = video.deletingPathExtension().appendingPathExtension("gif")
                    model.phase = .makingGIF(progress: 0)
                    try await GIFEncoder.convert(video: video, to: file, fps: session.options.gifFramesPerSecond,
                                                 maxWidth: session.options.gifMaxWidth) { progress in
                        model.phase = .makingGIF(progress: progress)
                    }
                    try? FileManager.default.removeItem(at: video)
                }

                let recording = CapturedRecording(url: file, format: session.options.format, duration: duration,
                                                  thumbnail: thumbnail, pointSize: session.pointSize)
                deliver(recording, on: session.screen)
            } catch {
                Alerts.present(error, log: Log.capture)
            }
        }
    }

    func discard() {
        guard case .recording(let session) = state else { return }
        state = .finishing
        session.panel.close()
        Task {
            _ = try? await session.recorder.stop()
            try? FileManager.default.removeItem(at: session.recorder.url)
            state = .idle
        }
    }

    #if DEBUG
    func debugOpenAudioEditor() {
        if case .setup(let setup) = state { setup.panel.model.editingAudio = true }
    }

    func debugMoveArea() {
        if case .recording(let session) = state { session.panel.debugMoveArea() }
    }

    func debugTogglePause() {
        if case .recording(let session) = state { session.panel.model.togglePause() }
    }
    #endif

    /// The same "after capture" preferences as screenshots.
    private func deliver(_ recording: CapturedRecording, on screen: NSScreen) {
        let defaults = UserDefaults.standard
        do {
            if defaults.bool(forKey: PrefKey.saveToFile) {
                try recording.save()
            }
        } catch {
            Alerts.present(error, log: Log.capture)
        }
        if defaults.bool(forKey: PrefKey.copyToClipboard) {
            recording.copyToClipboard()
        }
        if defaults.bool(forKey: PrefKey.playSound) {
            SoundEffects.play("Tink")
        }
        if defaults.bool(forKey: PrefKey.showQuickAccess) {
            onFinished(recording, screen)
        }
    }

    private static func microphoneAllowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .audio)
        default: false
        }
    }
}
