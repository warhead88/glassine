import CoreGraphics
import Foundation

// The editor's document model. Pure values in image points (top-left origin),
// independent of zoom, so the canvas and the exporter draw exactly the same thing.

enum EditorTool: String, CaseIterable, Identifiable {
    case select, arrow, line, rectangle, ellipse, text, pen, marker, step, blur, pixelate, redact, crop

    var id: Self { self }

    var title: String {
        switch self {
        case .select: "Select"
        case .arrow: "Arrow"
        case .line: "Line"
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .text: "Text"
        case .pen: "Pen"
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
        case .pen: "scribble"
        case .marker: "highlighter"
        case .step: "1.circle"
        case .blur: "drop"
        case .pixelate: "squareshape.split.3x3"
        case .redact: "rectangle.fill"
        case .crop: "crop"
        }
    }

    /// Shortcut key as printed on a US keyboard.
    var keyLabel: String {
        switch self {
        case .select: "V"
        case .arrow: "A"
        case .line: "L"
        case .rectangle: "R"
        case .ellipse: "O"
        case .text: "T"
        case .pen: "D"
        case .marker: "M"
        case .step: "N"
        case .blur: "B"
        case .pixelate: "P"
        case .redact: "X"
        case .crop: "C"
        }
    }

    /// Physical key (ANSI virtual key code), so shortcuts work in any keyboard layout.
    var keyCode: UInt16 {
        switch self {
        case .select: 9
        case .arrow: 0
        case .line: 37
        case .rectangle: 15
        case .ellipse: 31
        case .text: 17
        case .pen: 2
        case .marker: 46
        case .step: 45
        case .blur: 11
        case .pixelate: 35
        case .redact: 7
        case .crop: 8
        }
    }

    static func forKeyCode(_ code: UInt16) -> EditorTool? { allCases.first { $0.keyCode == code } }

    /// Tools that draw one shape per drag; afterwards the editor switches to Select
    /// with the new shape selected, ready to adjust.
    var switchesToSelectAfterDrawing: Bool {
        switch self {
        case .arrow, .line, .rectangle, .ellipse, .text, .blur, .pixelate, .redact: true
        case .select, .pen, .marker, .step, .crop: false
        }
    }
}

/// sRGB color stored as plain components so annotations stay value types.
struct RGBA: Equatable, Hashable {
    var red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1

    var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }

    /// From a 0xRRGGBB value, as in the design tokens.
    init(hex: Int) {
        self.init(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255)
    }

    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    static let palette: [RGBA] = [
        RGBA(red: 1, green: 0.231, blue: 0.188),      // red
        RGBA(red: 1, green: 0.584, blue: 0),          // orange
        RGBA(red: 1, green: 0.8, blue: 0),            // yellow
        RGBA(red: 0.204, green: 0.78, blue: 0.349),   // green
        RGBA(red: 0, green: 0.478, blue: 1),          // blue
        RGBA(red: 1, green: 1, blue: 1),              // white
        RGBA(red: 0.11, green: 0.11, blue: 0.118),    // black
    ]

    /// Light colors (white, yellow) get dark text on numbered steps.
    var isLight: Bool { 0.299 * red + 0.587 * green + 0.114 * blue > 0.6 }
}

/// Stroke width range of the toolbar slider; text and steps scale with it.
enum StrokeWidth {
    static let range: ClosedRange<CGFloat> = 1...20
    static let `default`: CGFloat = 4
}

struct Annotation: Identifiable, Equatable {
    enum Shape: Equatable {
        case arrow(from: CGPoint, to: CGPoint)
        case line(from: CGPoint, to: CGPoint)
        case rectangle(CGRect)
        case ellipse(CGRect)
        case text(origin: CGPoint, string: String)
        case pen(points: [CGPoint])
        case marker(points: [CGPoint])
        case step(center: CGPoint)
        case blur(CGRect)
        case pixelate(CGRect)
        case redact(CGRect)
    }

    /// A grip on the selected annotation: one of a box's eight handles, or a line's ends.
    enum Handle: Equatable, Hashable {
        case box(SelectionGeometry.Handle)
        case start, end
    }

    let id: UUID
    var shape: Shape
    var color: RGBA
    /// Stroke width in points; text size and step diameter derive from it.
    var width: CGFloat

    init(id: UUID = UUID(), shape: Shape, color: RGBA, width: CGFloat = StrokeWidth.default) {
        self.id = id
        self.shape = shape
        self.color = color
        self.width = width
    }

    var fontSize: CGFloat { 10 + width * 3.5 }
    var stepDiameter: CGFloat { 18 + width * 3 }
    var markerWidth: CGFloat { width * 4 }

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
        case .pen(let points): copy.shape = .pen(points: points.map(p))
        case .marker(let points): copy.shape = .marker(points: points.map(p))
        case .step(let center): copy.shape = .step(center: p(center))
        case .blur(let rect): copy.shape = .blur(r(rect))
        case .pixelate(let rect): copy.shape = .pixelate(r(rect))
        case .redact(let rect): copy.shape = .redact(r(rect))
        }
        return copy
    }

    /// Grips shown when selected, with their positions. Text and steps resize with the width slider.
    func handles() -> [(Handle, CGPoint)] {
        switch shape {
        case .arrow(let a, let b), .line(let a, let b):
            return [(.start, a), (.end, b)]
        case .rectangle(let rect), .ellipse(let rect), .blur(let rect), .pixelate(let rect), .redact(let rect):
            return boxHandles(rect)
        case .pen(let points), .marker(let points):
            let box = AnnotationGeometry.boundingBox(points)
            return box.width > 0 && box.height > 0 ? boxHandles(box) : []
        case .text, .step:
            return []
        }
    }

    private func boxHandles(_ rect: CGRect) -> [(Handle, CGPoint)] {
        SelectionGeometry.Handle.allCases.map { (.box($0), SelectionGeometry.handlePoint($0, of: rect)) }
    }

    /// The annotation after dragging `handle` by `delta` from its original state.
    func resized(_ handle: Handle, by delta: CGVector) -> Annotation {
        func p(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x + delta.dx, y: point.y + delta.dy) }
        func box(_ rect: CGRect) -> CGRect {
            guard case .box(let h) = handle else { return rect }
            return SelectionGeometry.resized(rect, handle: h, dx: delta.dx, dy: delta.dy)
        }
        var copy = self
        switch shape {
        case .arrow(let a, let b):
            copy.shape = .arrow(from: handle == .start ? p(a) : a, to: handle == .end ? p(b) : b)
        case .line(let a, let b):
            copy.shape = .line(from: handle == .start ? p(a) : a, to: handle == .end ? p(b) : b)
        case .rectangle(let rect): copy.shape = .rectangle(box(rect))
        case .ellipse(let rect): copy.shape = .ellipse(box(rect))
        case .blur(let rect): copy.shape = .blur(box(rect))
        case .pixelate(let rect): copy.shape = .pixelate(box(rect))
        case .redact(let rect): copy.shape = .redact(box(rect))
        case .pen(let points):
            copy.shape = .pen(points: AnnotationGeometry.scaled(points, to: box(AnnotationGeometry.boundingBox(points))))
        case .marker(let points):
            copy.shape = .marker(points: AnnotationGeometry.scaled(points, to: box(AnnotationGeometry.boundingBox(points))))
        case .text, .step:
            break
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

    static func boundingBox(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Maps points from their bounding box onto `target`, keeping the drawing's shape.
    static func scaled(_ points: [CGPoint], to target: CGRect) -> [CGPoint] {
        let box = boundingBox(points)
        guard box.width > 0, box.height > 0 else { return points }
        return points.map {
            CGPoint(x: target.minX + ($0.x - box.minX) / box.width * target.width,
                    y: target.minY + ($0.y - box.minY) / box.height * target.height)
        }
    }

    private static func hitsPolyline(_ points: [CGPoint], at point: CGPoint, width: CGFloat) -> Bool {
        if points.count == 1 { return hypot(point.x - points[0].x, point.y - points[0].y) <= width }
        return zip(points, points.dropFirst()).contains { distance(from: point, toSegment: $0, $1) <= width / 2 + 3 }
    }

    /// Whether a click at `point` grabs the annotation. `textBounds` measures text, which
    /// depends on fonts and so is supplied by the renderer.
    static func hits(_ annotation: Annotation, at point: CGPoint, textBounds: (Annotation) -> CGRect) -> Bool {
        let tolerance = max(annotation.width, 6)
        switch annotation.shape {
        case .arrow(let a, let b), .line(let a, let b):
            return distance(from: point, toSegment: a, b) <= tolerance
        case .rectangle(let rect), .ellipse(let rect), .blur(let rect), .pixelate(let rect), .redact(let rect):
            return rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case .text:
            return textBounds(annotation).insetBy(dx: -4, dy: -4).contains(point)
        case .pen(let points):
            return hitsPolyline(points, at: point, width: max(annotation.width, 6))
        case .marker(let points):
            return hitsPolyline(points, at: point, width: annotation.markerWidth)
        case .step(let center):
            return hypot(point.x - center.x, point.y - center.y) <= annotation.stepDiameter / 2 + 2
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
