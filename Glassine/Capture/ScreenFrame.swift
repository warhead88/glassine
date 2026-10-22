import AppKit

/// The white frame around the screen in area capture.
enum AreaFrameStyle: String, CaseIterable, Identifiable {
    /// A rounded rectangle along the screen edge.
    case straight
    /// Along the edge, dipping under the camera notch on displays that have one.
    case notch

    var id: Self { self }

    var title: String {
        switch self {
        case .straight: "Straight"
        case .notch: "Around the notch"
        }
    }
}

enum ScreenFrame {
    static let topRadius: CGFloat = 20
    static let bottomRadius: CGFloat = 14
    /// Notch bottom corners (the cut-out's own rounding) and its shoulders where it meets the edge.
    static let notchRadius: CGFloat = 10
    static let shoulderRadius: CGFloat = 6

    /// The notch in the screen's flipped local coordinates (top-left origin), from the unobscured
    /// areas macOS reports on either side of it. Nil on displays without a notch.
    static func notchRect(screenFrame: CGRect, topInset: CGFloat, leftArea: CGRect?, rightArea: CGRect?) -> CGRect? {
        guard topInset > 0, let leftArea, let rightArea, rightArea.minX > leftArea.maxX else { return nil }
        return CGRect(x: leftArea.maxX - screenFrame.minX, y: 0, width: rightArea.minX - leftArea.maxX, height: topInset)
    }

    /// Frame path inset by `inset` from the screen edge (flipped: y grows downward). With a notch,
    /// the top edge runs `inset` outside the notch's sides and bottom.
    static func path(in bounds: CGRect, inset: CGFloat, notch: CGRect?) -> CGPath {
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let top = topRadius, bottom = bottomRadius
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX + top, y: rect.minY))

        if let notch {
            let left = notch.minX - inset, right = notch.maxX + inset, under = notch.maxY + inset
            let shoulder = min(shoulderRadius, max(under - rect.minY, 0) / 2)
            let corner = min(notchRadius, (right - left) / 2, max(under - rect.minY - shoulder, 0))
            path.addLine(to: CGPoint(x: left - shoulder, y: rect.minY))
            path.addArc(tangent1End: CGPoint(x: left, y: rect.minY), tangent2End: CGPoint(x: left, y: under), radius: shoulder)
            path.addArc(tangent1End: CGPoint(x: left, y: under), tangent2End: CGPoint(x: right, y: under), radius: corner)
            path.addArc(tangent1End: CGPoint(x: right, y: under), tangent2End: CGPoint(x: right, y: rect.minY), radius: corner)
            path.addArc(tangent1End: CGPoint(x: right, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: shoulder)
        }

        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + top), radius: top)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottom))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - bottom, y: rect.maxY), radius: bottom)
        path.addLine(to: CGPoint(x: rect.minX + bottom, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - bottom), radius: bottom)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + top))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + top, y: rect.minY), radius: top)
        path.closeSubpath()
        return path
    }
}

extension NSScreen {
    /// The camera notch in this screen's flipped local coordinates, if it has one.
    var notchRect: CGRect? {
        ScreenFrame.notchRect(screenFrame: frame, topInset: safeAreaInsets.top,
                              leftArea: auxiliaryTopLeftArea, rightArea: auxiliaryTopRightArea)
    }
}
