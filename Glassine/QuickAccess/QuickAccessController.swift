import AppKit

/// Stacks capture previews in the bottom-right corner of the screen, newest at the bottom.
@MainActor
final class QuickAccessController {
    private var panels: [QuickAccessPanel] = [] // oldest first
    private var screen: NSScreen?

    private let margin: CGFloat = 16
    private let spacing: CGFloat = 12
    private let maxVisible = 5

    var onPin: (CapturedImage) -> Void = { _ in }

    func show(_ capture: CapturedImage, on screen: NSScreen) {
        let seconds = UserDefaults.standard.integer(forKey: PrefKey.quickAccessAutoClose)
        let panel = QuickAccessPanel(
            capture: capture,
            autoClose: seconds > 0 ? .seconds(seconds) : nil,
            onPin: { [weak self] in self?.onPin($0) }
        ) { [weak self] closed in
            self?.remove(closed)
        }

        self.screen = screen
        panels.append(panel)
        if panels.count > maxVisible {
            panels.first?.dismiss()
        }

        // The new panel slides in from the screen edge while older ones move up.
        // Everything moves in one animation group: a separate non-animated move
        // would be overridden by a slide-in that is still running.
        guard let target = targetFrames()[ObjectIdentifier(panel)] else { return }
        panel.setFrame(target.offsetBy(dx: target.width + margin, dy: 0), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            layout()
        }
    }

    private func remove(_ panel: QuickAccessPanel) {
        panels.removeAll { $0 === panel }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            layout()
        }
    }

    /// Animates every panel to its slot; call inside an animation group.
    private func layout() {
        let frames = targetFrames()
        for panel in panels {
            if let frame = frames[ObjectIdentifier(panel)] {
                panel.animator().setFrame(frame, display: true)
            }
        }
    }

    private func targetFrames() -> [ObjectIdentifier: NSRect] {
        guard let visible = (screen ?? NSScreen.main)?.visibleFrame else { return [:] }
        let frames = QuickAccessLayout.stackFrames(
            sizes: panels.map(\.frame.size), in: visible, margin: margin, spacing: spacing
        )
        return Dictionary(uniqueKeysWithValues: zip(panels.map(ObjectIdentifier.init), frames))
    }
}
