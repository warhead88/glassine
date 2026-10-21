import AppKit
import Testing
@testable import Glassine

@Suite("Annotation geometry")
struct AnnotationGeometryTests {
    typealias G = AnnotationGeometry

    @Test func arrowHeadEndsAtTheTipAndShaftStopsAtItsBase() {
        let parts = G.arrowParts(from: .zero, to: CGPoint(x: 100, y: 0), lineWidth: 4)
        #expect(parts.head[0] == CGPoint(x: 100, y: 0))
        #expect(parts.shaftEnd == CGPoint(x: 84, y: 0)) // head length = 4 × width = 16
        #expect(parts.head[1].x == 84 && parts.head[2].x == 84)
        #expect(abs(parts.head[1].y + parts.head[2].y) < 0.0001) // symmetric around the shaft
    }

    @Test func shortArrowHeadNeverOvershootsTheStart() {
        let parts = G.arrowParts(from: .zero, to: CGPoint(x: 5, y: 0), lineWidth: 8)
        #expect(parts.shaftEnd == .zero)
    }

    @Test func shiftSnapsTo45Degrees() {
        let snapped = G.snapped(CGPoint(x: 100, y: 10), from: .zero)
        #expect(abs(snapped.y) < 0.0001)
        let diagonal = G.snapped(CGPoint(x: 100, y: 90), from: .zero)
        #expect(abs(diagonal.x - diagonal.y) < 0.0001)
    }

    @Test func distanceToSegment() {
        #expect(G.distance(from: CGPoint(x: 50, y: 5), toSegment: .zero, CGPoint(x: 100, y: 0)) == 5)
        #expect(G.distance(from: CGPoint(x: 110, y: 0), toSegment: .zero, CGPoint(x: 100, y: 0)) == 10)
    }

    @Test func hitTestingShapes() {
        let arrow = Annotation(shape: .arrow(from: .zero, to: CGPoint(x: 100, y: 0)), color: RGBA.palette[0], size: .medium)
        #expect(G.hits(arrow, at: CGPoint(x: 50, y: 4), textBounds: { _ in .zero }))
        #expect(!G.hits(arrow, at: CGPoint(x: 50, y: 30), textBounds: { _ in .zero }))

        let step = Annotation(shape: .step(center: CGPoint(x: 10, y: 10)), color: RGBA.palette[0], size: .medium)
        #expect(G.hits(step, at: CGPoint(x: 20, y: 10), textBounds: { _ in .zero }))
        #expect(!G.hits(step, at: CGPoint(x: 40, y: 10), textBounds: { _ in .zero }))
    }

    @Test func stepsAreNumberedInOrderSkippingOtherShapes() {
        let a = Annotation(shape: .step(center: .zero), color: RGBA.palette[0], size: .small)
        let line = Annotation(shape: .line(from: .zero, to: CGPoint(x: 1, y: 1)), color: RGBA.palette[0], size: .small)
        let b = Annotation(shape: .step(center: .zero), color: RGBA.palette[0], size: .small)
        let numbers = G.stepNumbers([a, line, b])
        #expect(numbers[a.id] == 1)
        #expect(numbers[b.id] == 2)
        #expect(numbers[line.id] == nil)
    }

    @Test func movingKeepsShapeAndIdentity() {
        let rect = Annotation(shape: .rectangle(CGRect(x: 10, y: 10, width: 20, height: 20)), color: RGBA.palette[0], size: .small)
        let moved = rect.moved(by: CGVector(dx: 5, dy: -5))
        #expect(moved.id == rect.id)
        #expect(moved.shape == .rectangle(CGRect(x: 15, y: 5, width: 20, height: 20)))
    }

    @Test func lightColorsGetDarkStepNumbers() {
        #expect(RGBA.palette[2].isLight)  // yellow
        #expect(RGBA.palette[5].isLight)  // white
        #expect(!RGBA.palette[0].isLight) // red
    }
}

@Suite("Editor model")
@MainActor
struct EditorModelTests {
    /// 200×100 pt capture at 2× (400×200 px), solid gray.
    private func makeModel() throws -> EditorModel {
        let context = try #require(CGContext(
            data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
        let capture = try CapturedImage(image: try #require(context.makeImage()), scale: 2)
        capture.sourceFrame = CGRect(x: 100, y: 300, width: 200, height: 100)
        return EditorModel(capture: capture)
    }

    /// Tests have no event loop, so close an undo group per user action like AppKit does per event.
    private func action(_ model: EditorModel, _ body: () -> Void) {
        model.undoManager.groupsByEvent = false
        model.undoManager.beginUndoGrouping()
        body()
        model.undoManager.endUndoGrouping()
    }

    private func redact(_ rect: CGRect) -> Annotation {
        Annotation(shape: .redact(rect), color: RGBA(red: 0, green: 0, blue: 0), size: .medium)
    }

    @Test func undoAndRedoAnAnnotation() throws {
        let model = try makeModel()
        action(model) { model.add(redact(CGRect(x: 0, y: 0, width: 10, height: 10))) }
        #expect(model.annotations.count == 1)
        model.undoManager.undo()
        #expect(model.annotations.isEmpty)
        model.undoManager.redo()
        #expect(model.annotations.count == 1)
    }

    @Test func dragMoveIsOneUndoStep() throws {
        let model = try makeModel()
        let original = redact(CGRect(x: 0, y: 0, width: 10, height: 10))
        action(model) { model.add(original) }
        action(model) {
            for dx in 1...5 { model.previewMove(original.moved(by: CGVector(dx: CGFloat(dx), dy: 0))) }
            model.finishMove(from: original)
        }
        #expect(model.annotations.first?.shape == .redact(CGRect(x: 5, y: 0, width: 10, height: 10)))
        model.undoManager.undo()
        #expect(model.annotations.first == original)
    }

    @Test func cropIsClippedAndCoveringEverythingMeansNoCrop() throws {
        let model = try makeModel()
        model.setCrop(CGRect(x: 150, y: -20, width: 100, height: 70))
        #expect(model.crop == CGRect(x: 150, y: 0, width: 50, height: 50))
        model.setCrop(CGRect(x: -10, y: -10, width: 500, height: 500))
        #expect(model.crop == nil)
    }

    @Test func exportHasFullResolutionAndAppliesCrop() throws {
        let model = try makeModel()
        let full = try #require(model.renderedImage())
        #expect(full.width == 400 && full.height == 200)

        model.setCrop(CGRect(x: 50, y: 25, width: 100, height: 50))
        let cropped = try #require(model.renderedImage())
        #expect(cropped.width == 200 && cropped.height == 100)
    }

    @Test func exportDrawsAnnotationsWhereTheyAre() throws {
        let model = try makeModel()
        model.add(redact(CGRect(x: 0, y: 0, width: 50, height: 50))) // top-left quarter-ish
        let image = try #require(model.renderedImage())
        let rep = NSBitmapImageRep(cgImage: image)
        let inside = try #require(rep.colorAt(x: 20, y: 20)?.usingColorSpace(.sRGB))   // pixels, top-left origin
        let outside = try #require(rep.colorAt(x: 300, y: 150)?.usingColorSpace(.sRGB))
        let source = try #require(NSBitmapImageRep(cgImage: model.capture.image).colorAt(x: 300, y: 150)?.usingColorSpace(.sRGB))
        #expect(inside.brightnessComponent < 0.05)
        #expect(abs(outside.brightnessComponent - source.brightnessComponent) < 0.01)
    }

    @Test func croppedCapturePinsOverTheCroppedArea() throws {
        let model = try makeModel()
        model.setCrop(CGRect(x: 50, y: 25, width: 100, height: 50))
        let result = try model.renderedCapture()
        // Source frame is in Cocoa coordinates (bottom-left origin): top 25 pt in → maxY − 75.
        #expect(result.sourceFrame == CGRect(x: 150, y: 325, width: 100, height: 50))
        #expect(result.pointSize == CGSize(width: 100, height: 50))
    }
}
