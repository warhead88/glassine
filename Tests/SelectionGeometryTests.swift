import CoreGraphics
import Testing
@testable import Glassine

@Suite("Selection geometry")
struct SelectionGeometryTests {
    typealias G = SelectionGeometry

    // MARK: Creating a selection

    @Test func dragDownRight() {
        #expect(G.rect(anchor: CGPoint(x: 10, y: 10), point: CGPoint(x: 110, y: 60), square: false, fromCenter: false)
            == CGRect(x: 10, y: 10, width: 100, height: 50))
    }

    @Test func dragUpLeftGivesTheSameRect() {
        #expect(G.rect(anchor: CGPoint(x: 110, y: 60), point: CGPoint(x: 10, y: 10), square: false, fromCenter: false)
            == CGRect(x: 10, y: 10, width: 100, height: 50))
    }

    @Test func shiftMakesASquareTowardsThePointer() {
        #expect(G.rect(anchor: .zero, point: CGPoint(x: 100, y: 40), square: true, fromCenter: false)
            == CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(G.rect(anchor: .zero, point: CGPoint(x: -30, y: 80), square: true, fromCenter: false)
            == CGRect(x: -80, y: 0, width: 80, height: 80))
    }

    @Test func optionGrowsFromTheCenter() {
        #expect(G.rect(anchor: CGPoint(x: 50, y: 50), point: CGPoint(x: 70, y: 60), square: false, fromCenter: true)
            == CGRect(x: 30, y: 40, width: 40, height: 20))
    }

    @Test func shiftAndOptionTogether() {
        #expect(G.rect(anchor: CGPoint(x: 50, y: 50), point: CGPoint(x: 60, y: 90), square: true, fromCenter: true)
            == CGRect(x: 10, y: 10, width: 80, height: 80))
    }

    // MARK: Adjusting with handles

    private let rect = CGRect(x: 10, y: 10, width: 100, height: 50)

    @Test func rightHandleMovesOnlyTheRightEdge() {
        #expect(G.resized(rect, handle: .right, dx: 20, dy: 99) == CGRect(x: 10, y: 10, width: 120, height: 50))
    }

    @Test func cornerHandleMovesTwoEdges() {
        #expect(G.resized(rect, handle: .topLeft, dx: 5, dy: 5) == CGRect(x: 15, y: 15, width: 95, height: 45))
    }

    @Test func draggingPastTheOppositeEdgeFlips() {
        #expect(G.resized(rect, handle: .left, dx: 150, dy: 0) == CGRect(x: 110, y: 10, width: 50, height: 50))
        #expect(G.resized(rect, handle: .bottom, dx: 0, dy: -70) == CGRect(x: 10, y: -10, width: 100, height: 20))
    }

    @Test func handleHitTesting() {
        let square = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(G.handle(at: CGPoint(x: 101, y: 49), of: square) == .right)
        #expect(G.handle(at: CGPoint(x: 3, y: 98), of: square) == .bottomLeft)
        #expect(G.handle(at: CGPoint(x: 50, y: 50), of: square) == nil)
    }

    // MARK: Staying on screen

    @Test func movedSelectionStaysInsideTheScreen() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        #expect(G.fitted(CGRect(x: 950, y: -20, width: 100, height: 50), in: bounds)
            == CGRect(x: 900, y: 0, width: 100, height: 50))
    }

    @Test func pointerIsClampedToTheScreen() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        #expect(G.clamped(CGPoint(x: -5, y: 900), to: bounds) == CGPoint(x: 0, y: 800))
    }

    // MARK: Points to pixels

    private let retinaView = CGSize(width: 1512, height: 982)
    private let retinaImage = CGSize(width: 3024, height: 1964)

    @Test func pixelRectCoversEveryTouchedPixelOnRetina() {
        let pixels = G.pixelRect(CGRect(x: 10.25, y: 20.5, width: 100.5, height: 50), viewSize: retinaView, imageSize: retinaImage)
        #expect(pixels == CGRect(x: 20, y: 41, width: 202, height: 100))
    }

    @Test func pixelRectIsIdentityAt1x() {
        let rect = CGRect(x: 10, y: 20, width: 30, height: 40)
        #expect(G.pixelRect(rect, viewSize: retinaView, imageSize: retinaView) == rect)
    }

    @Test func pixelUnderPointerIsClampedToTheImage() {
        #expect(G.pixelPoint(CGPoint(x: 755.9, y: 0.2), viewSize: retinaView, imageSize: retinaImage) == CGPoint(x: 1511, y: 0))
        #expect(G.pixelPoint(CGPoint(x: 2000, y: -5), viewSize: retinaView, imageSize: retinaImage) == CGPoint(x: 3023, y: 0))
    }
}
