import CoreGraphics
import Testing
@testable import Glassine

@Suite("Preview layout")
struct QuickAccessLayoutTests {
    typealias L = QuickAccessLayout

    @Test func wideCaptureFitsTheMaximumWidth() {
        #expect(L.thumbnailSize(for: CGSize(width: 1000, height: 500)) == CGSize(width: 220, height: 110))
    }

    @Test func smallCaptureIsNotUpscaledButGetsRoomForButtons() {
        #expect(L.thumbnailSize(for: CGSize(width: 100, height: 50)) == CGSize(width: 140, height: 90))
    }

    @Test func tallCaptureKeepsTheMinimumWidth() {
        #expect(L.thumbnailSize(for: CGSize(width: 252, height: 491)) == CGSize(width: 140, height: 150))
    }

    @Test func newestPreviewSitsAtTheBottomRight() {
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 950)
        let frames = L.stackFrames(
            sizes: [CGSize(width: 220, height: 110), CGSize(width: 140, height: 150)],
            in: visible, margin: 16, spacing: 12
        )
        #expect(frames == [
            CGRect(x: 1276, y: 178, width: 220, height: 110), // older, above
            CGRect(x: 1356, y: 16, width: 140, height: 150),  // newest, bottom
        ])
    }

    @Test func stackRespectsTheDockOffset() {
        let visible = CGRect(x: 0, y: 70, width: 1512, height: 880) // Dock at the bottom
        let frames = L.stackFrames(sizes: [CGSize(width: 140, height: 90)], in: visible, margin: 16, spacing: 12)
        #expect(frames.first?.minY == 86)
    }
}

@Suite("Pin geometry")
struct PinGeometryTests {
    typealias G = PinGeometry

    @Test func zoomKeepsBothSidesAtLeast40Points() {
        let natural = CGSize(width: 400, height: 200)
        #expect(G.minZoom(natural: natural) == 0.2)
        #expect(G.clampedZoom(0.1, natural: natural) == 0.2)
        #expect(G.clampedZoom(1.5, natural: natural) == 1.5)
        #expect(G.clampedZoom(20, natural: natural) == G.maxZoom)
    }

    @Test func hugeImagesCanZoomOutTo5Percent() {
        #expect(G.minZoom(natural: CGSize(width: 4000, height: 4000)) == 0.05)
    }

    @Test func zoomAroundTheCenter() {
        let frame = CGRect(x: 100, y: 100, width: 200, height: 100)
        #expect(G.zoomedFrame(frame, to: CGSize(width: 400, height: 200), anchor: CGPoint(x: 200, y: 150))
            == CGRect(x: 0, y: 50, width: 400, height: 200))
    }

    @Test func zoomKeepsThePointUnderThePointerInPlace() {
        let frame = CGRect(x: 100, y: 100, width: 200, height: 100)
        let anchor = CGPoint(x: 100, y: 200) // top-left corner in Cocoa coordinates
        let zoomed = G.zoomedFrame(frame, to: CGSize(width: 400, height: 200), anchor: anchor)
        #expect(zoomed == CGRect(x: 100, y: 0, width: 400, height: 200))
        #expect(CGPoint(x: zoomed.minX, y: zoomed.maxY) == anchor)
    }

    private let visible = CGRect(x: 0, y: 0, width: 1512, height: 950)

    @Test func pinAppearsExactlyOverTheCapturedArea() {
        let placement = G.initialPlacement(natural: CGSize(width: 200, height: 100),
                                           source: CGRect(x: 500, y: 500, width: 200, height: 100), visible: visible)
        #expect(placement.zoom == 1)
        #expect(placement.center == CGPoint(x: 600, y: 550))
    }

    @Test func pinNearTheEdgeIsMovedOnScreen() {
        let placement = G.initialPlacement(natural: CGSize(width: 200, height: 100),
                                           source: CGRect(x: 1450, y: 900, width: 200, height: 100), visible: visible)
        #expect(placement.center == CGPoint(x: 1412, y: 900))
    }

    @Test func oversizedPinIsScaledDownAndCentered() {
        let placement = G.initialPlacement(natural: CGSize(width: 3000, height: 1000), source: nil, visible: visible)
        #expect(abs(placement.zoom - 0.4536) < 0.0001)
        #expect(placement.center == CGPoint(x: 756, y: 475))
    }
}
