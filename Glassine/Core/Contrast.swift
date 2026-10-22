import Foundation

/// WCAG 2 color contrast, for picking text on a fill and for checking the theme in tests.
enum Contrast {
    struct RGB: Equatable {
        var red, green, blue: Double // sRGB, 0…1
    }

    /// Relative luminance of an sRGB color.
    static func luminance(_ c: RGB) -> Double {
        func linear(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(c.red) + 0.7152 * linear(c.green) + 0.0722 * linear(c.blue)
    }

    /// 1…21; text needs 4.5 (3 when large).
    static func ratio(_ a: RGB, _ b: RGB) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Whether dark text reads better than white on `fill` — for the system accent, whose
    /// color the user picks in System Settings.
    static func prefersDarkText(on fill: RGB, dark: RGB) -> Bool {
        ratio(fill, dark) > ratio(fill, RGB(red: 1, green: 1, blue: 1))
    }
}
