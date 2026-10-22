import AVFoundation
import ScreenCaptureKit

/// What to record: part of a display, or one window wherever it moves.
enum RecordingTarget {
    /// `rect` in the display's points, top-left origin; the whole display when it covers it.
    case area(display: NSScreen, rect: CGRect)
    case window(CGWindowID)
}

enum RecordingError: LocalizedError {
    case unavailable
    case noFrames

    var errorDescription: String? {
        switch self {
        case .unavailable: "The window or display is no longer available."
        case .noFrames: "Nothing was recorded."
        }
    }
}

/// Streams the screen with ScreenCaptureKit straight into the hardware encoder: frames arrive as
/// GPU surfaces and go to the media engine without being copied or drawn.
///
/// Sound comes from its own audio-only streams, one per source (system, a microphone, an app —
/// ScreenCaptureKit filters sound by app). Each source is kept uncompressed on its own track of a
/// working file; on stop `AudioMixdown` mixes them into the user's tracks and copies the video
/// over as it is. Without sound the video is written to its final file directly.
final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    // The writer and inputs are used only on `queue` once capture starts.
    private let queue = DispatchQueue(label: "com.warhead88.glassine.recorder", qos: .userInitiated)
    private var videoStream: SCStream!
    private var videoConfig: SCStreamConfiguration!
    /// A new area waiting for the stream to take the previous one.
    private var pendingSourceRect: CGRect?
    private var isUpdatingSourceRect = false
    private var audioStreams: [SCStream] = []
    /// Which writer input each audio stream feeds.
    private var audioInputs: [ObjectIdentifier: AVAssetWriterInput] = [:]
    private let writer: AVAssetWriter
    private let video: AVAssetWriterInput
    private var sessionStarted = false
    private var firstVideoTime = CMTime.invalid
    private var lastVideoTime = CMTime.invalid
    /// While paused, samples are dropped; afterwards they're moved back by the time spent paused,
    /// so the file plays straight through.
    private var pausedSince: CMTime?
    private var pausedTotal = CMTime.zero

    /// The finished recording.
    let url: URL
    /// Where sources are recorded before the mixdown; nil without sound.
    private let workingURL: URL?
    private let mixPlan: [[Int]]
    private let trackNames: [String]
    private let codec: VideoCodec
    let pixelSize: (width: Int, height: Int)
    /// Sources left out because their app isn't running.
    private(set) var missingSources: [AudioSource] = []
    /// The stream stopped by itself (display gone, sharing stopped from the menu bar).
    var onInterrupted: (@MainActor (Error) -> Void)?

    @MainActor
    static func make(_ target: RecordingTarget, options: RecordingOptions, url: URL) async throws -> ScreenRecorder {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let config = SCStreamConfiguration()
        let filter: SCContentFilter
        let size: (width: Int, height: Int)
        var display = content.displays.first

        switch target {
        case .area(let screen, let rect):
            display = content.displays.first(where: { $0.displayID == screen.displayID })
            guard let display else { throw RecordingError.unavailable }
            // Glassine's own windows (the recording controls, previews) stay out of the video.
            filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            size = RecordingMath.pixelSize(points: rect.size, scale: options.retina ? screen.backingScaleFactor : 1)
            if rect.size != screen.frame.size {
                config.sourceRect = rect
            }
        case .window(let id):
            guard let window = content.windows.first(where: { $0.windowID == id }) else { throw RecordingError.unavailable }
            filter = SCContentFilter(desktopIndependentWindow: window)
            let info = SCShareableContent.info(for: filter)
            size = RecordingMath.pixelSize(points: info.contentRect.size, scale: options.retina ? CGFloat(info.pointPixelScale) : 1)
            config.ignoreShadowsSingleWindow = true
        }

        config.width = size.width
        config.height = size.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(options.framesPerSecond))
        config.showsCursor = options.showsCursor
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.queueDepth = 6

        // Sound comes from every running app, not only those with a window on screen: a minimized
        // or hidden player (Music on another Space) still plays. Apps that quit are left out.
        let runningApps = options.recordedTracks.isEmpty ? []
            : try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false).applications
        let missing = AudioTrackPlan.missingApps(in: options.recordedTracks, running: Set(runningApps.map(\.bundleIdentifier)))
        let tracks = AudioTrackPlan.removing(missing.contains, from: options.recordedTracks).filter { !$0.sources.isEmpty }
        let sources = AudioTrackPlan.sources(of: tracks)

        let recorder = try ScreenRecorder(
            url: url, size: size, options: options, sourceCount: sources.count,
            mixPlan: AudioTrackPlan.mix(tracks),
            trackNames: tracks.enumerated().map { AudioTrackPlan.name(of: $1, number: $0 + 1) }
        )
        let stream = SCStream(filter: filter, configuration: config, delegate: recorder)
        try stream.addStreamOutput(recorder, type: .screen, sampleHandlerQueue: recorder.queue)
        recorder.videoStream = stream
        recorder.videoConfig = config
        recorder.missingSources = missing

        for (index, source) in sources.enumerated() {
            guard let display else { throw RecordingError.unavailable }
            let audio = try Self.audioStream(for: source, display: display, ownApps: ownApps,
                                             apps: runningApps, recorder: recorder)
            recorder.audioStreams.append(audio)
            recorder.audioInputs[ObjectIdentifier(audio)] = recorder.sourceInputs[index]
        }
        return recorder
    }

    /// A stream that only carries sound: its picture is 2×2 pixels once a second and ignored.
    @MainActor
    private static func audioStream(for source: AudioSource, display: SCDisplay, ownApps: [SCRunningApplication],
                                    apps: [SCRunningApplication], recorder: ScreenRecorder) throws -> SCStream {
        let config = SCStreamConfiguration()
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.sampleRate = 48_000
        config.channelCount = 2
        config.excludesCurrentProcessAudio = true

        let filter: SCContentFilter
        var outputType = SCStreamOutputType.audio
        switch source {
        case .system:
            filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            config.capturesAudio = true
        case .app(let bundleID, _):
            let app = apps.filter { $0.bundleIdentifier == bundleID }
            filter = SCContentFilter(display: display, including: app, exceptingWindows: [])
            config.capturesAudio = true
        case .microphone(let id, _):
            filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            guard #available(macOS 15.0, *) else { throw RecordingError.unavailable }
            config.captureMicrophone = true
            config.microphoneCaptureDeviceID = id
            outputType = .microphone
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: recorder)
        try stream.addStreamOutput(recorder, type: .screen, sampleHandlerQueue: recorder.queue)
        try stream.addStreamOutput(recorder, type: outputType, sampleHandlerQueue: recorder.queue)
        return stream
    }

    /// One uncompressed input per source, in the working file.
    private var sourceInputs: [AVAssetWriterInput] = []

    private init(url: URL, size: (width: Int, height: Int), options: RecordingOptions, sourceCount: Int,
                 mixPlan: [[Int]], trackNames: [String]) throws {
        self.url = url
        self.pixelSize = size
        self.mixPlan = mixPlan
        self.trackNames = trackNames
        self.codec = options.codec
        workingURL = sourceCount > 0
            ? url.deletingPathExtension().appendingPathExtension("sources.mov")
            : nil
        writer = try AVAssetWriter(outputURL: workingURL ?? url, fileType: workingURL != nil ? .mov : options.codec.fileType)

        var settings: [String: Any] = [
            AVVideoCodecKey: options.codec.avCodec,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ]
        if options.codec.hasBitrate {
            var compression: [String: Any] = [
                AVVideoAverageBitRateKey: RecordingMath.bitrate(width: size.width, height: size.height,
                                                                fps: options.framesPerSecond,
                                                                codec: options.codec, mbps: options.bitrateMbps),
                AVVideoExpectedSourceFrameRateKey: options.framesPerSecond,
                AVVideoMaxKeyFrameIntervalKey: options.framesPerSecond * 2,
            ]
            if options.codec == .h264 {
                compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
            }
            settings[AVVideoCompressionPropertiesKey] = compression
        }
        video = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        video.expectsMediaDataInRealTime = true
        writer.add(video)

        for _ in 0..<sourceCount {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: AudioMixdown.pcm)
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            sourceInputs.append(input)
        }
        super.init()
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }

    func start() async throws {
        try await videoStream.startCapture()
        for stream in audioStreams {
            try await stream.startCapture()
        }
    }

    /// Moves (or zooms) the recorded area while recording; the video keeps its size. Updates are
    /// coalesced so a drag doesn't queue up dozens of them.
    @MainActor
    func setSourceRect(_ rect: CGRect) {
        pendingSourceRect = rect
        guard !isUpdatingSourceRect, let rect = pendingSourceRect else { return }
        pendingSourceRect = nil
        isUpdatingSourceRect = true
        videoConfig.sourceRect = rect
        Task { @MainActor in
            do {
                try await videoStream.updateConfiguration(videoConfig)
                Log.capture.debug("Recording area: \(rect.debugDescription, privacy: .public)")
            } catch {
                Log.capture.error("Area change failed: \(error.localizedDescription, privacy: .public)")
            }
            isUpdatingSourceRect = false
            if let next = pendingSourceRect { setSourceRect(next) }
        }
    }

    func setPaused(_ paused: Bool) {
        let now = Self.now
        queue.async { [self] in
            if paused, pausedSince == nil {
                pausedSince = now
            } else if !paused, let since = pausedSince {
                pausedTotal = CMTimeAdd(pausedTotal, CMTimeSubtract(now, since))
                pausedSince = nil
            }
        }
    }

    private static var now: CMTime { CMClockGetTime(CMClockGetHostTimeClock()) }

    /// Stops, finishes the file (mixing the sound into its tracks); returns the length in seconds.
    func stop() async throws -> Double {
        let stopTime = Self.now
        try? await videoStream.stopCapture()
        for stream in audioStreams {
            try? await stream.stopCapture()
        }
        let duration = try await finishWriting(stopTime: stopTime)
        if let workingURL {
            defer { try? FileManager.default.removeItem(at: workingURL) }
            try await AudioMixdown.run(source: workingURL, destination: url, fileType: codec.fileType,
                                       plan: mixPlan, names: trackNames,
                                       audioSettings: codec == .prores ? AudioMixdown.pcm24 : AudioMixdown.aac)
        }
        return duration
    }

    private func finishWriting(stopTime: CMTime) async throws -> Double {
        try await withCheckedThrowingContinuation { continuation in
            // On the sample queue: every frame delivered before the stop is already appended.
            queue.async { [self] in
                guard sessionStarted else {
                    writer.cancelWriting()
                    try? FileManager.default.removeItem(at: workingURL ?? url)
                    continuation.resume(throwing: RecordingError.noFrames)
                    return
                }
                // A still screen sends no new frames, so the video ends when Stop was pressed,
                // not at the last change on screen.
                let pausedAtStop = pausedSince.map { CMTimeSubtract(stopTime, $0) } ?? .zero
                let end = CMTimeMaximum(CMTimeSubtract(CMTimeSubtract(stopTime, pausedTotal), pausedAtStop), lastVideoTime)
                writer.endSession(atSourceTime: end)
                video.markAsFinished()
                sourceInputs.forEach { $0.markAsFinished() }
                let duration = CMTimeSubtract(end, firstVideoTime).seconds
                writer.finishWriting { [self] in
                    if writer.status == .completed {
                        continuation.resume(returning: duration)
                    } else {
                        continuation.resume(throwing: writer.error ?? CocoaError(.fileWriteUnknown))
                    }
                }
            }
        }
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard buffer.isValid, writer.status == .writing, pausedSince == nil else { return }
        if type == .screen {
            // Audio-only streams send a tiny picture too.
            guard stream === videoStream, Self.isCompleteFrame(buffer),
                  let buffer = Self.shifted(buffer, back: pausedTotal) else { return }
            let time = buffer.presentationTimeStamp
            if !sessionStarted {
                writer.startSession(atSourceTime: time)
                sessionStarted = true
                firstVideoTime = time
            }
            if video.isReadyForMoreMediaData, video.append(buffer) {
                lastVideoTime = time
            }
        } else if sessionStarted, let input = audioInputs[ObjectIdentifier(stream)], input.isReadyForMoreMediaData,
                  let buffer = Self.shifted(buffer, back: pausedTotal) {
            input.append(buffer)
        }
    }

    /// The buffer with its timestamps moved `back` (itself when there is nothing to move).
    private static func shifted(_ buffer: CMSampleBuffer, back offset: CMTime) -> CMSampleBuffer? {
        guard offset > .zero else { return buffer }
        guard var timing = try? buffer.sampleTimingInfos() else { return nil }
        for index in timing.indices {
            timing[index].presentationTimeStamp = CMTimeSubtract(timing[index].presentationTimeStamp, offset)
            if timing[index].decodeTimeStamp.isValid {
                timing[index].decodeTimeStamp = CMTimeSubtract(timing[index].decodeTimeStamp, offset)
            }
        }
        return try? CMSampleBuffer(copying: buffer, withNewTiming: timing)
    }

    /// ScreenCaptureKit also sends "idle" buffers when nothing changed; only complete ones carry a frame.
    private static func isCompleteFrame(_ buffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw)
        else { return false }
        return status == .complete
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        // A source going quiet (its app quit) doesn't end the recording; the picture does.
        guard stream === videoStream else {
            Log.capture.error("Audio source stopped: \(error.localizedDescription, privacy: .public)")
            return
        }
        Task { @MainActor [onInterrupted] in onInterrupted?(error) }
    }
}
