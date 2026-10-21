import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Glassine

@Suite("File names")
struct FileNamingTests {
    @Test func emptyPrefixFallsBackToGlassine() {
        #expect(FileNaming.sanitizedPrefix(nil) == "Glassine")
        #expect(FileNaming.sanitizedPrefix("   ") == "Glassine")
    }

    @Test func prefixIsTrimmedAndMadeSafeForFinder() {
        #expect(FileNaming.sanitizedPrefix(" My/Shots: A ") == "My-Shots- A")
    }

    @Test func baseNameIsSortableAndHasNoColons() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 19, minute: 53, second: 6)))
        #expect(FileNaming.baseName(prefix: "Glassine", date: date, timeZone: utc) == "Glassine 2026-10-21 at 19.53.06")
    }

    @Test func uniqueNameSkipsExistingFiles() {
        let folder = URL(filePath: "/tmp/shots", directoryHint: .isDirectory)
        let taken: Set<String> = ["Shot.png", "Shot (2).png"]
        let url = FileNaming.uniqueURL(in: folder, baseName: "Shot", fileExtension: "png") { taken.contains($0.lastPathComponent) }
        #expect(url.lastPathComponent == "Shot (3).png")
        let free = FileNaming.uniqueURL(in: folder, baseName: "Shot", fileExtension: "png") { _ in false }
        #expect(free.lastPathComponent == "Shot.png")
    }

    @Test func formatExtensions() {
        #expect(ImageFormat.png.fileExtension == "png")
        #expect(ImageFormat.jpeg.fileExtension == "jpg")
        #expect(ImageFormat.heic.fileExtension == "heic")
    }
}

@Suite("Image encoding")
@MainActor
struct ImageEncodingTests {
    private func makeImage(width: Int, height: Int) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0.5, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    @Test(arguments: [(ImageFormat.png, UTType.png), (.jpeg, .jpeg), (.heic, .heic)])
    func encodesFormatWithRetinaDPI(format: ImageFormat, type: UTType) throws {
        let data = try CapturedImage.encode(try makeImage(width: 40, height: 20), scale: 2, as: format)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == type.identifier)

        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 40)
        // 144 DPI makes a 2x capture open at its on-screen size.
        #expect((properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue == 144)
    }

    @Test func downscalesRetinaCaptureTo1x() throws {
        let scaled = try #require(CapturedImage.downscale(try makeImage(width: 400, height: 200), by: 2))
        #expect(scaled.width == 200)
        #expect(scaled.height == 100)
    }

    @Test func detachedCopyKeepsSizeAndPixels() throws {
        let screen = try makeImage(width: 400, height: 200)
        let crop = try #require(screen.cropping(to: CGRect(x: 10, y: 10, width: 30, height: 20)))
        let copy = try #require(CapturedImage.detached(crop))
        #expect(copy.width == 30)
        #expect(copy.height == 20)
        let pixel = NSBitmapImageRep(cgImage: copy).colorAt(x: 5, y: 5)?.usingColorSpace(.sRGB)
        let original = NSBitmapImageRep(cgImage: screen).colorAt(x: 15, y: 15)?.usingColorSpace(.sRGB)
        #expect(pixel?.hexString == original?.hexString, "copy \(pixel?.hexString ?? "-"), original \(original?.hexString ?? "-")")
    }

    @Test func magnifierHexColor() {
        #expect(NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1).hexString == "#FF8000")
        #expect(NSColor(srgbRed: 0.102, green: 0.102, blue: 0.102, alpha: 1).hexString == "#1A1A1A")
    }
}
