import CoreGraphics
import Testing
@testable import Glassine

/// Values reported by a 14" MacBook Pro: 1512×982 pt, notch 185 pt wide and 32 pt tall.
@Suite("Area frame")
struct ScreenFrameTests {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let left = CGRect(x: 0, y: 950, width: 663.5, height: 32)
    let right = CGRect(x: 848.5, y: 950, width: 663.5, height: 32)

    @Test func notchFromTheAreasBesideIt() {
        #expect(ScreenFrame.notchRect(screenFrame: screen, topInset: 32, leftArea: left, rightArea: right)
            == CGRect(x: 663.5, y: 0, width: 185, height: 32))
    }

    @Test func noNotchWithoutTopInset() {
        #expect(ScreenFrame.notchRect(screenFrame: screen, topInset: 0, leftArea: left, rightArea: right) == nil)
        #expect(ScreenFrame.notchRect(screenFrame: screen, topInset: 32, leftArea: nil, rightArea: nil) == nil)
    }

    @Test func notchOnASecondScreenIsInItsLocalCoordinates() {
        let external = CGRect(x: 1512, y: 0, width: 1512, height: 982)
        let rect = ScreenFrame.notchRect(screenFrame: external, topInset: 32,
                                         leftArea: left.offsetBy(dx: 1512, dy: 0), rightArea: right.offsetBy(dx: 1512, dy: 0))
        #expect(rect?.minX == 663.5)
    }

    @Test func frameDipsUnderTheNotch() throws {
        let notch = CGRect(x: 663.5, y: 0, width: 185, height: 32)
        let path = ScreenFrame.path(in: screen, inset: 1.5, notch: notch)
        #expect(!path.contains(CGPoint(x: notch.midX, y: 10)))   // the notch itself is outside
        #expect(path.contains(CGPoint(x: notch.midX, y: 40)))    // just below it is inside
        #expect(path.contains(CGPoint(x: 300, y: 10)))           // the top strip beside it is inside
        #expect(path.boundingBox == screen.insetBy(dx: 1.5, dy: 1.5))
    }

    @Test func straightFrameIgnoresTheNotch() {
        let path = ScreenFrame.path(in: screen, inset: 1.5, notch: nil)
        #expect(path.contains(CGPoint(x: 756, y: 10)))
    }
}
