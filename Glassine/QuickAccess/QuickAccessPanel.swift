import AppKit
import UniformTypeIdentifiers

/// Floating thumbnail of a fresh capture: drag it into any app, copy, save or close it.
/// Never activates Glassine, so the app the user is working in keeps focus.
@MainActor
final class QuickAccessPanel: NSPanel {
    let capture: CapturedImage
    private let autoClose: Duration?
    private let onClose: (QuickAccessPanel) -> Void
    private let onPin: (CapturedImage) -> Void
    private let onEdit: (CapturedImage) -> Void
    private let onResize: (QuickAccessPanel) -> Void
    private var closeTask: Task<Void, Never>?
    private var isDismissing = false

    init(
        capture: CapturedImage,
        autoClose: Duration?,
        onPin: @escaping (CapturedImage) -> Void,
        onEdit: @escaping (CapturedImage) -> Void,
        onResize: @escaping (QuickAccessPanel) -> Void,
        onClose: @escaping (QuickAccessPanel) -> Void
    ) {
        self.capture = capture
        self.autoClose = autoClose
        self.onPin = onPin
        self.onEdit = onEdit
        self.onResize = onResize
        self.onClose = onClose
        self.preferredSize = QuickAccessLayout.thumbnailSize(for: capture.pointSize)
        super.init(
            contentRect: NSRect(origin: .zero, size: QuickAccessLayout.thumbnailSize(for: capture.pointSize)),
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

        let thumbnail = ThumbnailView(capture: capture, panel: self)
        contentView = thumbnail
        scheduleAutoClose()

        // QR codes are found in the background (~10 ms); the preview grows a button if there are any.
        Task { [weak self, image = capture.image] in
            let codes = await BarcodeDetector.detect(image)
            guard let self, !codes.isEmpty, !isDismissing else { return }
            thumbnail.showCodes(codes)
            preferredSize = QuickAccessLayout.thumbnailSize(for: capture.pointSize, hasQR: true)
            onResize(self)
        }
    }

    /// The size the stack lays this preview out at; grows when QR codes are found.
    private(set) var preferredSize: NSSize

    override var canBecomeKey: Bool { true }

    /// The countdown pauses while the pointer is over the preview.
    func setHovering(_ hovering: Bool) {
        if hovering {
            closeTask?.cancel()
        } else {
            scheduleAutoClose()
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

@MainActor
private final class ThumbnailView: NSView, NSDraggingSource {
    private let capture: CapturedImage
    private unowned let panel: QuickAccessPanel

    private let overlay = NSView()
    private lazy var copyButton = PillButton(label: "Copy", target: self, action: #selector(copyImage))
    private lazy var saveButton = PillButton(label: "", target: self, action: #selector(saveOrReveal))
    private lazy var qrButton = PillButton(label: "", target: self, action: #selector(qrAction))
    private let qrBadge = NSImageView()
    private var codes: [String] = []
    private lazy var closeButton = FirstMouseButton(
        image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")!,
        target: self, action: #selector(close)
    )
    private lazy var pinButton = FirstMouseButton(
        image: NSImage(systemSymbolName: "pin.circle.fill", accessibilityDescription: "Pin")!,
        target: self, action: #selector(pin)
    )

    private var mouseDownPoint: NSPoint?
    private var resetCopyTitle: Task<Void, Never>?

    init(capture: CapturedImage, panel: QuickAccessPanel) {
        self.capture = capture
        self.panel = panel
        super.init(frame: NSRect(origin: .zero, size: panel.frame.size))

        wantsLayer = true
        // Aspect-fit on a neutral backdrop, so tall or tiny captures are shown whole.
        layer?.contents = capture.image
        layer?.contentsGravity = .resizeAspect
        layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.95).cgColor
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor

        setUpOverlay()
        updateSaveTitle()

        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setUpOverlay() {
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        overlay.alphaValue = 0
        overlay.frame = bounds
        overlay.autoresizingMask = [.width, .height]
        addSubview(overlay)

        qrButton.isHidden = true
        let stack = NSStackView(views: [copyButton, saveButton, qrButton])
        stack.orientation = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(stack)

        for button in [closeButton, pinButton] {
            button.isBordered = false
            button.contentTintColor = .white
            button.symbolConfiguration = .init(pointSize: 16, weight: .regular)
            button.translatesAutoresizingMaskIntoConstraints = false
            overlay.addSubview(button)
        }
        pinButton.toolTip = "Pin to screen"

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            copyButton.widthAnchor.constraint(equalTo: saveButton.widthAnchor),
            qrButton.widthAnchor.constraint(greaterThanOrEqualTo: saveButton.widthAnchor),
            closeButton.topAnchor.constraint(equalTo: overlay.topAnchor, constant: 6),
            closeButton.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 6),
            pinButton.topAnchor.constraint(equalTo: overlay.topAnchor, constant: 6),
            pinButton.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -6),
        ])
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Hover

    override func mouseEntered(with event: NSEvent) { setHovering(true) }
    override func mouseExited(with event: NSEvent) { setHovering(false) }

    private func setHovering(_ hovering: Bool) {
        panel.setHovering(hovering)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            overlay.animator().alphaValue = hovering ? 1 : 0
        }
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

        qrBadge.image = NSImage(systemSymbolName: "qrcode", accessibilityDescription: "QR code found")
        qrBadge.symbolConfiguration = .init(pointSize: 11, weight: .semibold)
        qrBadge.contentTintColor = .white
        qrBadge.wantsLayer = true
        qrBadge.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        qrBadge.layer?.cornerRadius = 5
        qrBadge.toolTip = codes.count == 1 ? "QR code found" : "\(codes.count) QR codes found"
        qrBadge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(qrBadge, positioned: .below, relativeTo: overlay)
        NSLayoutConstraint.activate([
            qrBadge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            qrBadge.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            qrBadge.widthAnchor.constraint(equalToConstant: 20),
            qrBadge.heightAnchor.constraint(equalToConstant: 20),
        ])
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
