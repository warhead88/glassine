// Renders the DMG window background (1x, 2x and the combined TIFF) for scripts/release.sh:
//   swift Design/tools/dmg-background.swift Design/dmg
//
// The 0.4 look: paper, Glassine and Applications each on a postage stamp, a perforated line
// with an ink arrowhead between them, Fraunces for the title and caption. Colors come from
// Design/0.4/tokens.json (light theme: the background is an image and doesn't follow dark mode).
import AppKit
import CoreImage

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let size = CGSize(width: 640, height: 400)
// Icon centers, in Finder's top-left coordinates — match scripts/dmg-settings.py.
// Finder's path and status bars (global settings in current macOS) can cover the bottom ~56 pt,
// so everything that matters stays above y = 330.
let appCenter = CGPoint(x: 170, y: 168), appsCenter = CGPoint(x: 470, y: 168)

// MARK: Tokens and fonts

let tokens = try! JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("0.4/tokens.json"))) as! [String: Any]
let light = tokens["light"] as! [String: String]
let perforation = tokens["perforation"] as! [String: Double]

func color(_ name: String) -> NSColor {
    let hex = Int(light[name]!.dropFirst(), radix: 16)!
    return NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                   blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

for file in ["Fraunces.ttf", "Fraunces-Italic.ttf"] {
    CTFontManagerRegisterFontsForURL(root.appendingPathComponent("fonts/\(file)") as CFURL, .process, nil)
}

/// Fraunces, soft and never wonky, like the app (Typography.fraunces).
func fraunces(_ size: CGFloat, weight: CGFloat, italic: Bool = false) -> NSFont {
    var descriptor = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: "Fraunces"] as CFDictionary)
    if italic { descriptor = CTFontDescriptorCreateCopyWithSymbolicTraits(descriptor, .traitItalic, .traitItalic) ?? descriptor }
    func axis(_ tag: String) -> NSNumber { NSNumber(value: tag.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }) }
    descriptor = CTFontDescriptorCreateCopyWithAttributes(descriptor, [kCTFontVariationAttribute: [
        axis("wght"): weight, axis("opsz"): min(max(size, 9), 144), axis("SOFT"): 100, axis("WONK"): 0,
    ]] as CFDictionary)
    return CTFontCreateWithFontDescriptor(descriptor, size, nil) as NSFont
}

func mono(_ size: CGFloat) -> NSFont { .monospacedSystemFont(ofSize: size, weight: .medium) }

// MARK: Drawing (top-left coordinates, like Finder)

/// Text with its baseline at `y`; `anchor` 0 = left, 0.5 = center, 1 = right of `x`.
func text(_ string: String, x: CGFloat, y: CGFloat, font: NSFont, color: NSColor, anchor: CGFloat = 0, tracking: CGFloat = 0) {
    let attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .kern: tracking])
    let width = attributed.size().width
    NSGraphicsContext.saveGraphicsState()
    // Text draws unflipped: undo the page flip around the baseline.
    let t = NSAffineTransform()
    t.translateX(by: x - width * anchor, yBy: y)
    t.scaleX(by: 1, yBy: -1)
    t.concat()
    attributed.draw(at: .zero)
    NSGraphicsContext.restoreGraphicsState()
}

/// A postage stamp: a card with perforation bitten out of every edge, softly shadowed.
func stamp(_ rect: CGRect) {
    let path = NSBezierPath(rect: rect)
    let r = CGFloat(perforation["hole"]!), pitch = CGFloat(perforation["pitch"]!)
    for (a, b) in [(CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY)),
                   (CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)),
                   (CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY)),
                   (CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY))] {
        let count = max(2, Int((hypot(b.x - a.x, b.y - a.y) / pitch).rounded()))
        for i in 1..<count {
            let t = CGFloat(i) / CGFloat(count)
            path.appendOval(in: CGRect(x: a.x + (b.x - a.x) * t - r, y: a.y + (b.y - a.y) * t - r, width: r * 2, height: r * 2))
        }
    }
    path.windingRule = .evenOdd
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color("shadow").withAlphaComponent(0.14)
    shadow.shadowBlurRadius = 10
    shadow.shadowOffset = NSSize(width: 0, height: -6) // down, in the flipped page
    shadow.set()
    color("card").setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
}

/// Paper grain: faint noise over the whole page.
func grain(in rect: CGRect, scale: CGFloat) {
    let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!
        .cropped(to: CGRect(x: 0, y: 0, width: rect.width * scale, height: rect.height * scale))
    let mono = noise.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
    let context = CIContext()
    guard let cg = context.createCGImage(mono, from: mono.extent) else { return }
    NSGraphicsContext.current?.cgContext.saveGState()
    NSGraphicsContext.current?.cgContext.setAlpha(0.035)
    NSGraphicsContext.current?.cgContext.setBlendMode(.multiply)
    NSGraphicsContext.current?.cgContext.draw(cg, in: rect)
    NSGraphicsContext.current?.cgContext.restoreGState()
}

func render(scale: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let flip = NSAffineTransform(); flip.translateX(by: 0, yBy: size.height); flip.scaleX(by: 1, yBy: -1); flip.concat()

    let page = CGRect(origin: .zero, size: size)
    color("paper").setFill()
    page.fill()
    grain(in: page, scale: scale)

    // Title block.
    text("A QUIET SCREENSHOT TOOL FOR MAC", x: 40, y: 38, font: mono(11), color: color("ink3"), tracking: 1.1)
    text("MACOS 14+ · APPLE SILICON", x: size.width - 40, y: 38, font: mono(11), color: color("ink3"), anchor: 1, tracking: 1.1)
    text("Install Glassine", x: 39, y: 72, font: fraunces(30, weight: 440), color: color("ink"), tracking: -0.3)

    // Each icon on a stamp; Finder puts the name under the icon, inside the stamp.
    for center in [appCenter, appsCenter] {
        stamp(CGRect(x: center.x - 76, y: center.y - 76, width: 152, height: 172))
    }

    // A perforated line between them, ending in an ink arrowhead.
    let y = appCenter.y, from = appCenter.x + 96, to = appsCenter.x - 96
    color("ink3").setFill()
    let dots = Int((to - 12 - from) / 7)
    for i in 0...dots {
        let x = from + CGFloat(i) * (to - 12 - from) / CGFloat(dots)
        NSBezierPath(ovalIn: CGRect(x: x - 1.6, y: y - 1.6, width: 3.2, height: 3.2)).fill()
    }
    let head = NSBezierPath()
    head.move(to: CGPoint(x: to - 9, y: y - 7))
    head.line(to: CGPoint(x: to, y: y))
    head.line(to: CGPoint(x: to - 9, y: y + 7))
    head.lineWidth = 2.2
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    color("ink").setStroke()
    head.stroke()

    text("Drag Glassine onto Applications to install", x: size.width / 2, y: 300,
         font: fraunces(16, weight: 440, italic: true), color: color("ink2"), anchor: 0.5)

    // Low enough to hide entirely under Finder's bars when they're on; nothing here is needed.
    text("FREE & OPEN SOURCE · GPLV3", x: size.width / 2, y: 378, font: mono(11), color: color("ink3"), anchor: 0.5, tracking: 1.1)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let dir = URL(fileURLWithPath: CommandLine.arguments[1])
let png = dir.appendingPathComponent("background.png"), png2x = dir.appendingPathComponent("background@2x.png")
try! render(scale: 1).write(to: png)
try! render(scale: 2).write(to: png2x)
// One TIFF with both resolutions: Finder picks the right one for the display.
let tiffutil = Process()
tiffutil.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
tiffutil.arguments = ["-cathidpicheck", png.path, png2x.path, "-out", dir.appendingPathComponent("background.tiff").path]
try! tiffutil.run()
tiffutil.waitUntilExit()
print("background.png, background@2x.png, background.tiff in \(dir.path)")
