import AVFoundation
import AppKit

/// A finished recording: a video or GIF file, in the save folder or (with saving off) in Caches
/// until the user saves it.
@MainActor
final class CapturedRecording {
    private(set) var url: URL
    let format: RecordingFormat
    let duration: Double
    /// The first frame, for the preview.
    let thumbnail: CGImage?
    /// Size in points, as it looked on screen.
    let pointSize: CGSize

    init(url: URL, format: RecordingFormat, duration: Double, thumbnail: CGImage?, pointSize: CGSize) {
        self.url = url
        self.format = format
        self.duration = duration
        self.thumbnail = thumbnail
        self.pointSize = pointSize
    }

    var isSaved: Bool { !url.path.hasPrefix(AppPaths.temporaryFiles.path) }

    /// The file itself: pastes as a video or GIF in chats and mail, as a file in Finder.
    func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
    }

    /// Moves the file from Caches into the save folder; returns where it is.
    @discardableResult
    func save() throws -> URL {
        guard !isSaved else { return url }
        let folder = Preferences.saveFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = FileNaming.uniqueURL(
            in: folder, baseName: url.deletingPathExtension().lastPathComponent, fileExtension: url.pathExtension
        ) { FileManager.default.fileExists(atPath: $0.path) }
        try FileManager.default.moveItem(at: url, to: destination)
        url = destination
        return destination
    }

    /// The first frame of a video, at most `maxPixels` wide or tall.
    static func firstFrame(of video: URL, maxPixels: CGFloat = 640) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.maximumSize = CGSize(width: maxPixels, height: maxPixels)
        return try? await generator.image(at: .zero).image
    }
}
