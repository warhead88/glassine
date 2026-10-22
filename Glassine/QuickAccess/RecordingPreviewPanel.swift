import AppKit

/// Preview of a finished recording: its first frame and length. Drag it into any app, copy or
/// save it; a click opens it.
@MainActor
final class RecordingPreviewPanel: PreviewPanel {
    let recording: CapturedRecording

    init(recording: CapturedRecording, autoClose: Duration?, onClose: @escaping (PreviewPanel) -> Void) {
        self.recording = recording
        super.init(size: QuickAccessLayout.thumbnailSize(for: recording.pointSize), autoClose: autoClose, onClose: onClose)
        contentView = RecordingThumbnailView(recording: recording, panel: self)
    }
}

@MainActor
private final class RecordingThumbnailView: NSView, NSDraggingSource {
    private let recording: CapturedRecording
    private unowned let panel: RecordingPreviewPanel

    private let overlay = NSView()
    private lazy var copyButton = PillButton(label: "Copy", target: self, action: #selector(copyFile))
    private lazy var saveButton = PillButton(label: "", target: self, action: #selector(saveOrReveal))
    private lazy var closeButton = FirstMouseButton(
        image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")!,
        target: self, action: #selector(close)
    )
    private var mouseDownPoint: NSPoint?
    private var resetCopyTitle: Task<Void, Never>?

    init(recording: CapturedRecording, panel: RecordingPreviewPanel) {
        self.recording = recording
        self.panel = panel
        super.init(frame: NSRect(origin: .zero, size: panel.frame.size))

        wantsLayer = true
        layer?.contents = recording.thumbnail
        layer?.contentsGravity = .resizeAspect
        layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.95).cgColor
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor

        addSubview(badge())
        setUpOverlay()
        saveButton.setLabel(recording.isSaved ? "Show in Finder" : "Save")

        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// "▶ 0:07" or "GIF 0:07" in the bottom-left corner, always visible.
    private func badge() -> NSView {
        let symbol = NSImageView(image: NSImage(systemSymbolName: recording.format == .gif ? "photo.stack" : "play.fill",
                                                accessibilityDescription: nil)!)
        symbol.symbolConfiguration = .init(pointSize: 9, weight: .bold)
        symbol.contentTintColor = .white
        let label = NSTextField(labelWithString: (recording.format == .gif ? "GIF  " : "") + RecordingMath.clock(recording.duration))
        label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        label.textColor = .white
        let stack = NSStackView(views: [symbol, label])
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 3, left: 6, bottom: 3, right: 7)
        stack.wantsLayer = true
        stack.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        stack.layer?.cornerRadius = 6
        stack.frame.origin = NSPoint(x: 6, y: 6)
        stack.setFrameSize(stack.fittingSize)
        return stack
    }

    private func setUpOverlay() {
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        overlay.alphaValue = 0
        overlay.frame = bounds
        overlay.autoresizingMask = [.width, .height]
        addSubview(overlay)

        let stack = NSStackView(views: [copyButton, saveButton])
        stack.orientation = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(stack)

        closeButton.isBordered = false
        closeButton.contentTintColor = .white
        closeButton.symbolConfiguration = .init(pointSize: 16, weight: .regular)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(closeButton)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            copyButton.widthAnchor.constraint(equalTo: saveButton.widthAnchor),
            closeButton.topAnchor.constraint(equalTo: overlay.topAnchor, constant: 6),
            closeButton.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 6),
        ])
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseEntered(with event: NSEvent) { setHovering(true) }
    override func mouseExited(with event: NSEvent) { setHovering(false) }

    private func setHovering(_ hovering: Bool) {
        panel.setHovering(hovering)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            overlay.animator().alphaValue = hovering ? 1 : 0
        }
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint else { return }
        let point = event.locationInWindow
        guard hypot(point.x - start.x, point.y - start.y) > 4 else { return }
        mouseDownPoint = nil

        let item = NSDraggingItem(pasteboardWriter: recording.url as NSURL)
        item.setDraggingFrame(bounds, contents: recording.thumbnail.map { NSImage(cgImage: $0, size: bounds.size) })
        beginDraggingSession(with: [item], event: event, source: self)
        panel.alphaValue = 0
    }

    override func mouseUp(with event: NSEvent) {
        guard mouseDownPoint != nil else { return }
        mouseDownPoint = nil
        NSWorkspace.shared.open(recording.url)
        panel.dismiss()
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if operation.isEmpty {
            panel.alphaValue = 1
            setHovering(panel.frame.contains(NSEvent.mouseLocation))
        } else {
            panel.dismiss()
        }
    }

    @objc private func copyFile() {
        recording.copyToClipboard()
        copyButton.setLabel("Copied")
        resetCopyTitle?.cancel()
        resetCopyTitle = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            self?.copyButton.setLabel("Copy")
        }
    }

    @objc private func saveOrReveal() {
        do {
            let alreadySaved = recording.isSaved
            let url = try recording.save()
            if alreadySaved {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            saveButton.setLabel("Show in Finder")
        } catch {
            Alerts.present(error)
        }
    }

    @objc private func close() {
        panel.dismiss()
    }
}
