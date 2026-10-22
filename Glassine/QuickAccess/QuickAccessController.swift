import AppKit

/// Stacks capture and recording previews in the bottom-right corner of the screen, newest at the bottom.
@MainActor
final class QuickAccessController {
    private var panels: [PreviewPanel] = [] // oldest first
    private var screen: NSScreen?

    private let margin: CGFloat = 16
    private let spacing: CGFloat = 12
    private let maxVisible = 5

    var onPin: (CapturedImage) -> Void = { _ in }
    var onEdit: (CapturedImage) -> Void = { _ in }

    func show(_ capture: CapturedImage, on screen: NSScreen) {
        present(QuickAccessPanel(
            capture: capture,
            autoClose: autoClose,
            onPin: { [weak self] in self?.onPin($0) },
            onEdit: { [weak self] in self?.onEdit($0) },
            onResize: { [weak self] _ in self?.relayout() },
            onClose: { [weak self] in self?.remove($0) }
        ), on: screen)
    }

    func show(_ recording: CapturedRecording, on screen: NSScreen) {
        present(RecordingPreviewPanel(recording: recording, autoClose: autoClose) { [weak self] in
            self?.remove($0)
        }, on: screen)
    }

    private var autoClose: Duration? {
        let seconds = UserDefaults.standard.integer(forKey: PrefKey.quickAccessAutoClose)
        return seconds > 0 ? .seconds(seconds) : nil
    }

    private func present(_ panel: PreviewPanel, on screen: NSScreen) {
        self.screen = screen
        panels.append(panel)
        // The oldest go when there are too many, or when the stack would run off the screen.
        let fitting = QuickAccessLayout.fittingCount(sizes: panels.map(\.preferredSize), height: screen.visibleFrame.height,
                                                     margin: margin, spacing: spacing)
        for old in panels.prefix(panels.count - min(fitting, maxVisible)) {
            old.dismiss()
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

    private func relayout() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            layout()
        }
    }

    private func remove(_ panel: PreviewPanel) {
        panels.removeAll { $0 === panel }
        relayout()
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
            sizes: panels.map(\.preferredSize), in: visible, margin: margin, spacing: spacing
        )
        return Dictionary(uniqueKeysWithValues: zip(panels.map(ObjectIdentifier.init), frames))
    }
}
