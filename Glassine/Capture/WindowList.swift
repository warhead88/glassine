import AppKit

/// An on-screen window the user can capture by clicking it in the overlay.
struct WindowCandidate {
    let id: CGWindowID
    /// Global display coordinates: origin at the top-left of the primary display, in points.
    let frame: CGRect
}

enum WindowList {
    /// Normal app windows, front to back, excluding Glassine's own.
    static func onScreenWindows() -> [WindowCandidate] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        return info.compactMap { entry in
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  (entry[kCGWindowOwnerPID as String] as? pid_t) != ownPID,
                  (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let id = entry[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  frame.width >= 40, frame.height >= 40
            else { return nil }
            return WindowCandidate(id: id, frame: frame)
        }
    }

    /// A window's current frame in global Cocoa coordinates (bottom-left origin).
    static func frame(of id: CGWindowID) -> NSRect? {
        guard let entry = (CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]])?.first,
              let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds)
        else { return nil }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }
}

extension NSScreen {
    /// Converts a rect in global display coordinates (top-left origin) into this screen's
    /// local coordinates with a top-left origin, as used by the flipped overlay view.
    func localFlippedRect(fromGlobal rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? frame.height
        let screenTop = primaryHeight - frame.maxY
        return rect.offsetBy(dx: -frame.minX, dy: -screenTop)
    }

    /// Converts a rect in this screen's flipped local coordinates (as used by the overlay)
    /// into global Cocoa coordinates with a bottom-left origin.
    func globalRect(fromLocalFlipped rect: CGRect) -> NSRect {
        NSRect(x: frame.minX + rect.minX, y: frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }
}
