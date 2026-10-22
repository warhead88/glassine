import CoreGraphics
import Foundation

// Pure geometry used by the overlay, previews and pins. Kept free of AppKit state
// so it can be unit-tested (see GlassineTests).

/// Selection math in the overlay's coordinates: points, flipped (top-left origin).
enum SelectionGeometry {
    enum Handle: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    }

    /// Rect dragged from `anchor` to `point`. Square: equal sides; from center: `anchor` is the middle.
    static func rect(anchor: CGPoint, point: CGPoint, square: Bool, fromCenter: Bool) -> CGRect {
        var dx = point.x - anchor.x
        var dy = point.y - anchor.y
        if square {
            let side = max(abs(dx), abs(dy))
            dx = dx < 0 ? -side : side
            dy = dy < 0 ? -side : side
        }
        if fromCenter {
            return CGRect(x: anchor.x - abs(dx), y: anchor.y - abs(dy), width: abs(dx) * 2, height: abs(dy) * 2)
        }
        return CGRect(x: min(anchor.x, anchor.x + dx), y: min(anchor.y, anchor.y + dy), width: abs(dx), height: abs(dy))
    }

    /// Moves the edges a handle controls; dragging past the opposite edge flips the rect.
    static func resized(_ rect: CGRect, handle: Handle, dx: CGFloat, dy: CGFloat) -> CGRect {
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        switch handle {
        case .topLeft: minX += dx; minY += dy
        case .top: minY += dy
        case .topRight: maxX += dx; minY += dy
        case .right: maxX += dx
        case .bottomRight: maxX += dx; maxY += dy
        case .bottom: maxY += dy
        case .bottomLeft: minX += dx; maxY += dy
        case .left: minX += dx
        }
        return CGRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))
    }

    static func handlePoint(_ handle: Handle, of rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .top: CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .right: CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .left: CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    static func handle(at point: CGPoint, of rect: CGRect, tolerance: CGFloat = 8) -> Handle? {
        Handle.allCases.first {
            let p = handlePoint($0, of: rect)
            return hypot(p.x - point.x, p.y - point.y) <= tolerance
        }
    }

    /// Resizes from a corner keeping the aspect ratio; the opposite corner stays put and the rect
    /// stays inside `bounds`. Edge handles leave the rect as it is.
    static func resizedKeepingAspect(_ rect: CGRect, handle: Handle, dx: CGFloat, in bounds: CGRect,
                                     minWidth: CGFloat) -> CGRect {
        let right = handle == .topRight || handle == .bottomRight
        let down = handle == .bottomLeft || handle == .bottomRight
        guard right || handle == .topLeft || handle == .bottomLeft, rect.height > 0 else { return rect }
        let aspect = rect.width / rect.height
        let anchor = CGPoint(x: right ? rect.minX : rect.maxX, y: down ? rect.minY : rect.maxY)
        let roomX = right ? bounds.maxX - anchor.x : anchor.x - bounds.minX
        let roomY = down ? bounds.maxY - anchor.y : anchor.y - bounds.minY
        let width = min(max(rect.width + (right ? dx : -dx), minWidth), roomX, roomY * aspect)
        let height = width / aspect
        return CGRect(x: right ? anchor.x : anchor.x - width, y: down ? anchor.y : anchor.y - height,
                      width: width, height: height)
    }

    /// Whether `point` is within `tolerance` of the rect's outline.
    static func isOnBorder(_ point: CGPoint, of rect: CGRect, tolerance: CGFloat = 6) -> Bool {
        rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
            && !rect.insetBy(dx: tolerance, dy: tolerance).contains(point)
    }

    /// A freely resized rect inside `bounds`, at least `minSize`.
    static func limited(_ rect: CGRect, in bounds: CGRect, minSize: CGSize) -> CGRect {
        var rect = rect.intersection(bounds)
        if rect.isNull { rect = CGRect(origin: bounds.origin, size: .zero) }
        rect.size.width = max(rect.width, minSize.width)
        rect.size.height = max(rect.height, minSize.height)
        return fitted(rect, in: bounds)
    }

    static func clamped(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
    }

    /// Keeps a moved rect inside `bounds` without changing its size.
    static func fitted(_ rect: CGRect, in bounds: CGRect) -> CGRect {
        var rect = rect
        rect.origin.x = min(max(rect.minX, bounds.minX), bounds.maxX - rect.width)
        rect.origin.y = min(max(rect.minY, bounds.minY), bounds.maxY - rect.height)
        return rect
    }

    /// Converts a selection in view points to whole image pixels (covering every touched pixel).
    static func pixelRect(_ rect: CGRect, viewSize: CGSize, imageSize: CGSize) -> CGRect {
        let sx = imageSize.width / viewSize.width
        let sy = imageSize.height / viewSize.height
        return CGRect(x: rect.minX * sx, y: rect.minY * sy, width: rect.width * sx, height: rect.height * sy).integral
    }

    /// The image pixel under a view point, clamped to the image.
    static func pixelPoint(_ point: CGPoint, viewSize: CGSize, imageSize: CGSize) -> CGPoint {
        let sx = imageSize.width / viewSize.width
        let sy = imageSize.height / viewSize.height
        return CGPoint(
            x: min(max(floor(point.x * sx), 0), imageSize.width - 1),
            y: min(max(floor(point.y * sy), 0), imageSize.height - 1)
        )
    }
}

/// Conversions between the three coordinate systems Glassine meets:
/// - global top-left: CoreGraphics window bounds, origin at the primary display's top-left;
/// - global Cocoa: NSWindow/NSScreen frames, origin at the primary display's bottom-left;
/// - local flipped: one screen's overlay view, origin at that screen's top-left.
enum ScreenGeometry {
    static func localFlipped(fromGlobalTopLeft rect: CGRect, screenFrame: CGRect, primaryHeight: CGFloat) -> CGRect {
        let screenTop = primaryHeight - screenFrame.maxY
        return rect.offsetBy(dx: -screenFrame.minX, dy: -screenTop)
    }

    static func localFlipped(fromGlobalCocoa rect: CGRect, screenFrame: CGRect) -> CGRect {
        CGRect(x: rect.minX - screenFrame.minX, y: screenFrame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    static func globalCocoa(fromLocalFlipped rect: CGRect, screenFrame: CGRect) -> CGRect {
        CGRect(x: screenFrame.minX + rect.minX, y: screenFrame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    static func globalCocoa(fromGlobalTopLeft rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

/// Layout of capture previews in the screen corner.
enum QuickAccessLayout {
    static let maxSize = CGSize(width: 220, height: 150)
    static let minSize = CGSize(width: 140, height: 90)

    /// Tall enough for three buttons (Copy, Save, QR) clear of the corner buttons.
    static let minHeightWithQR: CGFloat = 150

    /// Fits the capture into `maxSize`, never upscaling, but never smaller than the controls need.
    static func thumbnailSize(for size: CGSize, hasQR: Bool = false) -> CGSize {
        let fit = min(maxSize.width / max(size.width, 1), maxSize.height / max(size.height, 1), 1)
        return CGSize(
            width: max((size.width * fit).rounded(), minSize.width),
            height: max((size.height * fit).rounded(), hasQR ? minHeightWithQR : minSize.height)
        )
    }

    /// Frames for a stack in the bottom-right corner of `visible`; `sizes` are oldest first,
    /// and the newest sits at the bottom.
    static func stackFrames(sizes: [CGSize], in visible: CGRect, margin: CGFloat, spacing: CGFloat) -> [CGRect] {
        var frames = [CGRect](repeating: .zero, count: sizes.count)
        var y = visible.minY + margin
        for index in sizes.indices.reversed() {
            let size = sizes[index]
            frames[index] = CGRect(x: visible.maxX - margin - size.width, y: y, width: size.width, height: size.height)
            y += size.height + spacing
        }
        return frames
    }
}

/// Placement and zoom of pins, in global Cocoa coordinates.
enum PinGeometry {
    static let maxZoom: CGFloat = 8

    /// Smallest zoom that keeps both sides at least 40 pt (and never below 5 %).
    static func minZoom(natural: CGSize) -> CGFloat {
        max(40 / natural.width, 40 / natural.height, 0.05)
    }

    static func clampedZoom(_ zoom: CGFloat, natural: CGSize) -> CGFloat {
        min(max(zoom, minZoom(natural: natural)), maxZoom)
    }

    /// Resizes `frame` to `size` keeping the point at `anchor` fixed relative to the content.
    static func zoomedFrame(_ frame: CGRect, to size: CGSize, anchor: CGPoint) -> CGRect {
        let fx = (anchor.x - frame.minX) / frame.width
        let fy = (anchor.y - frame.minY) / frame.height
        return CGRect(x: anchor.x - fx * size.width, y: anchor.y - fy * size.height, width: size.width, height: size.height)
    }

    /// Actual size centered over where the content was (or the screen center), scaled down to
    /// 90 % of the visible area if needed and moved fully on screen.
    static func initialPlacement(natural: CGSize, source: CGRect?, visible: CGRect) -> (center: CGPoint, zoom: CGFloat) {
        let zoom = min(visible.width * 0.9 / natural.width, visible.height * 0.9 / natural.height, 1)
        let size = CGSize(width: natural.width * zoom, height: natural.height * zoom)
        var center = source.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: visible.midX, y: visible.midY)
        center.x = min(max(center.x, visible.minX + size.width / 2), visible.maxX - size.width / 2)
        center.y = min(max(center.y, visible.minY + size.height / 2), visible.maxY - size.height / 2)
        return (center, zoom)
    }
}

/// File names for saved captures.
enum FileNaming {
    /// The user's prefix, trimmed, with path separators and colons replaced; "Glassine" if empty.
    static func sanitizedPrefix(_ raw: String?) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespaces) ?? ""
        let cleaned = trimmed.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return cleaned.isEmpty ? "Glassine" : cleaned
    }

    /// e.g. "Glassine 2026-10-21 at 19.53.06" (Finder-style, sortable, no colons).
    static func baseName(prefix: String, date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "\(prefix) \(formatter.string(from: date))"
    }

    /// First free name: "base.ext", then "base (2).ext", "base (3).ext"…
    static func uniqueURL(in folder: URL, baseName: String, fileExtension: String, exists: (URL) -> Bool) -> URL {
        var url = folder.appending(path: "\(baseName).\(fileExtension)")
        var index = 2
        while exists(url) {
            url = folder.appending(path: "\(baseName) (\(index)).\(fileExtension)")
            index += 1
        }
        return url
    }
}
