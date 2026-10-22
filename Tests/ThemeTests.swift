import AppKit
import CoreText
import Testing
@testable import Glassine

@Suite("Contrast")
struct ContrastTests {
    let white = Contrast.RGB(red: 1, green: 1, blue: 1)
    let black = Contrast.RGB(red: 0, green: 0, blue: 0)
    let ink = Contrast.RGB(red: 0x1C / 255, green: 0x22 / 255, blue: 0x30 / 255)

    @Test func extremes() {
        #expect(Contrast.luminance(white) == 1)
        #expect(Contrast.luminance(black) == 0)
        #expect(abs(Contrast.ratio(white, black) - 21) < 0.001)
        #expect(Contrast.ratio(ink, ink) == 1)
    }

    @Test func textOnTheSystemAccent() {
        let yellow = Contrast.RGB(red: 1, green: 0.8, blue: 0)
        let blue = Contrast.RGB(red: 0, green: 0.478, blue: 1)
        #expect(Contrast.prefersDarkText(on: yellow, dark: ink))
        #expect(!Contrast.prefersDarkText(on: blue, dark: ink))
    }

    @Test func accentDefaultFollowsMacOS() {
        #expect(AccentChoice.default(systemAccentChosen: false) == .ink)
        #expect(AccentChoice.default(systemAccentChosen: true) == .system)
    }
}

/// The generated asset catalog, checked against WCAG in both appearances — a bad edit to
/// tokens.json fails here.
@Suite("Theme colors")
struct ThemeColorTests {
    func rgb(_ color: NSColor, _ appearance: NSAppearance.Name) -> Contrast.RGB {
        var result: Contrast.RGB?
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance { result = Contrast.RGB(color) }
        return result!
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func accentsCarryReadableText(_ appearance: NSAppearance.Name) {
        let pairs: [(NSColor, NSColor)] = [(.accentInk, .onAccentInk), (.accentSage, .onAccentSage),
                                           (.accentStamp, .onAccentStamp), (.accentOchre, .onAccentOchre)]
        for (fill, text) in pairs {
            #expect(Contrast.ratio(rgb(fill, appearance), rgb(text, appearance)) >= 4.5)
        }
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func textReadsOnPaperAndCards(_ appearance: NSAppearance.Name) {
        for surface in [NSColor.paper, .card] {
            for text in [NSColor.ink, .ink2, .ink3] {
                #expect(Contrast.ratio(rgb(text, appearance), rgb(surface, appearance)) >= 4.5)
            }
        }
    }

    @Test func darkThemeIsDark() {
        #expect(Contrast.luminance(rgb(.paper, .darkAqua)) < Contrast.luminance(rgb(.paper, .aqua)))
    }
}

@Suite("Typography")
struct TypographyTests {
    func variation(_ font: NSFont) -> [UInt32: Double] {
        let raw = CTFontCopyVariation(font as CTFont) as? [NSNumber: NSNumber] ?? [:]
        return Dictionary(uniqueKeysWithValues: raw.map { ($0.key.uint32Value, $0.value.doubleValue) })
    }

    @Test func axisTags() {
        #expect(Typography.axis("wght").uint32Value == 0x7767_6874)
        #expect(Typography.axis("SOFT").uint32Value == 0x534F_4654)
    }

    @Test func frauncesShipsWithTheApp() {
        let font = Typography.nsFont(ThemeTokens.title)
        #expect(font.familyName == "Fraunces")
        let axes = variation(font)
        #expect(axes[Typography.axis("SOFT").uint32Value] == 100)
        #expect(axes[Typography.axis("WONK").uint32Value] ?? 0 == 0)
        #expect(axes[Typography.axis("wght").uint32Value] == 460)
        #expect(axes[Typography.axis("opsz").uint32Value] == 28)
    }

    @Test func datesAreItalic() {
        let font = Typography.nsFont(ThemeTokens.date)
        #expect(font.familyName == "Fraunces")
        #expect(font.fontDescriptor.symbolicTraits.contains(.italic))
    }

    @Test func opticalSizeStaysInTheFontsRange() {
        let tiny = variation(Typography.fraunces(size: 6))
        let huge = variation(Typography.fraunces(size: 200))
        #expect(tiny[Typography.axis("opsz").uint32Value] ?? 9 == 9) // 9 is the axis default, left out
        #expect(huge[Typography.axis("opsz").uint32Value] == 144)
    }

    @Test func interfaceRolesUseSystemFonts() {
        #expect(Typography.nsFont(ThemeTokens.body).familyName != "Fraunces")
        #expect(Typography.systemWeight(500) == .medium)
        #expect(Typography.systemWeight(nil) == .regular)
    }
}

@Suite("Key caps")
struct KeyCapTests {
    @Test func modifiersEachGetACap() {
        #expect(KeyCapParts.split("⌥⇧⌘R") == ["⌥", "⇧", "⌘", "R"])
        #expect(KeyCapParts.split("⇧⌘4") == ["⇧", "⌘", "4"])
        #expect(KeyCapParts.split("⌥⇧⌘,") == ["⌥", "⇧", "⌘", ","])
    }

    @Test func namedKeysStayWhole() {
        #expect(KeyCapParts.split("⌃F12") == ["⌃", "F12"])
        #expect(KeyCapParts.split("Space") == ["Space"])
        #expect(KeyCapParts.split("") == [])
    }
}
