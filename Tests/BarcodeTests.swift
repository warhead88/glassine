import CoreGraphics
import CoreImage.CIFilterBuiltins
import Testing
@testable import Glassine

@Suite("QR codes")
struct BarcodeTests {
    typealias B = BarcodeDetector

    @Test func readingOrderRowsThenColumnsWithoutDuplicates() {
        // Vision boxes: bottom-left origin, so a higher midY is nearer the top.
        let codes: [(payload: String, box: CGRect)] = [
            ("bottom", CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)),
            ("top-right", CGRect(x: 0.6, y: 0.7, width: 0.2, height: 0.2)),
            ("top-left", CGRect(x: 0.1, y: 0.72, width: 0.2, height: 0.2)),
            ("top-left", CGRect(x: 0.1, y: 0.72, width: 0.2, height: 0.2)),
        ]
        #expect(B.ordered(codes) == ["top-left", "top-right", "bottom"])
    }

    @Test func linksAreOnlyWebAddresses() {
        #expect(B.link("https://example.com/a?b=1")?.host == "example.com")
        #expect(B.link("  http://example.com  ") != nil)
        #expect(B.link("WIFI:S:Home;T:WPA;P:secret;;") == nil)
        #expect(B.link("mailto:me@example.com") == nil)
        #expect(B.link("just text") == nil)
    }

    @Test func menuTitlesAreShort() {
        #expect(B.menuTitle("https://example.com/glassine") == "example.com/glassine")
        #expect(B.menuTitle(String(repeating: "a", count: 100)).count == 48)
        #expect(B.menuTitle("two\nlines") == "two lines")
    }

    @Test func previewGrowsForTheQRButton() {
        let wide = QuickAccessLayout.thumbnailSize(for: CGSize(width: 1000, height: 500), hasQR: true)
        #expect(wide.height == QuickAccessLayout.minHeightWithQR)
        #expect(QuickAccessLayout.thumbnailSize(for: CGSize(width: 1000, height: 500)).height == 110)
    }

    @Test func findsSeveralCodesInOneCapture() async throws {
        func qr(_ text: String) -> CIImage {
            let filter = CIFilter.qrCodeGenerator()
            filter.message = Data(text.utf8)
            return filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        }
        let a = qr("https://example.com/one"), b = qr("https://example.com/two"), c = qr("plain text")
        let side = a.extent.width
        var canvas = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: side * 2 + 180, height: side * 2 + 180))
        canvas = a.transformed(by: CGAffineTransform(translationX: 60, y: side + 120)).composited(over: canvas)   // top-left
        canvas = b.transformed(by: CGAffineTransform(translationX: side + 120, y: side + 120)).composited(over: canvas) // top-right
        canvas = c.transformed(by: CGAffineTransform(translationX: 60, y: 60)).composited(over: canvas)            // bottom
        let image = try #require(CIContext().createCGImage(canvas, from: canvas.extent))

        #expect(await B.detect(image) == ["https://example.com/one", "https://example.com/two", "plain text"])
    }
}
