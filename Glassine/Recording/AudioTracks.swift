import AppKit
import AVFoundation

/// Something to record sound from.
enum AudioSource: Hashable, Codable {
    /// Everything the Mac plays, except Glassine.
    case system
    /// A microphone; `id` nil is the default one.
    case microphone(id: String?, name: String)
    /// One app's sound only.
    case app(bundleID: String, name: String)

    var title: String {
        switch self {
        case .system: "System audio"
        case .microphone(_, let name): name
        case .app(_, let name): name
        }
    }

    var symbol: String {
        switch self {
        case .system: "speaker.wave.2.fill"
        case .microphone: "mic.fill"
        case .app: "app.fill"
        }
    }

    var isMicrophone: Bool {
        if case .microphone = self { true } else { false }
    }
}

/// One audio track of the recording; its sources are mixed together. Tracks stay separate in the
/// file, so an editor can mute or level them on their own (e.g. voice apart from the app).
struct AudioTrack: Hashable, Codable, Identifiable {
    var id = UUID()
    var sources: [AudioSource] = []
}

enum AudioTrackPlan {
    /// Every source to capture, once each, in track order.
    static func sources(of tracks: [AudioTrack]) -> [AudioSource] {
        var seen = Set<AudioSource>()
        return tracks.flatMap(\.sources).filter { seen.insert($0).inserted }
    }

    /// For each track that has sources, the indices into `sources(of:)` to mix into it.
    static func mix(_ tracks: [AudioTrack]) -> [[Int]] {
        let all = sources(of: tracks)
        return tracks.compactMap { track in
            let indices = track.sources.compactMap { all.firstIndex(of: $0) }
            return indices.isEmpty ? nil : indices
        }
    }

    /// Sources that can still be added: each source belongs to one track.
    static func available(_ candidates: [AudioSource], in tracks: [AudioTrack]) -> [AudioSource] {
        let used = Set(tracks.flatMap(\.sources))
        return candidates.filter { !used.contains($0) }
    }

    /// App sources whose app isn't among `running` (bundle IDs): those can't be recorded now.
    static func missingApps(in tracks: [AudioTrack], running: Set<String>) -> [AudioSource] {
        sources(of: tracks).filter { source in
            if case .app(let id, _) = source { !running.contains(id) } else { false }
        }
    }

    /// The tracks without the given sources (a microphone that isn't allowed, an app that quit).
    static func removing(_ unavailable: (AudioSource) -> Bool, from tracks: [AudioTrack]) -> [AudioTrack] {
        tracks.map { track in
            var track = track
            track.sources.removeAll(where: unavailable)
            return track
        }
    }

    /// "Track 1", or the sources when they're few: "System audio + MacBook Pro Microphone".
    static func name(of track: AudioTrack, number: Int) -> String {
        track.sources.isEmpty || track.sources.count > 2
            ? "Track \(number)"
            : track.sources.map(\.title).joined(separator: " + ")
    }
}

@MainActor
enum AudioSourceCatalog {
    /// Microphones and other audio inputs connected now.
    static var microphones: [AudioSource] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
            .devices.map { .microphone(id: $0.uniqueID, name: $0.localizedName) }
    }

    /// An app source's own icon; nil for the others or an app that isn't installed.
    static func icon(for source: AudioSource) -> NSImage? {
        guard case .app(let bundleID, _) = source,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// Apps with a Dock icon that are running now, by name.
    static var apps: [(source: AudioSource, icon: NSImage?)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            .compactMap { app in
                guard let id = app.bundleIdentifier, let name = app.localizedName else { return nil }
                return (AudioSource.app(bundleID: id, name: name), app.icon)
            }
            .sorted { $0.source.title.localizedStandardCompare($1.source.title) == .orderedAscending }
    }
}
