// Renders the letter G in candidate fonts as a comparison sheet, and exports
// a chosen variant as an SVG outline.
//
//   swift glyphs.swift sheet <fontsDir> <out.png>
//   swift glyphs.swift svg <fontFile|system:Name> <wght> <out.svg> [opsz] [soft] [wonk]
import AppKit
import CoreText

struct Variant {
    let label: String
    let source: String          // file name in fontsDir, or "system:<PostScript name>"
    var axes: [String: CGFloat] = [:]
}

func tag(_ s: String) -> Int {
    s.unicodeScalars.reduce(0) { ($0 << 8) | Int($1.value) }
}

func makeFont(_ source: String, dir: String, axes: [String: CGFloat], size: CGFloat) -> CTFont {
    if source.hasPrefix("system:") {
        return CTFontCreateWithName(String(source.dropFirst(7)) as CFString, size, nil)
    }
    let url = URL(fileURLWithPath: dir).appendingPathComponent(source) as CFURL
    let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url) as! [CTFontDescriptor]
    var descriptor = descriptors[0]
    if !axes.isEmpty {
        var variation: [NSNumber: NSNumber] = [:]
        for (key, value) in axes { variation[NSNumber(value: tag(key))] = NSNumber(value: Double(value)) }
        descriptor = CTFontDescriptorCreateCopyWithAttributes(
            descriptor, [kCTFontVariationAttribute: variation] as CFDictionary)
    }
    return CTFontCreateWithFontDescriptor(descriptor, size, nil)
}

/// Path of "G", scaled and centered (by its bounding box) inside `box`, with y up.
func glyphPath(_ font: CTFont, in box: CGRect, fill: CGFloat) -> CGPath {
    var chars: [UniChar] = Array("G".utf16)
    var glyphs = [CGGlyph](repeating: 0, count: 1)
    CTFontGetGlyphsForCharacters(font, &chars, &glyphs, 1)
    let raw = CTFontCreatePathForGlyph(font, glyphs[0], nil)!
    let bounds = raw.boundingBoxOfPath
    let scale = min(box.width * fill / bounds.width, box.height * fill / bounds.height)
    var t = CGAffineTransform(translationX: box.midX, y: box.midY)
        .scaledBy(x: scale, y: scale)
        .translatedBy(x: -bounds.midX, y: -bounds.midY)
    return raw.copy(using: &t)!
}

let background = CGColor(red: 0x1a / 255.0, green: 0x1a / 255.0, blue: 0x1a / 255.0, alpha: 1)
let letter = CGColor(gray: 0.8, alpha: 1)

func sheet(dir: String, out: String) {
    let variants: [Variant] = [
        Variant(label: "Apple Chancery (current)", source: "system:Apple-Chancery"),
        Variant(label: "Lora Italic 500", source: "Lora-Italic.ttf", axes: ["wght": 500]),
        Variant(label: "Lora Italic 700", source: "Lora-Italic.ttf", axes: ["wght": 700]),
        Variant(label: "Fraunces Italic 400", source: "Fraunces-Italic.ttf", axes: ["wght": 400, "opsz": 144]),
        Variant(label: "Fraunces Italic 600 soft", source: "Fraunces-Italic.ttf", axes: ["wght": 600, "opsz": 144, "SOFT": 100]),
        Variant(label: "Fraunces Italic 400 soft", source: "Fraunces-Italic.ttf", axes: ["wght": 400, "opsz": 144, "SOFT": 100]),
        Variant(label: "Playfair Display Italic 400", source: "PlayfairDisplay-Italic.ttf", axes: ["wght": 400]),
        Variant(label: "Playfair Display Italic 700", source: "PlayfairDisplay-Italic.ttf", axes: ["wght": 700]),
        Variant(label: "EB Garamond Italic 500", source: "EBGaramond-Italic.ttf", axes: ["wght": 500]),
        Variant(label: "EB Garamond Italic 700", source: "EBGaramond-Italic.ttf", axes: ["wght": 700]),
        Variant(label: "Instrument Serif Italic", source: "InstrumentSerif-Italic.ttf"),
    ]
    let cell: CGFloat = 300, labelH: CGFloat = 34, cols = 4
    let rows = (variants.count + cols - 1) / cols
    let width = Int(cell) * cols, height = Int(cell + labelH) * rows
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(gray: 0.35, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

    for (i, v) in variants.enumerated() {
        let col = i % cols, row = i / cols
        let x = CGFloat(col) * cell
        let y = CGFloat(height) - CGFloat(row + 1) * (cell + labelH) + labelH
        let tile = CGRect(x: x + 4, y: y + 4, width: cell - 8, height: cell - 8)
        ctx.setFillColor(background)
        ctx.addPath(CGPath(roundedRect: tile, cornerWidth: 54, cornerHeight: 54, transform: nil))
        ctx.fillPath()

        let font = makeFont(v.source, dir: dir, axes: v.axes, size: 400)
        ctx.setFillColor(letter)
        ctx.addPath(glyphPath(font, in: tile, fill: 0.62))
        ctx.fillPath()

        // Actual small sizes as they'd appear in Finder lists and menus.
        for (n, s) in [CGFloat(16), 32].enumerated() {
            let small = CGRect(x: tile.maxX - 10 - CGFloat(n + 1) * 40, y: tile.minY + 10, width: s, height: s)
            ctx.setFillColor(background)
            ctx.addPath(CGPath(roundedRect: small, cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil))
            ctx.fillPath()
            ctx.setStrokeColor(CGColor(gray: 0.5, alpha: 1))
            ctx.setLineWidth(1)
            ctx.addPath(CGPath(roundedRect: small, cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil))
            ctx.strokePath()
            ctx.setFillColor(letter)
            ctx.addPath(glyphPath(font, in: small, fill: 0.62))
            ctx.fillPath()
        }

        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: NSColor.white]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "\(i + 1). \(v.label)", attributes: attrs))
        ctx.textPosition = CGPoint(x: x + 8, y: y - 24)
        CTLineDraw(line, ctx)
    }
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
}

/// Writes the glyph as filled outlines in a 1024×1024 SVG (y down), transparent background.
func svg(source: String, axes: [String: CGFloat], out: String) {
    let dir = URL(fileURLWithPath: source).deletingLastPathComponent().path
    let file = source.hasPrefix("system:") ? source : URL(fileURLWithPath: source).lastPathComponent
    let font = makeFont(file, dir: dir, axes: axes, size: 1000)
    let canvas = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    var flip = CGAffineTransform(translationX: 0, y: 1024).scaledBy(x: 1, y: -1)
    let path = glyphPath(font, in: canvas, fill: 0.62).copy(using: &flip)!

    var d = ""
    path.applyWithBlock { element in
        let p = element.pointee.points
        func f(_ pt: CGPoint) -> String { String(format: "%.2f %.2f", pt.x, pt.y) }
        switch element.pointee.type {
        case .moveToPoint: d += "M\(f(p[0]))"
        case .addLineToPoint: d += "L\(f(p[0]))"
        case .addQuadCurveToPoint: d += "Q\(f(p[0])) \(f(p[1]))"
        case .addCurveToPoint: d += "C\(f(p[0])) \(f(p[1])) \(f(p[2]))"
        case .closeSubpath: d += "Z"
        @unknown default: break
        }
    }
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
      <path fill="#cccccc" fill-rule="nonzero" d="\(d)"/>
    </svg>

    """
    try! svg.write(toFile: out, atomically: true, encoding: .utf8)
}

let args = CommandLine.arguments
switch args[1] {
case "sheet":
    sheet(dir: args[2], out: args[3])
case "svg":
    var axes: [String: CGFloat] = [:]
    if let w = Double(args[3]), w > 0 { axes["wght"] = w }
    if args.count > 5 { axes["opsz"] = CGFloat(Double(args[5])!) }
    if args.count > 6 { axes["SOFT"] = CGFloat(Double(args[6])!) }
    if args.count > 7 { axes["WONK"] = CGFloat(Double(args[7])!) }
    svg(source: args[2], axes: axes, out: args[4])
default:
    print("usage: sheet <dir> <out.png> | svg <font> <wght> <out.svg> [opsz] [soft] [wonk]")
}
