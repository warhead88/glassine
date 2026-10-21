import CoreGraphics
import Testing
@testable import Glassine

/// Two displays: a 1512×982 primary, and a 1920×1080 one to its right, placed 200 pt higher.
@Suite("Screen coordinates")
struct ScreenGeometryTests {
    typealias G = ScreenGeometry

    let primary = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let secondary = CGRect(x: 1512, y: 200, width: 1920, height: 1080)
    var primaryHeight: CGFloat { primary.height }

    @Test func primaryScreenLocalCoordinatesMatchGlobalTopLeft() {
        let window = CGRect(x: 100, y: 33, width: 500, height: 400)
        #expect(G.localFlipped(fromGlobalTopLeft: window, screenFrame: primary, primaryHeight: primaryHeight) == window)
    }

    @Test func windowOnASecondScreenAboveThePrimary() {
        // The secondary screen's top edge is 298 pt above the primary's in top-left coordinates.
        let window = CGRect(x: 1600, y: -200, width: 300, height: 200)
        #expect(G.localFlipped(fromGlobalTopLeft: window, screenFrame: secondary, primaryHeight: primaryHeight)
            == CGRect(x: 88, y: 98, width: 300, height: 200))
    }

    @Test func overlaySelectionToCocoaFrame() {
        #expect(G.globalCocoa(fromLocalFlipped: CGRect(x: 100, y: 33, width: 500, height: 400), screenFrame: primary)
            == CGRect(x: 100, y: 549, width: 500, height: 400))
    }

    @Test func allThreeSystemsAgreeOnSecondScreen() {
        let topLeft = CGRect(x: 1600, y: -200, width: 300, height: 200)
        let local = G.localFlipped(fromGlobalTopLeft: topLeft, screenFrame: secondary, primaryHeight: primaryHeight)
        let viaLocal = G.globalCocoa(fromLocalFlipped: local, screenFrame: secondary)
        let direct = G.globalCocoa(fromGlobalTopLeft: topLeft, primaryHeight: primaryHeight)
        #expect(viaLocal == direct)
        #expect(direct == CGRect(x: 1600, y: 982, width: 300, height: 200))
    }
}
