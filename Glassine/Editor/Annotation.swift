import CoreGraphics
import Foundation

// The editor's document model. Pure values in image points (top-left origin),
// independent of zoom, so the canvas and the exporter draw exactly the same thing.

enum EditorTool: String, CaseIterable, Identifiable {
    case select, arrow, line, rectangle, ellipse, text, marker, step, blur, pixelate, redact, crop

    var id: Self { self }

    var title: String {
        switch self {
        case .select: "Select"
        case .arrow: "Arrow"
        case .line: "Line"
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .text: "Text"
        case .marker: "Marker"
        case .step: "Numbered Step"
        case .blur: "Blur"
        case .pixelate: "Pixelate"
        case .redact: "Redact"
        case .crop: "Crop"
        }
    }

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .line: "line.diagonal"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .text: "textformat"
        case .marker: "highlighter"
        case .step: "1.circle"
        case .blur: "drop"
        case .pixelate: "squareshape.split.3x3"
        case .redact: "rectangle.fill"
        case .crop: "crop"
        }
    }

    /// Single-key shortcut, as in most annotation tools.
    var key: Character {
        switch self {
        case .select: "v"
        case .arrow: "a"
        case .line: "l"
        case .rectangle: "r"
        case .ellipse: "o"
        case .text: "t"
        case .marker: "m"
        case .step: "n"
        case .blur: "b"
        case .pixelate: "p"
        case .redact: "x"
        case .crop: "c"
        }
    }
}

/// sRGB color stored as plain components so annotations stay value types.
struct RGBA: Equatable, Hashable {
    var red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1

    var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }

    func withAlpha(_ alpha: CGFloat) -> RGBA { RGBA(red: red, green: green, blue: blue, alpha: alpha) }

    static let palette: [RGBA] = [
        RGBA(red: 1, green: 0.231, blue: 0.188),      // red
        RGBA(red: 1, green: 0.584, blue: 0),          // orange
        RGBA(red: 1, green: 0.8, blue: 0),            // yellow
        RGBA(red: 0.204, green: 0.78, blue: 0.349),   // green
        RGBA(red: 0, green: 0.478, blue: 1),          // blue
        RGBA(red: 1, green: 1, blue: 1),              // white
        RGBA(red: 0.11, green: 0.11, blue: 0.118),    // black
    ]
}

/// One size control for every tool, so the toolbar stays small.
enum AnnotationSize: Int, CaseIterable, Identifiable {
    case small = 1, medium = 2, large = 3

    var id: Self { self }
    var title: String { ["S", "M", "L"][rawValue - 1] }
    var lineWidth: CGFloat { [2, 4, 8][rawValue - 1] }
    var fontSize: CGFloat { [16, 24, 36][rawValue - 1] }
    var stepDiameter: CGFloat { [22, 30, 42][rawValue - 1] }
}

struct Annotation: Identifiable, Equatable {
    enum Shape: Equatable {
        case arrow(from: CGPoint, to: CGPoint)
        case line(from: CGPoint, to: CGPoint)
        case rectangle(CGRect)
        case ellipse(CGRect)
        case text(origin: CGPoint, string: String)
        case marker(points: [CGPoint])
        case step(center: CGPoint)
        case blur(CGRect)
        case pixelate(CGRect)
        case redact(CGRect)
    }

    let id: UUID
    var shape: Shape
    var color: RGBA
    var size: AnnotationSize

    init(id: UUID = UUID(), shape: Shape, color: RGBA, size: AnnotationSize) {
        self.id = id
        self.shape = shape
        self.color = color
        self.size = size
    }

    /// The same annotation shifted by `delta` (used when dragging with the select tool).
    func moved(by delta: CGVector) -> Annotation {
        func p(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x + delta.dx, y: point.y + delta.dy) }
        func r(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: delta.dx, dy: delta.dy) }
        var copy = self
        switch shape {
        case .arrow(let from, let to): copy.shape = .arrow(from: p(from), to: p(to))
        case .line(let from, let to): copy.shape = .line(from: p(from), to: p(to))
        case .rectangle(let rect): copy.shape = .rectangle(r(rect))
        case .ellipse(let rect): copy.shape = .ellipse(r(rect))
        case .text(let origin, let string): copy.shape = .text(origin: p(origin), string: string)
        case .marker(let points): copy.shape = .marker(points: points.map(p))
        case .step(let center): copy.shape = .step(center: p(center))
        case .blur(let rect): copy.shape = .blur(r(rect))
        case .pixelate(let rect): copy.shape = .pixelate(r(rect))
        case .redact(let rect): copy.shape = .redact(r(rect))
        }
        return copy
    }
}

/// Geometry for drawing and hit-testing annotations.
enum AnnotationGeometry {
    /// Arrow as a shaft (ending at the base of the head) plus a filled triangular head.
    static func arrowParts(from: CGPoint, to: CGPoint, lineWidth: CGFloat) -> (shaftEnd: CGPoint, head: [CGPoint]) {
        let dx = to.x - from.x, dy = to.y - from.y
        let length = max(hypot(dx, dy), 0.001)
        let ux = dx / length, uy = dy / length
        let headLength = min(max(lineWidth * 4, 12), length)
        let headHalfWidth = headLength * 0.55
        let base = CGPoint(x: to.x - ux * headLength, y: to.y - uy * headLength)
        let left = CGPoint(x: base.x - uy * headHalfWidth, y: base.y + ux * headHalfWidth)
        let right = CGPoint(x: base.x + uy * headHalfWidth, y: base.y - ux * headHalfWidth)
        return (base, [to, left, right])
    }

    /// Snaps the end point to the nearest 45° direction (Shift with lines and arrows).
    static func snapped(_ point: CGPoint, from origin: CGPoint) -> CGPoint {
        let dx = point.x - origin.x, dy = point.y - origin.y
        let length = hypot(dx, dy)
        let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
        return CGPoint(x: origin.x + cos(angle) * length, y: origin.y + sin(angle) * length)
    }

    static func distance(from point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - a.x, point.y - a.y) }
        let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared))
        return hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy))
    }

    /// Whether a click at `point` grabs the annotation. `textBounds` measures text, which
    /// depends on fonts and so is supplied by the renderer.
    static func hits(_ annotation: Annotation, at point: CGPoint, textBounds: (Annotation) -> CGRect) -> Bool {
        let tolerance = max(annotation.size.lineWidth, 6)
        switch annotation.shape {
        case .arrow(let a, let b), .line(let a, let b):
            return distance(from: point, toSegment: a, b) <= tolerance
        case .rectangle(let rect), .ellipse(let rect), .blur(let rect), .pixelate(let rect), .redact(let rect):
            return rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case .text:
            return textBounds(annotation).insetBy(dx: -4, dy: -4).contains(point)
        case .marker(let points):
            let width = annotation.size.lineWidth * 4
            return zip(points, points.dropFirst()).contains { distance(from: point, toSegment: $0, $1) <= width / 2 + 2 }
                || (points.count == 1 && hypot(point.x - points[0].x, point.y - points[0].y) <= width)
        case .step(let center):
            return hypot(point.x - center.x, point.y - center.y) <= annotation.size.stepDiameter / 2 + 2
        }
    }

    /// Numbers for step annotations, in the order they were added (1, 2, 3…).
    static func stepNumbers(_ annotations: [Annotation]) -> [UUID: Int] {
        var numbers: [UUID: Int] = [:]
        for annotation in annotations {
            if case .step = annotation.shape { numbers[annotation.id] = numbers.count + 1 }
        }
        return numbers
    }

    /// Rect dragged between two points; Shift makes it square.
    static func rect(from a: CGPoint, to b: CGPoint, square: Bool) -> CGRect {
        SelectionGeometry.rect(anchor: a, point: b, square: square, fromCenter: false)
    }
}
