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
    /// Format for files on disk; the clipboard always gets lossless PNG.
    let format: ImageFormat
    private let png: Data
    private var encodedFile: Data?

    private(set) var savedURL: URL?
    private var temporaryURL: URL?
    /// Where the captured content was on screen (global Cocoa coordinates), so a pin
    /// can appear exactly over it. Nil for images that didn't come from the screen.
    var sourceFrame: NSRect?

    init(image: CGImage, scale: CGFloat, date: Date = .now) throws {
        if UserDefaults.standard.bool(forKey: PrefKey.saveAtStandardResolution), scale > 1,
           let downscaled = Self.downscale(image, by: scale) {
            self.image = downscaled
            self.scale = 1
        } else {
            self.image = image
            self.scale = scale
        }
        self.format = Preferences.imageFormat
        self.png = try Self.encode(self.image, scale: self.scale, as: .png)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        self.baseName = "\(Preferences.fileNamePrefix) \(formatter.string(from: date))"
    }

    var fileExtension: String {
        switch format {
        case .png: "png"
        case .jpeg: "jpg"
        case .heic: "heic"
        }
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
        try fileData().write(to: url, options: .atomic)
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
        var url = folder.appending(path: "\(baseName).\(fileExtension)")
        var index = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appending(path: "\(baseName) (\(index)).\(fileExtension)")
            index += 1
        }
        try fileData().write(to: url, options: .atomic)
        return url
    }

    private func fileData() throws -> Data {
        if format == .png { return png }
        if let encodedFile { return encodedFile }
        let data = try Self.encode(image, scale: scale, as: format)
        encodedFile = data
        return data
    }

    /// Encodes with DPI metadata, so a 2x capture opens at its on-screen size.
    private static func encode(_ image: CGImage, scale: CGFloat, as format: ImageFormat) throws -> Data {
        let type: UTType = switch format {
        case .png: .png
        case .jpeg: .jpeg
        case .heic: .heic
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let dpi = 72 * scale
        var properties: [CFString: Any] = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi]
        if format != .png {
            properties[kCGImageDestinationLossyCompressionQuality] = 0.9
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return data as Data
    }

    private static func downscale(_ image: CGImage, by scale: CGFloat) -> CGImage? {
        let width = Int((CGFloat(image.width) / scale).rounded())
        let height = Int((CGFloat(image.height) / scale).rounded())
        guard width > 0, height > 0,
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
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
        if defaults.bool(forKey: PrefKey.playSound) {
            NSSound(named: "Tink")?.play()
        }
    }
}
