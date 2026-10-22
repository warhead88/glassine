import AppKit
import UniformTypeIdentifiers

/// A floating preview in the bottom-right stack: closes itself after a while (paused on hover)
/// and never activates Glassine, so the app the user is working in keeps focus.
@MainActor
class PreviewPanel: NSPanel {
    private let autoClose: Duration?
    private let onClose: (PreviewPanel) -> Void
    private var closeTask: Task<Void, Never>?
    private(set) var isDismissing = false

    /// The size the stack lays this preview out at.
    var preferredSize: NSSize

    init(size: NSSize, autoClose: Duration?, onClose: @escaping (PreviewPanel) -> Void) {
        self.autoClose = autoClose
        self.onClose = onClose
        self.preferredSize = size
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        scheduleAutoClose()
    }

    override var canBecomeKey: Bool { true }

    /// The countdown pauses while the pointer is over the preview.
    func setHovering(_ hovering: Bool) {
        if hovering {
            closeTask?.cancel()
        } else {
            scheduleAutoClose()
        }
    }

    func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true
        closeTask?.cancel()
        onClose(self)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            animator().setFrame(frame.offsetBy(dx: frame.width / 2, dy: 0), display: true)
            animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { self.orderOut(nil) }
        })
    }

    private func scheduleAutoClose() {
        closeTask?.cancel()
        guard let autoClose else { return }
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: autoClose)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }
}

/// Floating thumbnail of a fresh capture: drag it into any app, copy, save or close it.
@MainActor
final class QuickAccessPanel: PreviewPanel {
    let capture: CapturedImage
    private let onPin: (CapturedImage) -> Void
    private let onEdit: (CapturedImage) -> Void
    private let onResize: (PreviewPanel) -> Void

    init(
        capture: CapturedImage,
        autoClose: Duration?,
        onPin: @escaping (CapturedImage) -> Void,
        onEdit: @escaping (CapturedImage) -> Void,
        onResize: @escaping (PreviewPanel) -> Void,
        onClose: @escaping (PreviewPanel) -> Void
    ) {
        self.capture = capture
        self.onPin = onPin
        self.onEdit = onEdit
        self.onResize = onResize
        super.init(size: QuickAccessLayout.stampSize(image: QuickAccessLayout.thumbnailSize(for: capture.pointSize)),
                   autoClose: autoClose, onClose: onClose)

        let thumbnail = ThumbnailView(capture: capture, panel: self)
        contentView = thumbnail

        // QR codes are found in the background (~10 ms); the preview grows a button if there are any.
        Task { [weak self, image = capture.image] in
            let codes = await BarcodeDetector.detect(image)
            guard let self, !codes.isEmpty, !isDismissing else { return }
            thumbnail.showCodes(codes)
            preferredSize = QuickAccessLayout.stampSize(image: QuickAccessLayout.thumbnailSize(for: capture.pointSize, hasQR: true))
            onResize(self)
        }
    }

    /// Turns the preview into a pin that stays on screen.
    func pin() {
        onPin(capture)
        dismiss()
    }

    /// Opens the capture in the editor; the preview's job is done.
    func edit() {
        onEdit(capture)
        dismiss()
    }
}

@MainActor
private final class ThumbnailView: PreviewStampView, NSDraggingSource {
    private let capture: CapturedImage
    private unowned let panel: QuickAccessPanel

    private lazy var copyButton = PillButton(label: "Copy", target: self, action: #selector(copyImage))
    private lazy var saveButton = PillButton(label: "", target: self, action: #selector(saveOrReveal))
    private lazy var qrButton = PillButton(label: "", style: .stamp, symbol: "qrcode", target: self, action: #selector(qrAction))
    private var codes: [String] = []

    private var mouseDownPoint: NSPoint?
    private var resetCopyTitle: Task<Void, Never>?

    init(capture: CapturedImage, panel: QuickAccessPanel) {
        self.capture = capture
        self.panel = panel
        super.init(panel: panel, image: capture.image, date: capture.date,
                   detail: "\(capture.image.width) × \(capture.image.height)")

        qrButton.isHidden = true
        for button in [copyButton, saveButton, qrButton] {
            buttons.addArrangedSubview(button)
        }
        NSLayoutConstraint.activate([
            copyButton.widthAnchor.constraint(equalTo: saveButton.widthAnchor),
            copyButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 96),
        ])
        topLeading.addArrangedSubview(CircleIconButton(symbol: "xmark", help: "Close", target: self, action: #selector(close)))
        topTrailing.addArrangedSubview(CircleIconButton(symbol: "pencil", help: "Edit", target: self, action: #selector(edit)))
        topTrailing.addArrangedSubview(CircleIconButton(symbol: "pin", help: "Pin to screen", target: self, action: #selector(pin)))
        updateSaveTitle()
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

        do {
            let url = try capture.shareableFileURL()
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            item.setDraggingFrame(bounds, contents: capture.nsImage)
            beginDraggingSession(with: [item], event: event, source: self)
            panel.alphaValue = 0
        } catch {
            Alerts.present(error)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard mouseDownPoint != nil else { return }
        mouseDownPoint = nil
        panel.edit()
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

    // MARK: Actions

    @objc private func copyImage() {
        capture.copyToClipboard()
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
            let alreadySaved = capture.savedURL != nil
            let url = try capture.save()
            if alreadySaved {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            updateSaveTitle()
        } catch {
            Alerts.present(error)
        }
    }

    @objc private func saveAs() {
        panel.setHovering(true)
        defer { panel.setHovering(panel.frame.contains(NSEvent.mouseLocation)) }

        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = "\(capture.baseName).\(capture.fileExtension)"
        savePanel.allowedContentTypes = [UTType(filenameExtension: capture.fileExtension) ?? .png]
        savePanel.directoryURL = Preferences.saveFolder
        NSApp.activate()
        guard savePanel.runModal() == .OK, let url = savePanel.url else { return }
        do {
            try capture.save(to: url)
            updateSaveTitle()
        } catch {
            Alerts.present(error)
        }
    }

    @objc private func openFile() {
        do {
            NSWorkspace.shared.open(try capture.shareableFileURL())
        } catch {
            Alerts.present(error)
        }
    }

    @objc private func close() {
        panel.dismiss()
    }

    @objc private func pin() {
        panel.pin()
    }

    @objc private func edit() {
        panel.edit()
    }

    @objc private func copyText() {
        SmartActions.copyText(from: capture.image)
    }

    private var saveTitle: String { capture.savedURL == nil ? "Save" : "Show in Finder" }

    private func updateSaveTitle() {
        saveButton.setLabel(saveTitle)
    }

    // MARK: QR codes

    /// Called once codes are found: the badge stays visible, the button shows on hover.
    func showCodes(_ codes: [String]) {
        self.codes = codes
        qrButton.setLabel(qrTitle)
        qrButton.isHidden = false

        let badge = NSImageView(image: NSImage(systemSymbolName: "qrcode", accessibilityDescription: "QR code found")!)
        badge.symbolConfiguration = .init(pointSize: 10, weight: .semibold)
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 10
        badge.toolTip = codes.count == 1 ? "QR code found" : "\(codes.count) QR codes found"
        effectiveAppearance.performAsCurrentDrawingAppearance {
            badge.contentTintColor = .onAccentStamp
            badge.layer?.backgroundColor = NSColor.accentStamp.cgColor
        }
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 20),
            badge.heightAnchor.constraint(equalToConstant: 20),
        ])
        addBadge(badge)
    }

    private var qrTitle: String {
        guard codes.count == 1 else { return "QR Codes (\(codes.count))…" }
        return BarcodeDetector.link(codes[0]) != nil ? "Copy QR Link" : "Copy QR Text"
    }

    @objc private func qrAction() {
        if codes.count == 1 {
            copyCode(codes[0])
        } else {
            let menu = qrMenu()
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: qrButton.bounds.height + 4), in: qrButton)
        }
    }

    /// One item per code (copies it), Copy All, and Open for links.
    private func qrMenu() -> NSMenu {
        let menu = NSMenu()
        for (index, code) in codes.enumerated() {
            let item = menu.addItem(withTitle: BarcodeDetector.menuTitle(code), action: #selector(copyCodeItem(_:)), keyEquivalent: "")
            item.tag = index
            item.toolTip = code
        }
        if codes.count > 1 {
            menu.addItem(.separator())
            menu.addItem(withTitle: "Copy All", action: #selector(copyAllCodes), keyEquivalent: "")
        }
        let links = codes.enumerated().filter { BarcodeDetector.link($0.element) != nil }
        if !links.isEmpty { menu.addItem(.separator()) }
        for (index, code) in links {
            let item = menu.addItem(withTitle: "Open \(BarcodeDetector.link(code)?.host ?? code)", action: #selector(openCodeItem(_:)), keyEquivalent: "")
            item.tag = index
        }
        menu.items.forEach { $0.target = self }
        return menu
    }

    @objc private func copyCodeItem(_ sender: NSMenuItem) { copyCode(codes[sender.tag]) }
    @objc private func copyAllCodes() { copyCode(codes.joined(separator: "\n")) }

    @objc private func openCodeItem(_ sender: NSMenuItem) {
        if let url = BarcodeDetector.link(codes[sender.tag]) { NSWorkspace.shared.open(url) }
    }

    private func copyCode(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        qrButton.setLabel("Copied")
        resetQRTitle?.cancel()
        resetQRTitle = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled, let self else { return }
            qrButton.setLabel(qrTitle)
        }
    }

    private var resetQRTitle: Task<Void, Never>?

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "Copy", action: #selector(copyImage), keyEquivalent: "")
        menu.addItem(withTitle: saveTitle, action: #selector(saveOrReveal), keyEquivalent: "")
        menu.addItem(withTitle: "Save As…", action: #selector(saveAs), keyEquivalent: "")
        menu.addItem(withTitle: "Edit", action: #selector(edit), keyEquivalent: "")
        menu.addItem(withTitle: "Open in Preview", action: #selector(openFile), keyEquivalent: "")
        menu.addItem(withTitle: "Pin to Screen", action: #selector(pin), keyEquivalent: "")
        menu.addItem(withTitle: "Copy Text", action: #selector(copyText), keyEquivalent: "")
        if !codes.isEmpty {
            let qr = menu.addItem(withTitle: codes.count == 1 ? qrTitle : "QR Codes", action: codes.count == 1 ? #selector(qrAction) : nil, keyEquivalent: "")
            if codes.count > 1 { qr.submenu = qrMenu() }
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Close", action: #selector(close), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        return menu
    }
}
