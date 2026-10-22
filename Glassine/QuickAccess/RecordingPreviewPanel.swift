import AppKit

/// Preview of a finished recording: its first frame and length on a stamp. Drag it into any
/// app, copy or save it; a click opens it.
@MainActor
final class RecordingPreviewPanel: PreviewPanel {
    let recording: CapturedRecording

    init(recording: CapturedRecording, autoClose: Duration?, onClose: @escaping (PreviewPanel) -> Void) {
        self.recording = recording
        super.init(size: QuickAccessLayout.stampSize(image: QuickAccessLayout.thumbnailSize(for: recording.pointSize)),
                   autoClose: autoClose, onClose: onClose)
        contentView = RecordingThumbnailView(recording: recording, panel: self)
    }
}

@MainActor
private final class RecordingThumbnailView: PreviewStampView, NSDraggingSource {
    private let recording: CapturedRecording

    private lazy var copyButton = PillButton(label: "Copy", target: self, action: #selector(copyFile))
    private lazy var saveButton = PillButton(label: "", target: self, action: #selector(saveOrReveal))
    private var mouseDownPoint: NSPoint?
    private var resetCopyTitle: Task<Void, Never>?

    init(recording: CapturedRecording, panel: RecordingPreviewPanel) {
        self.recording = recording
        super.init(panel: panel, image: recording.thumbnail, date: recording.date, detail: recording.summary)

        buttons.addArrangedSubview(copyButton)
        buttons.addArrangedSubview(saveButton)
        NSLayoutConstraint.activate([
            copyButton.widthAnchor.constraint(equalTo: saveButton.widthAnchor),
            copyButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 96),
        ])
        topLeading.addArrangedSubview(CircleIconButton(symbol: "xmark", help: "Close", target: self, action: #selector(close)))
        saveButton.setLabel(recording.isSaved ? "Show in Finder" : "Save")
        addBadge(lengthBadge())
    }

    /// "▶ 0:42" or "GIF 0:07", always visible.
    private func lengthBadge() -> NSView {
        let symbol = NSImageView(image: NSImage(systemSymbolName: recording.format == .gif ? "photo.stack" : "play.fill",
                                                accessibilityDescription: nil)!)
        symbol.symbolConfiguration = .init(pointSize: 9, weight: .bold)
        symbol.contentTintColor = .white
        let label = NSTextField(labelWithString: (recording.format == .gif ? "GIF  " : "") + RecordingMath.clock(recording.duration))
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        label.textColor = .white
        let stack = NSStackView(views: [symbol, label])
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 3, left: 7, bottom: 3, right: 8)
        stack.wantsLayer = true
        // The light theme's ink, in both themes: the badge sits on the capture, not on paper.
        stack.layer?.backgroundColor = NSColor(srgbRed: 0x1C / 255, green: 0x22 / 255, blue: 0x30 / 255, alpha: 0.78).cgColor
        stack.layer?.cornerRadius = 6
        return stack
    }

    // MARK: Click & drag

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint else { return }
        let point = event.locationInWindow
        guard hypot(point.x - start.x, point.y - start.y) > 4 else { return }
        mouseDownPoint = nil

        let item = NSDraggingItem(pasteboardWriter: recording.url as NSURL)
        item.setDraggingFrame(imageArea.frame, contents: recording.thumbnail.map { NSImage(cgImage: $0, size: imageArea.frame.size) })
        beginDraggingSession(with: [item], event: event, source: self)
        previewPanel.alphaValue = 0
    }

    override func mouseUp(with event: NSEvent) {
        guard mouseDownPoint != nil else { return }
        mouseDownPoint = nil
        NSWorkspace.shared.open(recording.url)
        previewPanel.dismiss()
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if operation.isEmpty {
            previewPanel.alphaValue = 1
            setHovering(previewPanel.frame.contains(NSEvent.mouseLocation))
        } else {
            previewPanel.dismiss()
        }
    }

    // MARK: Actions

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
        previewPanel.dismiss()
    }
}
