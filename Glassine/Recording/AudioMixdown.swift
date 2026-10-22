import AVFoundation

/// Turns the working file — video plus one uncompressed track per sound source — into the
/// recording: the video copied as it is, and each of the user's tracks mixed from its sources.
enum AudioMixdown {
    /// How sources are kept while recording, and how the mixer hands them over.
    static var pcm: [String: Any] { [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 48_000,
        AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ] }
    /// Tracks in an MP4.
    static var aac: [String: Any] { [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 48_000,
        AVNumberOfChannelsKey: 2,
        AVEncoderBitRateKey: 192_000,
    ] }
    /// Tracks next to ProRes: uncompressed, as editors expect.
    static var pcm24: [String: Any] { [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 48_000,
        AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: 24,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ] }

    /// `plan[i]` lists the source tracks (by order in the working file) mixed into track i.
    static func run(source: URL, destination: URL, fileType: AVFileType, plan: [[Int]], names: [String],
                    audioSettings: [String: Any]) async throws {
        let asset = AVURLAsset(url: source)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else { throw RecordingError.noFrames }
        let sourceTracks = try await asset.loadTracks(withMediaType: .audio)
        let hint = try await videoTrack.load(.formatDescriptions).first

        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: destination, fileType: fileType)
        var pumps: [Pump] = []

        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil) // as encoded
        videoOutput.alwaysCopiesSampleData = false
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: hint)
        reader.add(videoOutput)
        writer.add(videoInput)
        pumps.append(Pump(output: videoOutput, input: videoInput))

        for (index, sources) in plan.enumerated() {
            let tracks = sources.filter { $0 < sourceTracks.count }.map { sourceTracks[$0] }
            guard !tracks.isEmpty else { continue }
            let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: pcm)
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            if fileType == .mov, index < names.count {
                let name = AVMutableMetadataItem()
                name.identifier = .quickTimeUserDataTrackName
                name.value = names[index] as NSString
                input.metadata = [name]
            }
            reader.add(output)
            writer.add(input)
            pumps.append(Pump(output: output, input: input))
        }

        guard reader.startReading() else { throw reader.error ?? CocoaError(.fileReadUnknown) }
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)

        await withTaskGroup(of: Void.self) { group in
            for pump in pumps {
                group.addTask { await pump.run() }
            }
        }
        if reader.status == .failed {
            writer.cancelWriting()
            throw reader.error ?? CocoaError(.fileReadUnknown)
        }
        await writer.finishWriting()
        if writer.status != .completed {
            throw writer.error ?? CocoaError(.fileWriteUnknown)
        }
    }

    /// Copies one reader output into one writer input as fast as the writer takes it.
    private struct Pump: @unchecked Sendable {
        let output: AVAssetReaderOutput
        let input: AVAssetWriterInput
        let queue = DispatchQueue(label: "com.warhead88.glassine.mixdown")

        func run() async {
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                input.requestMediaDataWhenReady(on: queue) {
                    while input.isReadyForMoreMediaData {
                        guard let buffer = output.copyNextSampleBuffer() else {
                            input.markAsFinished()
                            done.resume()
                            return
                        }
                        input.append(buffer)
                    }
                }
            }
        }
    }
}
