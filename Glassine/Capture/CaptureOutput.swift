import AppKit
import ImageIO
import UniformTypeIdentifiers

/// A finished capture and the ways to hand it off: clipboard, the save folder,
/// or a file for drag & drop.
@MainActor
final class CapturedImage {
    let image: CGImage
    let scale: CGFloat
    /// e.g. "Glassine 2026-10-21 at 19.53.06", fixed at capture time.
    let baseName: String
    private let png: Data

    private(set) var savedURL: URL?
    private var temporaryURL: URL?

    init(image: CGImage, scale: CGFloat, date: Date = .now) throws {
        self.image = image
        self.scale = scale
        self.png = try Self.pngData(for: image, scale: scale)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        self.baseName = "Glassine \(formatter.string(from: date))"
    }

    /// Size in points, i.e. how big the capture looked on screen.
    var pointSize: NSSize {
        NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
    }

    var nsImage: NSImage { NSImage(cgImage: image, size: pointSize) }

    func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
    }

    /// Saves into the user's save folder once; later calls return the same file.
    @discardableResult
    func save() throws -> URL {
        if let savedURL { return savedURL }
        let url = try write(into: Preferences.saveFolder)
        savedURL = url
        return url
    }

    func save(to url: URL) throws {
        try png.write(to: url, options: .atomic)
        savedURL = url
    }

    /// A file to hand to other apps (drag & drop, open). Uses the saved file if there is one,
    /// otherwise a temporary copy in Caches that is cleared on next launch.
    func shareableFileURL() throws -> URL {
        if let url = savedURL ?? temporaryURL { return url }
        let url = try write(into: AppPaths.temporaryFiles)
        temporaryURL = url
        return url
    }

    private func write(into folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var url = folder.appending(path: "\(baseName).png")
        var index = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appending(path: "\(baseName) (\(index)).png")
            index += 1
        }
        try png.write(to: url, options: .atomic)
        return url
    }

    /// PNG with DPI metadata, so a 2x capture opens at its on-screen size.
    private static func pngData(for image: CGImage, scale: CGFloat) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let dpi = 72 * scale
        let properties = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return data as Data
    }
}

/// Applies the user's "after capture" preferences to a new capture.
@MainActor
enum CaptureOutput {
    static func deliver(_ capture: CapturedImage) throws {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: PrefKey.copyToClipboard) {
            capture.copyToClipboard()
        }
        if defaults.bool(forKey: PrefKey.saveToFile) {
            try capture.save()
        }
        NSSound(named: "Tink")?.play()
    }
}
