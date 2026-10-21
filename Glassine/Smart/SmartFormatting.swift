import CoreGraphics
import Foundation

// Pure formatting behind the smart tools (text recognition, color picker, ruler),
// kept free of AppKit and Vision so it can be unit-tested.

enum ColorFormat: String, CaseIterable, Identifiable {
    case hex, rgb, hsl

    var id: Self { self }

    var title: String {
        switch self {
        case .hex: "HEX — #FF8000"
        case .rgb: "RGB — rgb(255, 128, 0)"
        case .hsl: "HSL — hsl(30, 100%, 50%)"
        }
    }

    /// Formats sRGB components in 0…1.
    func string(red: CGFloat, green: CGFloat, blue: CGFloat) -> String {
        let r = Self.byte(red), g = Self.byte(green), b = Self.byte(blue)
        switch self {
        case .hex:
            return String(format: "#%02X%02X%02X", r, g, b)
        case .rgb:
            return "rgb(\(r), \(g), \(b))"
        case .hsl:
            let (h, s, l) = Self.hsl(red: red, green: green, blue: blue)
            return "hsl(\(Int(h.rounded())), \(Int((s * 100).rounded()))%, \(Int((l * 100).rounded()))%)"
        }
    }

    private static func byte(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }

    /// Hue in degrees 0…360, saturation and lightness 0…1.
    static func hsl(red: CGFloat, green: CGFloat, blue: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
        let maxC = max(red, green, blue), minC = min(red, green, blue)
        let l = (maxC + minC) / 2
        let delta = maxC - minC
        guard delta > 0 else { return (0, 0, l) }
        let s = delta / (1 - abs(2 * l - 1))
        var h: CGFloat
        switch maxC {
        case red: h = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        case green: h = (blue - red) / delta + 2
        default: h = (red - green) / delta + 4
        }
        h *= 60
        if h < 0 { h += 360 }
        return (h, s, l)
    }
}

/// Distance readout for the ruler.
enum Measurement {
    /// Length and offsets in pixels and points between two points given in points.
    static func describe(from a: CGPoint, to b: CGPoint, scale: CGFloat) -> String {
        let dx = abs(b.x - a.x), dy = abs(b.y - a.y)
        let points = hypot(dx, dy)
        let pixels = points * scale
        var text = "\(Int(pixels.rounded())) px"
        if scale != 1 { text += " · \(format(points)) pt" }
        if dx >= 1 && dy >= 1 {
            text += "   ↔ \(Int((dx * scale).rounded()))  ↕ \(Int((dy * scale).rounded()))"
        }
        return text
    }

    /// Shift on the ruler: straight horizontal, vertical or 45° lines.
    static func snapped(_ point: CGPoint, from origin: CGPoint) -> CGPoint {
        AnnotationGeometry.snapped(point, from: origin)
    }

    private static func format(_ value: CGFloat) -> String {
        value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value)
    }
}

/// Turns recognized text fragments into readable text: top to bottom, and fragments that
/// share a line joined left to right with a space.
enum TextLayout {
    struct Fragment: Equatable {
        var text: String
        /// Normalized box with a top-left origin (0…1).
        var box: CGRect
    }

    static func join(_ fragments: [Fragment]) -> String {
        let sorted = fragments.sorted { $0.box.midY < $1.box.midY }
        var lines: [[Fragment]] = []
        for fragment in sorted {
            // Same line when the vertical centers are within half a line height.
            if let last = lines.last?.last, abs(last.box.midY - fragment.box.midY) < min(last.box.height, fragment.box.height) / 2 {
                lines[lines.count - 1].append(fragment)
            } else {
                lines.append([fragment])
            }
        }
        return lines
            .map { $0.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ") }
            .joined(separator: "\n")
    }
}
