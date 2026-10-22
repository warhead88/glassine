import AppKit
import CoreText
import SwiftUI

/// Glassine's type: Fraunces (bundled, loaded through ATSApplicationFontsPath) for titles, dates
/// and numbers; SF Pro for the interface; SF Mono for small caps labels. Roles and sizes come
/// from the generated `ThemeTokens`.
enum Typography {
    /// The serif is set soft, never wonky, like the G on the icon; its optical size follows the size.
    static let softness: CGFloat = 100

    static func nsFont(_ style: ThemeTokens.TypeStyle) -> NSFont {
        switch style.family {
        case .serif:
            fraunces(size: style.size, weight: style.weight ?? 400, italic: style.italic)
        case .sans:
            .systemFont(ofSize: style.size, weight: systemWeight(style.weight))
        case .mono:
            .monospacedSystemFont(ofSize: style.size, weight: systemWeight(style.weight))
        }
    }

    static func font(_ style: ThemeTokens.TypeStyle) -> Font {
        Font(nsFont(style) as CTFont)
    }

    /// Fraunces at any size and weight; New York (the system serif) if it can't be loaded.
    static func fraunces(size: CGFloat, weight: CGFloat = 400, italic: Bool = false) -> NSFont {
        var descriptor = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: "Fraunces"] as CFDictionary)
        if italic {
            descriptor = CTFontDescriptorCreateCopyWithSymbolicTraits(descriptor, .traitItalic, .traitItalic) ?? descriptor
        }
        let variation: [NSNumber: NSNumber] = [
            axis("wght"): NSNumber(value: Double(weight)),
            axis("opsz"): NSNumber(value: Double(min(max(size, 9), 144))),
            axis("SOFT"): NSNumber(value: Double(softness)),
            axis("WONK"): 0,
        ]
        descriptor = CTFontDescriptorCreateCopyWithAttributes(
            descriptor, [kCTFontVariationAttribute: variation] as CFDictionary)
        let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        guard CTFontCopyFamilyName(font) as String == "Fraunces" else { return systemSerif(size: size, italic: italic) }
        return font as NSFont
    }

    /// A variation axis identifier from its four-letter tag ("wght" → 0x77676874).
    static func axis(_ tag: String) -> NSNumber {
        NSNumber(value: tag.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
    }

    private static func systemSerif(size: CGFloat, italic: Bool) -> NSFont {
        var descriptor = NSFont.systemFont(ofSize: size).fontDescriptor.withDesign(.serif) ?? NSFont.systemFont(ofSize: size).fontDescriptor
        if italic { descriptor = descriptor.withSymbolicTraits(.italic) }
        return NSFont(descriptor: descriptor, size: size) ?? .systemFont(ofSize: size)
    }

    /// CSS-style weights (400 regular, 500 medium, 600 semibold) to the system font's weights.
    static func systemWeight(_ weight: CGFloat?) -> NSFont.Weight {
        switch weight ?? 400 {
        case ..<350: .light
        case ..<450: .regular
        case ..<550: .medium
        case ..<650: .semibold
        default: .bold
        }
    }
}

extension View {
    /// A role from the type scale: font, tracking and case.
    func textStyle(_ style: ThemeTokens.TypeStyle) -> some View {
        font(Typography.font(style))
            .tracking(style.tracking)
            .textCase(style.uppercase ? .uppercase : nil)
    }
}
