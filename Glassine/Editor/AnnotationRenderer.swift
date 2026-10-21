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

    /// The capture's edge color, used to continue it into the background.
    lazy var edgeColor: RGBA = EdgeColor.of(image)

    func drawImage() {
        nsImage.draw(in: imageBounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
    }

    /// Everything under the annotations: background around the capture (when there is
    /// space around it), the capture's shadow, and the capture with rounded corners.
    func drawBase(canvas: CGRect, background: BackgroundSettings) {
        let radius = min(background.cornerRadius, min(imageBounds.width, imageBounds.height) / 2)
        let imagePath = NSBezierPath(roundedRect: imageBounds, xRadius: radius, yRadius: radius)
        let hasSpace = canvas != imageBounds

        if hasSpace {
            switch background.fill {
            case .extend:
                NSColor(cgColor: edgeColor.cgColor)?.setFill()
                canvas.fill()
            case .none:
                break
            case .color(let color):
                NSColor(cgColor: color.cgColor)?.setFill()
                canvas.fill()
            case .gradient(let index):
                let preset = BackgroundSettings.gradients[index]
                NSGradient(starting: NSColor(cgColor: preset.from.cgColor)!, ending: NSColor(cgColor: preset.to.cgColor)!)?
                    .draw(in: canvas, angle: 45)
            }

            if background.shadow {
                NSGraphicsContext.saveGraphicsState()
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
                shadow.shadowBlurRadius = 18
                shadow.shadowOffset = NSSize(width: 0, height: -6)
                shadow.set()
                NSColor.black.setFill()
                imagePath.fill()
                NSGraphicsContext.restoreGraphicsState()
            }
        }

        NSGraphicsContext.saveGraphicsState()
        imagePath.addClip()
        drawImage()
        NSGraphicsContext.restoreGraphicsState()
    }

    func draw(_ annotations: [Annotation], stepNumbers: [UUID: Int]) {
        for annotation in annotations {
            draw(annotation, number: stepNumbers[annotation.id] ?? stepNumbers.count + 1)
        }
    }

    func draw(_ annotation: Annotation, number: Int) {
        let color = NSColor(cgColor: annotation.color.cgColor) ?? .red
        let width = annotation.width

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

        case .pen(let points):
            stroke(polyline(points), color: color, width: width)

        case .marker(let points):
            let path = polyline(points)
            path.lineWidth = annotation.markerWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            color.withAlphaComponent(0.4).setStroke()
            path.stroke()

        case .step(let center):
            let d = annotation.stepDiameter
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
            .font: NSFont.systemFont(ofSize: annotation.fontSize, weight: .semibold),
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
        let pad = annotation.width
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
        case .pen(let points):
            return AnnotationGeometry.boundingBox(points).insetBy(dx: -pad, dy: -pad)
        case .marker(let points):
            return AnnotationGeometry.boundingBox(points).insetBy(dx: -annotation.markerWidth / 2, dy: -annotation.markerWidth / 2)
        case .step(let center):
            let r = annotation.stepDiameter / 2
            return CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        }
    }

    func hitTest(_ annotations: [Annotation], at point: CGPoint) -> Annotation? {
        annotations.last { AnnotationGeometry.hits($0, at: point, textBounds: textBounds) }
    }

    /// Renders `area` (image points) of the document — background, capture and annotations —
    /// at `scale` pixels per point.
    func render(annotations: [Annotation], stepNumbers: [UUID: Int], area: CGRect, canvas: CGRect,
                background: BackgroundSettings, scale: CGFloat) -> CGImage? {
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
        drawBase(canvas: canvas, background: background)
        draw(annotations, stepNumbers: stepNumbers)
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    // MARK: Helpers

    private func polyline(_ points: [CGPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        guard let first = points.first else { return path }
        path.move(to: first)
        points.dropFirst().forEach { path.line(to: $0) }
        if points.count == 1 { path.line(to: first) }
        return path
    }

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
