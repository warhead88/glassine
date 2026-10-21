import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Draws a capture and its annotations. The canvas and the exporter both call `draw`,
/// with the current NSGraphicsContext flipped and scaled to image points.
@MainActor
final class AnnotationRenderer {
    let image: CGImage
    let pointSize: CGSize

    private lazy var nsImage = NSImage(cgImage: image, size: pointSize)
    private lazy var blurred: NSImage? = filtered { input in
        input.clampedToExtent().applyingGaussianBlur(sigma: Double(image.width) / 120 + 6).cropped(to: input.extent)
    }
    private lazy var pixelated: NSImage? = filtered { input in
        let filter = CIFilter.pixellate()
        filter.inputImage = input.clampedToExtent()
        filter.scale = Float(max(Double(image.width) / 70, 10))
        filter.center = .zero
        return filter.outputImage?.cropped(to: input.extent)
    }

    init(image: CGImage, pointSize: CGSize) {
        self.image = image
        self.pointSize = pointSize
    }

    var imageBounds: CGRect { CGRect(origin: .zero, size: pointSize) }

    func drawImage() {
        nsImage.draw(in: imageBounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
    }

    func draw(_ annotations: [Annotation], stepNumbers: [UUID: Int]) {
        for annotation in annotations {
            draw(annotation, number: stepNumbers[annotation.id] ?? stepNumbers.count + 1)
        }
    }

    func draw(_ annotation: Annotation, number: Int) {
        let color = NSColor(cgColor: annotation.color.cgColor) ?? .red
        let width = annotation.size.lineWidth

        switch annotation.shape {
        case .arrow(let from, let to):
            let parts = AnnotationGeometry.arrowParts(from: from, to: to, lineWidth: width)
            let shaft = NSBezierPath()
            shaft.move(to: from)
            shaft.line(to: parts.shaftEnd)
            stroke(shaft, color: color, width: width)
            let head = NSBezierPath()
            head.move(to: parts.head[0])
            parts.head.dropFirst().forEach { head.line(to: $0) }
            head.close()
            head.lineJoinStyle = .round
            withShadow { color.setFill(); head.fill() }

        case .line(let from, let to):
            let path = NSBezierPath()
            path.move(to: from)
            path.line(to: to)
            stroke(path, color: color, width: width)

        case .rectangle(let rect):
            stroke(NSBezierPath(roundedRect: rect, xRadius: width, yRadius: width), color: color, width: width)

        case .ellipse(let rect):
            stroke(NSBezierPath(ovalIn: rect), color: color, width: width)

        case .text(let origin, let string):
            withShadow { NSAttributedString(string: string, attributes: textAttributes(for: annotation)).draw(at: origin) }

        case .marker(let points):
            guard let first = points.first else { return }
            let path = NSBezierPath()
            path.move(to: first)
            points.dropFirst().forEach { path.line(to: $0) }
            if points.count == 1 { path.line(to: first) }
            path.lineWidth = width * 4
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            color.withAlphaComponent(0.4).setStroke()
            path.stroke()

        case .step(let center):
            let d = annotation.size.stepDiameter
            let circle = NSBezierPath(ovalIn: CGRect(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d))
            withShadow { color.setFill(); circle.fill() }
            let label = NSAttributedString(string: "\(number)", attributes: [
                .font: NSFont.systemFont(ofSize: d * 0.55, weight: .bold),
                .foregroundColor: annotation.color.isLight ? NSColor.black : NSColor.white,
            ])
            let size = label.size()
            label.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))

        case .blur(let rect):
            drawFiltered(blurred, in: rect)

        case .pixelate(let rect):
            drawFiltered(pixelated, in: rect)

        case .redact(let rect):
            color.setFill()
            rect.fill()
        }
    }

    func textAttributes(for annotation: Annotation) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: annotation.size.fontSize, weight: .semibold),
            .foregroundColor: NSColor(cgColor: annotation.color.cgColor) ?? .red,
        ]
    }

    func textBounds(_ annotation: Annotation) -> CGRect {
        guard case .text(let origin, let string) = annotation.shape else { return .zero }
        let size = NSAttributedString(string: string, attributes: textAttributes(for: annotation)).size()
        return CGRect(origin: origin, size: size)
    }

    /// Area an annotation covers, for the selection outline.
    func bounds(of annotation: Annotation) -> CGRect {
        let pad = annotation.size.lineWidth
        switch annotation.shape {
        case .arrow(let a, let b), .line(let a, let b):
            return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
                .insetBy(dx: -pad * 2, dy: -pad * 2)
        case .rectangle(let rect), .ellipse(let rect):
            return rect.insetBy(dx: -pad, dy: -pad)
        case .blur(let rect), .pixelate(let rect), .redact(let rect):
            return rect
        case .text:
            return textBounds(annotation)
        case .marker(let points):
            let xs = points.map(\.x), ys = points.map(\.y)
            return CGRect(x: xs.min() ?? 0, y: ys.min() ?? 0, width: (xs.max() ?? 0) - (xs.min() ?? 0),
                          height: (ys.max() ?? 0) - (ys.min() ?? 0)).insetBy(dx: -pad * 2, dy: -pad * 2)
        case .step(let center):
            let r = annotation.size.stepDiameter / 2
            return CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        }
    }

    func hitTest(_ annotations: [Annotation], at point: CGPoint) -> Annotation? {
        annotations.last { AnnotationGeometry.hits($0, at: point, textBounds: textBounds) }
    }

    /// Renders the final image at `scale` pixels per point, cropped to `crop` (image points).
    func render(annotations: [Annotation], stepNumbers: [UUID: Int], crop: CGRect?, scale: CGFloat) -> CGImage? {
        let area = crop ?? imageBounds
        let width = Int((area.width * scale).rounded()), height = Int((area.height * scale).rounded())
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        // Top-left origin in image points, like the canvas.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -area.minX, y: -area.minY)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        drawImage()
        draw(annotations, stepNumbers: stepNumbers)
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    // MARK: Helpers

    private func stroke(_ path: NSBezierPath, color: NSColor, width: CGFloat) {
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        withShadow { color.setStroke(); path.stroke() }
    }

    /// A soft shadow keeps annotations readable on both light and dark content.
    private func withShadow(_ draw: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        draw()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawFiltered(_ filtered: NSImage?, in rect: CGRect) {
        guard let filtered else { return }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        filtered.draw(in: imageBounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func filtered(_ apply: (CIImage) -> CIImage?) -> NSImage? {
        let input = CIImage(cgImage: image)
        guard let output = apply(input),
              let cgImage = CIContext().createCGImage(output, from: input.extent)
        else { return nil }
        return NSImage(cgImage: cgImage, size: pointSize)
    }
}

extension RGBA {
    /// Light colors (white, yellow) get dark text on numbered steps.
    var isLight: Bool { 0.299 * red + 0.587 * green + 0.114 * blue > 0.6 }
}
