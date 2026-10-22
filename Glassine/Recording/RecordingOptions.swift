import AVFoundation
import CoreGraphics

/// What a recording is saved as. Both are recorded the same way (hardware-encoded video);
/// a GIF is made from the video when recording stops.
enum RecordingFormat: String, Hashable {
    case video, gif
}

enum VideoCodec: String, CaseIterable, Identifiable {
    /// Plays everywhere (browsers, messengers, older devices).
    case h264
    /// About half the size at the same quality; every Apple device since 2017 plays it.
    case hevc
    /// ProRes 422: nearly lossless and quick to edit (Final Cut, DaVinci, Premiere); files are 10–20× larger.
    case prores

    var id: Self { self }

    var title: String {
        switch self {
        case .h264: "H.264"
        case .hevc: "HEVC"
        case .prores: "ProRes"
        }
    }

    var avCodec: AVVideoCodecType {
        switch self {
        case .h264: .h264
        case .hevc: .hevc
        case .prores: .proRes422
        }
    }

    /// ProRes keeps its own quality and lives in QuickTime movies; the others go in MP4.
    var hasBitrate: Bool { self != .prores }
    var fileType: AVFileType { self == .prores ? .mov : .mp4 }
    var fileExtension: String { self == .prores ? "mov" : "mp4" }
}

/// Everything a recording is made with, read from preferences when it starts.
struct RecordingOptions {
    var format = RecordingFormat.video
    var codec = VideoCodec.h264
    var framesPerSecond = 60
    /// Average video bitrate in Mbit/s; 0 picks one from the size and frame rate.
    var bitrateMbps = 0
    /// Record at the screen's pixel density; off records at 1 pixel per point (smaller files).
    var retina = true
    var showsCursor = true
    /// Video only; empty records no sound.
    var audioTracks: [AudioTrack] = []
    var gifFramesPerSecond = 15
    /// Widest GIF in pixels; 0 keeps the recording's width.
    var gifMaxWidth = 800

    /// The options last used; the recording controls change and save them.
    /// What the recording is saved as: "gif", "mov" (ProRes) or "mp4".
    var fileExtension: String { format == .gif ? "gif" : codec.fileExtension }

    /// The audio tracks actually recorded: none for a GIF.
    var recordedTracks: [AudioTrack] { format == .video ? audioTracks.filter { !$0.sources.isEmpty } : [] }

    static var current: RecordingOptions {
        let defaults = UserDefaults.standard
        var options = RecordingOptions()
        options.format = RecordingFormat(rawValue: defaults.string(forKey: PrefKey.recordingFormat) ?? "") ?? .video
        options.codec = VideoCodec(rawValue: defaults.string(forKey: PrefKey.recordingCodec) ?? "") ?? .h264
        options.framesPerSecond = defaults.integer(forKey: PrefKey.recordingFPS)
        options.bitrateMbps = defaults.integer(forKey: PrefKey.recordingBitrate)
        options.retina = defaults.bool(forKey: PrefKey.recordingRetina)
        options.showsCursor = defaults.bool(forKey: PrefKey.recordingCursor)
        if let data = defaults.data(forKey: PrefKey.recordingAudioTracks),
           let tracks = try? JSONDecoder().decode([AudioTrack].self, from: data) {
            options.audioTracks = tracks
        } else {
            // Before tracks there were two switches; keep what they recorded, in one track.
            var sources: [AudioSource] = []
            if defaults.bool(forKey: PrefKey.recordingSystemAudio) { sources.append(.system) }
            if defaults.bool(forKey: PrefKey.recordingMicrophone) { sources.append(.microphone(id: nil, name: "Microphone")) }
            options.audioTracks = sources.isEmpty ? [] : [AudioTrack(sources: sources)]
        }
        options.gifFramesPerSecond = defaults.integer(forKey: PrefKey.gifFPS)
        options.gifMaxWidth = defaults.integer(forKey: PrefKey.gifMaxWidth)
        return options
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(format.rawValue, forKey: PrefKey.recordingFormat)
        defaults.set(codec.rawValue, forKey: PrefKey.recordingCodec)
        defaults.set(framesPerSecond, forKey: PrefKey.recordingFPS)
        defaults.set(bitrateMbps, forKey: PrefKey.recordingBitrate)
        defaults.set(retina, forKey: PrefKey.recordingRetina)
        defaults.set(showsCursor, forKey: PrefKey.recordingCursor)
        defaults.set(try? JSONEncoder().encode(audioTracks), forKey: PrefKey.recordingAudioTracks)
        defaults.removeObject(forKey: PrefKey.recordingSystemAudio)
        defaults.removeObject(forKey: PrefKey.recordingMicrophone)
        defaults.set(gifFramesPerSecond, forKey: PrefKey.gifFPS)
        defaults.set(gifMaxWidth, forKey: PrefKey.gifMaxWidth)
    }
}

enum RecordingMath {
    /// Encoder size in pixels for an area in points: video encoders need even dimensions.
    static func pixelSize(points: CGSize, scale: CGFloat) -> (width: Int, height: Int) {
        func even(_ value: CGFloat) -> Int { max(2, Int((value * scale).rounded(.down)) & ~1) }
        return (even(points.width), even(points.height))
    }

    /// Average bitrate in bits per second. Auto gives screen content about 0.1 bit per pixel per
    /// frame for H.264 (≈12 Mbit/s for 1080p60) and 30% less for HEVC, within 2…80 Mbit/s.
    static func bitrate(width: Int, height: Int, fps: Int, codec: VideoCodec, mbps: Int) -> Int {
        if mbps > 0 { return mbps * 1_000_000 }
        let bitsPerPixel = codec == .h264 ? 0.1 : 0.07
        let auto = Double(width * height * fps) * bitsPerPixel
        return Int(min(max(auto, 2_000_000), 80_000_000))
    }

    /// GIF frame size: the recording scaled down to `maxWidth` (0 = no limit), never up.
    static func gifSize(width: Int, height: Int, maxWidth: Int) -> CGSize {
        guard maxWidth > 0, width > maxWidth else { return CGSize(width: width, height: height) }
        let scale = Double(maxWidth) / Double(width)
        return CGSize(width: maxWidth, height: max(1, Int((Double(height) * scale).rounded())))
    }

    /// Times of the GIF's frames: every 1/fps seconds, at least one frame.
    static func gifFrameTimes(duration: Double, fps: Int) -> [Double] {
        let count = max(1, Int((duration * Double(fps)).rounded(.down)))
        return (0..<count).map { Double($0) / Double(fps) }
    }

    /// The file in a few words: "MP4 · 2 tracks", "MOV · ProRes", "GIF".
    static func summary(format: RecordingFormat, codec: VideoCodec, tracks: Int) -> String {
        guard format == .video else { return "GIF" }
        var parts = [codec.fileExtension.uppercased()]
        if codec == .prores { parts.append("ProRes") }
        if tracks > 0 { parts.append(tracks == 1 ? "1 track" : "\(tracks) tracks") }
        return parts.joined(separator: " · ")
    }

    /// "0:07", "1:05:09".
    static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let (h, m, s) = (total / 3600, total / 60 % 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
