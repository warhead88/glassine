import AppKit
import CoreImage.CIFilterBuiltins
import Testing
@testable import Glassine

@Suite("Color formats")
struct ColorFormatTests {
    @Test func formatsOrange() {
        #expect(ColorFormat.hex.string(red: 1, green: 0.5, blue: 0) == "#FF8000")
        #expect(ColorFormat.rgb.string(red: 1, green: 0.5, blue: 0) == "rgb(255, 128, 0)")
        #expect(ColorFormat.hsl.string(red: 1, green: 0.5, blue: 0) == "hsl(30, 100%, 50%)")
    }

    @Test func grayHasNoHueOrSaturation() {
        #expect(ColorFormat.hsl.string(red: 0.5, green: 0.5, blue: 0.5) == "hsl(0, 0%, 50%)")
    }

    @Test(arguments: [
        (CGFloat(0), CGFloat(1), CGFloat(0), "hsl(120, 100%, 50%)"),
        (0, 0, 1, "hsl(240, 100%, 50%)"),
        (1, 0, 1, "hsl(300, 100%, 50%)"),
    ])
    func primaryHues(red: CGFloat, green: CGFloat, blue: CGFloat, expected: String) {
        #expect(ColorFormat.hsl.string(red: red, green: green, blue: blue) == expected)
    }
}

@Suite("Ruler")
struct MeasurementTests {
    @Test func horizontalOnRetina() {
        #expect(Measurement.describe(from: .zero, to: CGPoint(x: 100, y: 0), scale: 2) == "200 px · 100 pt")
    }

    @Test func diagonalShowsOffsets() {
        #expect(Measurement.describe(from: .zero, to: CGPoint(x: 30, y: 40), scale: 1) == "50 px   ↔ 30  ↕ 40")
    }

    @Test func halfPointsOnRetina() {
        #expect(Measurement.describe(from: .zero, to: CGPoint(x: 0, y: 10.5), scale: 2) == "21 px · 10.5 pt")
    }
}

@Suite("Text layout")
struct TextLayoutTests {
    typealias F = TextLayout.Fragment

    @Test func linesTopToBottomAndWordsLeftToRight() {
        let fragments = [
            F(text: "world", box: CGRect(x: 0.5, y: 0.1, width: 0.3, height: 0.1)),
            F(text: "second line", box: CGRect(x: 0.1, y: 0.4, width: 0.6, height: 0.1)),
            F(text: "Hello", box: CGRect(x: 0.1, y: 0.11, width: 0.3, height: 0.1)),
        ]
        #expect(TextLayout.join(fragments) == "Hello world\nsecond line")
    }

    @Test func emptyInputGivesEmptyText() {
        #expect(TextLayout.join([]) == "")
    }
}

@Suite("Recognition (Vision, on device)")
struct TextRecognizerTests {
    private func render(_ lines: [String]) throws -> CGImage {
        let size = CGSize(width: 900, height: 120 * lines.count + 40)
        let context = try #require(CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        for (index, line) in lines.enumerated() {
            NSAttributedString(string: line, attributes: [.font: NSFont.systemFont(ofSize: 64), .foregroundColor: NSColor.black])
                .draw(at: CGPoint(x: 30, y: size.height - CGFloat(index + 1) * 120))
        }
        NSGraphicsContext.restoreGraphicsState()
        return try #require(context.makeImage())
    }

    @Test func readsEnglishAndRussianInOrder() async throws {
        let result = try await TextRecognizer.recognize(try render(["Hello Glassine", "Привет мир"]))
        let lines = result.text.split(separator: "\n").map(String.init)
        #expect(lines == ["Hello Glassine", "Привет мир"])
        #expect(result.codes.isEmpty)
    }

    @Test func readsQRCode() async throws {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data("https://example.com/glassine".utf8)
        let output = try #require(filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)))
        let padded = output.composited(over: CIImage(color: .white).cropped(to: output.extent.insetBy(dx: -60, dy: -60)))
        let image = try #require(CIContext().createCGImage(padded, from: padded.extent))

        let result = try await TextRecognizer.recognize(image)
        #expect(result.codes == ["https://example.com/glassine"])
    }

    @Test func blankImageHasNothing() async throws {
        let result = try await TextRecognizer.recognize(try render([]))
        #expect(result.isEmpty)
    }
}
