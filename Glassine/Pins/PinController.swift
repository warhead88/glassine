import AppKit

/// Owns all pins: creating them from captures or the clipboard, hiding and closing them,
/// and letting click-through pins become interactive while ⌥⌘ is held.
@MainActor
final class PinController {
    private var pins: [PinPanel] = []
    private var areHidden = false
    private var modifierPoll: Timer?

    var hasPins: Bool { !pins.isEmpty }

    var onEdit: (CapturedImage) -> Void = { _ in }

    func pin(_ capture: CapturedImage) {
        let screen = screenForNewPin(capture)
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let placement = PinGeometry.initialPlacement(natural: capture.pointSize, source: capture.sourceFrame, visible: visible)

        if areHidden { setHidden(false) }
        let panel = PinPanel(capture: capture, center: placement.center, zoom: placement.zoom, controller: self)
        pins.append(panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
    }

    /// Pins whatever image is on the clipboard; beeps if there is none.
    func pinFromClipboard() {
        guard let image = NSImage(pasteboard: .general),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            NSSound.beep()
            return
        }
        let scale = image.size.width > 0 ? CGFloat(cgImage.width) / image.size.width : 1
        do {
            pin(try CapturedImage(image: cgImage, scale: max(scale, 1)))
        } catch {
            Alerts.present(error)
        }
    }

    func toggleVisibility() {
        guard hasPins else {
            NSSound.beep()
            return
        }
        setHidden(!areHidden)
    }

    func close(_ pin: PinPanel) {
        pins.removeAll { $0 === pin }
        pin.orderOut(nil)
        clickThroughDidChange()
    }

    func closeAll() {
        pins.forEach { $0.orderOut(nil) }
        pins.removeAll()
        areHidden = false
        clickThroughDidChange()
    }

    private func setHidden(_ hidden: Bool) {
        areHidden = hidden
        for pin in pins {
            if hidden { pin.orderOut(nil) } else { pin.orderFrontRegardless() }
        }
    }

    private func screenForNewPin(_ capture: CapturedImage) -> NSScreen? {
        if let source = capture.sourceFrame,
           let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: source.midX, y: source.midY)) }) {
            return screen
        }
        return NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
    }

    #if DEBUG
    /// Debug hook (`--debug-pins [hover]`): pins two crops of the main screen, one zoomed out at
    /// 50% opacity, without the hotkey or touching the clipboard and save folder. `hover` shows the
    /// close buttons and the first pin's ⌥⌘ ring.
    func showDebugPins() {
        Task {
            guard let snapshot = try? await ScreenSnapshotter.snapshotAllScreens().first else { return }
            let w = snapshot.image.width, h = snapshot.image.height
            for (index, crop) in [CGRect(x: w / 8, y: h / 8, width: w / 4, height: h / 4),
                                  CGRect(x: w / 2, y: h / 2, width: w / 3, height: h / 3)].enumerated() {
                guard let image = snapshot.image.cropping(to: crop),
                      let capture = try? CapturedImage(image: image, scale: snapshot.scale) else { continue }
                capture.sourceFrame = snapshot.screen.globalRect(fromLocalFlipped: CGRect(
                    x: crop.minX / snapshot.scale, y: crop.minY / snapshot.scale,
                    width: crop.width / snapshot.scale, height: crop.height / snapshot.scale
                ))
                pin(capture)
                if index == 1, let panel = pins.last {
                    panel.setZoom(panel.zoom * 0.6)
                    panel.setOpacity(0.5)
                }
                // `hover`: the first pin as if ⌥⌘ were held over a click-through pin.
                if index == 0, CommandLine.arguments.contains("hover") { pins.last?.setHighlighted(true) }
            }
        }
    }
    #endif

    // MARK: Click-through

    /// A click-through pin ignores the mouse, so there is no way to reach its menu again.
    /// While any exists, poll the modifier keys (no Accessibility permission needed) and
    /// make those pins interactive while ⌥⌘ is held.
    func clickThroughDidChange() {
        let needsPoll = pins.contains { $0.isClickThrough }
        if needsPoll, modifierPoll == nil {
            modifierPoll = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateClickThroughPins() }
            }
        } else if !needsPoll {
            modifierPoll?.invalidate()
            modifierPoll = nil
        }
    }

    private func updateClickThroughPins() {
        let reveal = NSEvent.modifierFlags.intersection([.command, .option]) == [.command, .option]
        for pin in pins where pin.isClickThrough {
            pin.ignoresMouseEvents = !reveal
            pin.setHighlighted(reveal)
        }
    }
}
