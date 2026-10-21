import AppKit
import ScreenCaptureKit

/// A frozen, full-resolution image of one screen.
struct ScreenSnapshot {
    let screen: NSScreen
    let image: CGImage
    var scale: CGFloat { screen.backingScaleFactor }
}

enum ScreenSnapshotter {
    /// Captures every connected screen at native pixel resolution, without the cursor
    /// and without Glassine's own windows (previews, settings).
    @MainActor
    static func snapshotAllScreens() async throws -> [ScreenSnapshot] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownApps = content.applications.filter { $0.processID == ownPID }

        var snapshots: [ScreenSnapshot] = []
        for screen in NSScreen.screens {
            guard let displayID = screen.displayID,
                  let display = content.displays.first(where: { $0.displayID == displayID })
            else { continue }

            let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.width = Int(screen.frame.width * screen.backingScaleFactor)
            config.height = Int(screen.frame.height * screen.backingScaleFactor)
            config.showsCursor = false
            config.captureResolution = .best

            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            snapshots.append(ScreenSnapshot(screen: screen, image: image))
        }
        return snapshots
    }

    /// Captures a single window by itself (even if partly covered), on a transparent background.
    /// Returns the image and its pixels-per-point scale.
    @MainActor
    static func captureWindow(id: CGWindowID, includeShadow: Bool) async throws -> (CGImage, CGFloat) {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == id }) else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "The window is no longer available."])
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let info = SCShareableContent.info(for: filter)
        let scale = CGFloat(info.pointPixelScale)

        let config = SCStreamConfiguration()
        config.ignoreShadowsSingleWindow = !includeShadow
        config.width = Int(info.contentRect.width * scale)
        config.height = Int(info.contentRect.height * scale)
        config.showsCursor = false
        config.captureResolution = .best

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return (image, scale)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
