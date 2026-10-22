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

    /// Two-stop gradients, top-left to bottom-right, in the 0.4 palette (Design/0.4, DECISIONS 11).
    static let gradients: [(name: String, from: RGBA, to: RGBA)] = [
        ("Sleeve", RGBA(hex: 0xF7F7F3), RGBA(hex: 0xE2E3DC)),
        ("Sage", RGBA(hex: 0xB9C7B2), RGBA(hex: 0x6F8869)),
        ("Stamp", RGBA(hex: 0x9DB3CC), RGBA(hex: 0x5E7C9E)),
        ("Peach", RGBA(hex: 0xF2D9BF), RGBA(hex: 0xD9A57C)),
        ("Ink", RGBA(hex: 0x3A4254), RGBA(hex: 0x1C2230)),
    ]

    /// Version of `gradients`, saved with the choice: 1 was Ocean, Sunset, Mint, Graphite, Paper.
    static let gradientsVersion = 2

    /// A gradient saved under an older version, as the nearest of today's.
    static func migratedGradient(_ index: Int, from version: Int) -> Int {
        let clamped = min(max(index, 0), gradients.count - 1)
        guard version < gradientsVersion else { return clamped }
        // Ocean → Stamp, Sunset → Peach, Mint → Sage, Graphite → Ink, Paper → Sleeve.
        return [2, 3, 1, 4, 0][min(max(index, 0), 4)]
    }
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
