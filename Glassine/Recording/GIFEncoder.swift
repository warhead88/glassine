import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// Turns a finished recording into a looping GIF, with AVFoundation and ImageIO only.
enum GIFEncoder {
    /// `progress` gets 0…1 on the main actor.
    static func convert(video: URL, to output: URL, fps: Int, maxWidth: Int,
                        progress: @escaping @MainActor (Double) -> Void) async throws {
        let asset = AVURLAsset(url: video)
        let duration = try await asset.load(.duration).seconds
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw RecordingError.noFrames }
        let natural = try await track.load(.naturalSize)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = RecordingMath.gifSize(width: Int(natural.width), height: Int(natural.height), maxWidth: maxWidth)

        let times = RecordingMath.gifFrameTimes(duration: duration, fps: fps)
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString, times.count, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        let delay = 1 / Double(fps)
        let frameProperties = [kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFDelayTime: delay,
            kCGImagePropertyGIFUnclampedDelayTime: delay,
        ]] as CFDictionary

        for (index, time) in times.enumerated() {
            try Task.checkCancellation()
            let (image, _) = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600))
            CGImageDestinationAddImage(destination, image, frameProperties)
            let done = Double(index + 1) / Double(times.count)
            await progress(done)
        }
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
