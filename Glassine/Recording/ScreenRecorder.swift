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

/// Streams the screen with ScreenCaptureKit straight into a hardware-encoded MP4: frames arrive
/// as GPU surfaces and go to the media engine without being copied or drawn.
final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    // The writer and inputs are used only on `queue` once capture starts.
    private let queue = DispatchQueue(label: "com.warhead88.glassine.recorder", qos: .userInitiated)
    private var stream: SCStream!
    private let writer: AVAssetWriter
    private let video: AVAssetWriterInput
    private var systemAudio: AVAssetWriterInput?
    private var microphone: AVAssetWriterInput?
    private var sessionStarted = false
    private var firstVideoTime = CMTime.invalid
    private var lastVideoTime = CMTime.invalid

    let url: URL
    let pixelSize: (width: Int, height: Int)
    /// The stream stopped by itself (display gone, sharing stopped from the menu bar).
    var onInterrupted: (@MainActor (Error) -> Void)?

    @MainActor
    static func make(_ target: RecordingTarget, options: RecordingOptions, url: URL) async throws -> ScreenRecorder {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let config = SCStreamConfiguration()
        let filter: SCContentFilter
        let size: (width: Int, height: Int)

        switch target {
        case .area(let screen, let rect):
            guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else {
                throw RecordingError.unavailable
            }
            // Glassine's own windows (the recording controls, previews) stay out of the video.
            let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
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
        config.capturesAudio = options.systemAudio
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        var microphone = false
        if #available(macOS 15.0, *), options.microphone {
            config.captureMicrophone = true
            microphone = true
        }

        let recorder = try ScreenRecorder(url: url, size: size, options: options, microphone: microphone)
        let stream = SCStream(filter: filter, configuration: config, delegate: recorder)
        try stream.addStreamOutput(recorder, type: .screen, sampleHandlerQueue: recorder.queue)
        if options.systemAudio {
            try stream.addStreamOutput(recorder, type: .audio, sampleHandlerQueue: recorder.queue)
        }
        if #available(macOS 15.0, *), microphone {
            try stream.addStreamOutput(recorder, type: .microphone, sampleHandlerQueue: recorder.queue)
        }
        recorder.stream = stream
        return recorder
    }

    private init(url: URL, size: (width: Int, height: Int), options: RecordingOptions, microphone: Bool) throws {
        self.url = url
        self.pixelSize = size
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        let bitrate = RecordingMath.bitrate(width: size.width, height: size.height, fps: options.framesPerSecond,
                                            codec: options.codec, mbps: options.bitrateMbps)
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: bitrate,
            AVVideoExpectedSourceFrameRateKey: options.framesPerSecond,
            AVVideoMaxKeyFrameIntervalKey: options.framesPerSecond * 2,
        ]
        if options.codec == .h264 {
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        }
        video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: options.codec.avCodec,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
            AVVideoCompressionPropertiesKey: compression,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ])
        video.expectsMediaDataInRealTime = true
        writer.add(video)

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 160_000,
        ]
        // System audio and the microphone are separate tracks; players mix them.
        if options.systemAudio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            systemAudio = input
        }
        if microphone {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            self.microphone = input
        }
        super.init()
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }

    func start() async throws {
        try await stream.startCapture()
    }

    /// Stops and finishes the file; returns the recording's length in seconds.
    func stop() async throws -> Double {
        let stopTime = CMClockGetTime(CMClockGetHostTimeClock())
        try? await stream.stopCapture()
        return try await withCheckedThrowingContinuation { continuation in
            // On the sample queue: every frame delivered before the stop is already appended.
            queue.async { [self] in
                guard sessionStarted else {
                    writer.cancelWriting()
                    try? FileManager.default.removeItem(at: url)
                    continuation.resume(throwing: RecordingError.noFrames)
                    return
                }
                // A still screen sends no new frames, so the video ends when Stop was pressed,
                // not at the last change on screen.
                let end = CMTimeMaximum(stopTime, lastVideoTime)
                writer.endSession(atSourceTime: end)
                video.markAsFinished()
                systemAudio?.markAsFinished()
                microphone?.markAsFinished()
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
        guard buffer.isValid, writer.status == .writing else { return }
        switch type {
        case .screen:
            guard Self.isCompleteFrame(buffer) else { return }
            let time = buffer.presentationTimeStamp
            if !sessionStarted {
                writer.startSession(atSourceTime: time)
                sessionStarted = true
                firstVideoTime = time
            }
            if video.isReadyForMoreMediaData, video.append(buffer) {
                lastVideoTime = time
            }
        case .audio:
            append(buffer, to: systemAudio)
        default:
            if #available(macOS 15.0, *), type == .microphone {
                append(buffer, to: microphone)
            }
        }
    }

    private func append(_ buffer: CMSampleBuffer, to input: AVAssetWriterInput?) {
        guard sessionStarted, let input, input.isReadyForMoreMediaData else { return }
        input.append(buffer)
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
        Task { @MainActor [onInterrupted] in onInterrupted?(error) }
    }
}
