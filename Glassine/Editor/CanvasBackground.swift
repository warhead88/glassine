import CoreGraphics
import Foundation

/// How the space around the capture looks: padding, rounded corners, shadow and fill.
/// The space exists when there's padding or when annotations reach past the image.
struct BackgroundSettings: Equatable {
    enum Fill: Equatable, Hashable {
        /// Continues the capture: the dominant color along its edges.
        case extend
        /// Transparent (PNG); shown as a checkerboard in the editor.
        case none
        case color(RGBA)
        case gradient(Int)
    }

    var fill: Fill = .extend
    var padding: CGFloat = 0
    var cornerRadius: CGFloat = 0
    var shadow = true

    static let paddingRange: ClosedRange<CGFloat> = 0...160
    static let cornerRange: ClosedRange<CGFloat> = 0...48

    static let solidColors: [RGBA] = [
        RGBA(red: 1, green: 1, blue: 1),
        RGBA(red: 0.11, green: 0.11, blue: 0.118),
    ]

    /// Two-stop gradients, top-left to bottom-right.
    static let gradients: [(name: String, from: RGBA, to: RGBA)] = [
        ("Ocean", RGBA(red: 0.31, green: 0.49, blue: 1), RGBA(red: 0.64, green: 0.36, blue: 1)),
        ("Sunset", RGBA(red: 1, green: 0.54, blue: 0.24), RGBA(red: 1, green: 0.24, blue: 0.5)),
        ("Mint", RGBA(red: 0.2, green: 0.83, blue: 0.6), RGBA(red: 0.05, green: 0.65, blue: 0.91)),
        ("Graphite", RGBA(red: 0.23, green: 0.23, blue: 0.24), RGBA(red: 0.11, green: 0.11, blue: 0.12)),
        ("Paper", RGBA(red: 0.96, green: 0.96, blue: 0.97), RGBA(red: 0.9, green: 0.9, blue: 0.92)),
    ]
}

enum CanvasLayout {
    /// Breathing room kept around annotations that reach past the image.
    static let annotationMargin: CGFloat = 16

    /// The exported area in image points: the image grown by `padding`, plus anything
    /// annotations draw outside it. Origin may be negative (left of / above the image).
    static func canvasRect(image: CGRect, annotationBounds: [CGRect], padding: CGFloat) -> CGRect {
        var rect = image.insetBy(dx: -padding, dy: -padding)
        for bounds in annotationBounds where !bounds.isNull && !image.contains(bounds) {
            rect = rect.union(bounds.insetBy(dx: -annotationMargin, dy: -annotationMargin))
        }
        return rect.integral
    }
}

enum EdgeColor {
    /// The color along an image's border: the most common color (quantized) if the edge
    /// is mostly uniform, otherwise the plain average. `pixels` are border samples.
    static func dominant(_ pixels: [RGBA]) -> RGBA {
        guard !pixels.isEmpty else { return RGBA(red: 0.12, green: 0.12, blue: 0.12) }
        func key(_ c: RGBA) -> Int {
            (Int(c.red * 15.99) << 8) | (Int(c.green * 15.99) << 4) | Int(c.blue * 15.99)
        }
        let groups = Dictionary(grouping: pixels, by: key)
        let largest = groups.values.max { $0.count < $1.count } ?? pixels
        let source = Double(largest.count) / Double(pixels.count) > 0.5 ? largest : pixels
        let n = CGFloat(source.count)
        return RGBA(
            red: source.reduce(0) { $0 + $1.red } / n,
            green: source.reduce(0) { $0 + $1.green } / n,
            blue: source.reduce(0) { $0 + $1.blue } / n
        )
    }

    /// Samples the border of `image` (downscaled to 64 px for speed).
    static func of(_ image: CGImage) -> RGBA {
        let side = 64
        var data = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = data.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return dominant([]) }

        var samples: [RGBA] = []
        for i in 0..<side {
            for (x, y) in [(i, 0), (i, side - 1), (0, i), (side - 1, i)] {
                let o = (y * side + x) * 4
                samples.append(RGBA(red: CGFloat(data[o]) / 255, green: CGFloat(data[o + 1]) / 255, blue: CGFloat(data[o + 2]) / 255))
            }
        }
        return dominant(samples)
    }
}
