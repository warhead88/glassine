// Renders the DMG window background (1x and 2x) for scripts/release.sh:
//   swift Design/tools/dmg-background.swift Design/dmg
import AppKit

let size = CGSize(width: 640, height: 400)
let appCenter = CGPoint(x: 170, y: 150), appsCenter = CGPoint(x: 470, y: 150) // match release.sh

func render(scale: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // Flip so coordinates match Finder's (top-left origin).
    let flip = NSAffineTransform(); flip.translateX(by: 0, yBy: size.height); flip.scaleX(by: 1, yBy: -1); flip.concat()

    NSGradient(starting: NSColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1),
               ending: NSColor(srgbRed: 0.91, green: 0.91, blue: 0.94, alpha: 1))!
        .draw(in: CGRect(origin: .zero, size: size), angle: 90)

    // Arrow from the app to Applications.
    let y = appCenter.y, from = appCenter.x + 80, to = appsCenter.x - 80
    let arrow = NSBezierPath()
    arrow.move(to: CGPoint(x: from, y: y))
    arrow.line(to: CGPoint(x: to - 14, y: y))
    arrow.lineWidth = 4
    arrow.lineCapStyle = .round
    NSColor(white: 0.62, alpha: 1).setStroke()
    arrow.stroke()
    let head = NSBezierPath()
    head.move(to: CGPoint(x: to, y: y))
    head.line(to: CGPoint(x: to - 18, y: y - 11))
    head.line(to: CGPoint(x: to - 18, y: y + 11))
    head.close()
    NSColor(white: 0.62, alpha: 1).setFill()
    head.fill()

    // Caption under the icon names, above where Finder may put its path and status bars.
    let caption = NSAttributedString(string: "Drag Glassine to Applications to install", attributes: [
        .font: NSFont.systemFont(ofSize: 13, weight: .medium),
        .foregroundColor: NSColor(white: 0.45, alpha: 1),
    ])
    let captionSize = caption.size()
    NSGraphicsContext.saveGraphicsState()
    // Text must be drawn unflipped.
    let unflip = NSAffineTransform(); unflip.translateX(by: 0, yBy: size.height); unflip.scaleX(by: 1, yBy: -1); unflip.concat()
    caption.draw(at: CGPoint(x: (size.width - captionSize.width) / 2, y: size.height - 262 - captionSize.height))
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let dir = URL(fileURLWithPath: CommandLine.arguments[1])
try! render(scale: 1).write(to: dir.appendingPathComponent("background.png"))
try! render(scale: 2).write(to: dir.appendingPathComponent("background@2x.png"))
