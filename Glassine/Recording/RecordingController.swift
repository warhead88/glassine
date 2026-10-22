import AVFoundation
import AppKit

/// One recording at a time: countdown, recording with its controls, then saving (and making the
/// GIF) and handing the file over like a screenshot — clipboard, save folder, preview.
@MainActor
final class RecordingController {
    private enum State {
        case idle
        case countingDown(CountdownHUD)
        case recording(Session)
        case finishing
    }

    private struct Session {
        let recorder: ScreenRecorder
        let hud: RecordingHUD
        let options: RecordingOptions
        let screen: NSScreen
        let pointSize: CGSize
    }

    private var state = State.idle

    /// Called with the finished recording, to show its preview.
    var onFinished: (CapturedRecording, NSScreen) -> Void = { _, _ in }

    var isIdle: Bool {
        if case .idle = state { true } else { false }
    }

    /// The record shortcut pressed again: stop a recording, cancel a countdown.
    func stopOrCancel() {
        switch state {
        case .countingDown(let countdown): countdown.cancel()
        case .recording: stop()
        case .idle, .finishing: break
        }
    }

    /// Counts down, then records `target`. `area` is where it is on screen (global Cocoa coordinates).
    func begin(_ target: RecordingTarget, format: RecordingFormat, area: NSRect, on screen: NSScreen) {
        guard isIdle else { return }
        var options = RecordingOptions.current
        options.format = format
        state = .finishing // busy while asking for the microphone

        Task { [weak self] in
            if options.microphone, !(await Self.microphoneAllowed()) {
                options.microphone = false
                HUD.show("Recording without the microphone",
                         detail: "Allow Glassine in System Settings → Privacy & Security → Microphone.",
                         symbol: "mic.slash")
            }
            let countdown = CountdownHUD(seconds: 3) { [weak self] completed in
                guard let self else { return }
                if completed {
                    Task { await self.start(target, options: options, area: area, on: screen) }
                } else {
                    state = .idle
                }
            }
            self?.state = .countingDown(countdown)
            countdown.start()
        }
    }

    private func start(_ target: RecordingTarget, options: RecordingOptions, area: NSRect, on screen: NSScreen) async {
        do {
            try FileManager.default.createDirectory(at: AppPaths.temporaryFiles, withIntermediateDirectories: true)
            let baseName = FileNaming.baseName(prefix: Preferences.fileNamePrefix, date: .now)
            let url = FileNaming.uniqueURL(in: AppPaths.temporaryFiles, baseName: baseName, fileExtension: "mp4") {
                FileManager.default.fileExists(atPath: $0.path)
            }
            let recorder = try await ScreenRecorder.make(target, options: options, url: url)
            recorder.onInterrupted = { [weak self] error in
                Log.capture.error("Recording stopped by the system: \(error.localizedDescription, privacy: .public)")
                self?.stop()
            }
            try await recorder.start()

            let framed: Bool = if case .area = target { area.size != screen.frame.size } else { false }
            let hud = RecordingHUD(area: area, on: screen, framed: framed,
                                   onStop: { [weak self] in self?.stop() },
                                   onDiscard: { [weak self] in self?.discard() })
            hud.model.phase = .recording(since: .now)
            hud.show()
            state = .recording(Session(recorder: recorder, hud: hud, options: options, screen: screen, pointSize: area.size))
            Log.capture.notice("Recording \(recorder.pixelSize.width, privacy: .public)×\(recorder.pixelSize.height, privacy: .public) at \(options.framesPerSecond, privacy: .public) fps")
        } catch {
            state = .idle
            Alerts.present(error, log: Log.capture)
        }
    }

    func stop() {
        guard case .recording(let session) = state else { return }
        state = .finishing
        session.hud.hideOutline()
        session.hud.model.phase = .saving

        Task {
            defer {
                session.hud.close()
                state = .idle
            }
            do {
                let video = session.recorder.url
                let duration = try await session.recorder.stop()
                let thumbnail = await CapturedRecording.firstFrame(of: video)

                var file = video
                if session.options.format == .gif {
                    file = video.deletingPathExtension().appendingPathExtension("gif")
                    session.hud.model.phase = .makingGIF(progress: 0)
                    try await GIFEncoder.convert(video: video, to: file, fps: session.options.gifFramesPerSecond,
                                                 maxWidth: session.options.gifMaxWidth) { progress in
                        session.hud.model.phase = .makingGIF(progress: progress)
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
        session.hud.close()
        Task {
            _ = try? await session.recorder.stop()
            try? FileManager.default.removeItem(at: session.recorder.url)
            state = .idle
        }
    }

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
