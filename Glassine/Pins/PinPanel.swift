import AppKit
import UniformTypeIdentifiers

/// A capture floating above all windows.
///
/// Drag to move, scroll to zoom, ⌥-scroll for opacity, double-click for 100%.
/// (No pinch: macOS sends trackpad gestures only to the active app, and pins never activate Glassine.)
/// Right-click for copy, save, opacity, lock, click-through and close.
@MainActor
final class PinPanel: NSPanel {
    let capture: CapturedImage
    private unowned let controller: PinController
    private(set) var zoom: CGFloat

    /// Position can't be changed by dragging.
    var isLocked = false

    /// Clicks go to the windows underneath. Hold ⌥⌘ to interact with the pin again.
    var isClickThrough = false {
        didSet {
            ignoresMouseEvents = isClickThrough
            if isClickThrough {
                (contentView as? PinView)?.showBadge("Clicks pass through · hold ⌥⌘ to use the pin", for: .seconds(3))
            } else {
                setHighlighted(false)
            }
            controller.clickThroughDidChange()
        }
    }

    init(capture: CapturedImage, center: NSPoint, zoom: CGFloat, controller: PinController) {
        self.capture = capture
        self.controller = controller
        self.zoom = zoom
        let size = Self.size(for: capture, zoom: zoom)
        super.init(
            contentRect: NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        contentView = PinView(capture: capture, panel: self)
        makeFirstResponder(contentView)
    }

    override var canBecomeKey: Bool { true }

    // MARK: Zoom & opacity

    /// Zooms around `anchor` (a screen point) so the pixel under the pointer stays put.
    func setZoom(_ newZoom: CGFloat, anchor: NSPoint? = nil) {
        let clamped = PinGeometry.clampedZoom(newZoom, natural: capture.pointSize)
        guard clamped != zoom else { return }

        let anchor = anchor ?? NSPoint(x: frame.midX, y: frame.midY)
        zoom = clamped
        setFrame(PinGeometry.zoomedFrame(frame, to: Self.size(for: capture, zoom: clamped), anchor: anchor), display: true)
        (contentView as? PinView)?.showBadge("\(Int((clamped * 100).rounded()))%")
    }

    func setOpacity(_ opacity: CGFloat) {
        alphaValue = min(max(opacity, 0.2), 1)
        (contentView as? PinView)?.showBadge("Opacity \(Int((alphaValue * 100).rounded()))%")
    }

    private static func size(for capture: CapturedImage, zoom: CGFloat) -> NSSize {
        NSSize(width: (capture.pointSize.width * zoom).rounded(), height: (capture.pointSize.height * zoom).rounded())
    }

    // MARK: Actions

    @objc func copyImage() {
        capture.copyToClipboard()
        (contentView as? PinView)?.showBadge("Copied")
    }

    @objc func saveAs() {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = "\(capture.baseName).\(capture.fileExtension)"
        savePanel.allowedContentTypes = [UTType(filenameExtension: capture.fileExtension) ?? .png]
        savePanel.directoryURL = Preferences.saveFolder
        NSApp.activate()
        guard savePanel.runModal() == .OK, let url = savePanel.url else { return }
        do {
            try capture.save(to: url)
        } catch {
            Alerts.present(error)
        }
    }

    @objc func actualSize() { setZoom(1) }
    @objc func toggleLock() { isLocked.toggle() }
    @objc func toggleClickThrough() { isClickThrough.toggle() }
    @objc func closePin() { controller.close(self) }
    @objc func closeAllPins() { controller.closeAll() }
    @objc func copyText() { SmartActions.copyText(from: capture.image) }
    @objc func edit() {
        controller.onEdit(capture)
        controller.close(self)
    }

    @objc func setOpacityFromMenu(_ sender: NSMenuItem) {
        setOpacity(CGFloat(sender.tag) / 100)
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Copy", action: #selector(copyImage), keyEquivalent: "c")
        menu.addItem(withTitle: "Save As…", action: #selector(saveAs), keyEquivalent: "s")
        menu.addItem(withTitle: "Edit", action: #selector(edit), keyEquivalent: "e")
        menu.addItem(withTitle: "Copy Text", action: #selector(copyText), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Actual Size", action: #selector(actualSize), keyEquivalent: "0")

        let opacity = NSMenu()
        for percent in [100, 75, 50, 25] {
            let item = opacity.addItem(withTitle: "\(percent)%", action: #selector(setOpacityFromMenu(_:)), keyEquivalent: "")
            item.tag = percent
            item.target = self
            item.state = Int((alphaValue * 100).rounded()) == percent ? .on : .off
        }
        menu.addItem(withTitle: "Opacity", action: nil, keyEquivalent: "").submenu = opacity

        menu.addItem(withTitle: "Lock Position", action: #selector(toggleLock), keyEquivalent: "").state = isLocked ? .on : .off
        let clickThrough = menu.addItem(withTitle: "Click Through", action: #selector(toggleClickThrough), keyEquivalent: "")
        clickThrough.state = isClickThrough ? .on : .off
        clickThrough.toolTip = "Clicks pass to the windows below. Hold ⌥⌘ to use the pin again."
        menu.addItem(.separator())
        menu.addItem(withTitle: "Close", action: #selector(closePin), keyEquivalent: "w")
        menu.addItem(withTitle: "Close All Pins", action: #selector(closeAllPins), keyEquivalent: "")
        for item in menu.items where item.action != nil {
            item.target = self
        }
        return menu
    }
}

@MainActor
private final class PinView: NSView {
    private let capture: CapturedImage
    private unowned let panel: PinPanel

    private lazy var closeButton = CircleIconButton(symbol: "xmark", help: "Close pin (Esc)",
                                                    target: panel, action: #selector(PinPanel.closePin))
    private let badge = NSTextField(labelWithString: "")
    private var highlighted = false
    private var hideBadge: Task<Void, Never>?

    init(capture: CapturedImage, panel: PinPanel) {
        self.capture = capture
        self.panel = panel
        super.init(frame: NSRect(origin: .zero, size: panel.frame.size))

        wantsLayer = true
        layer?.contents = capture.image
        layer?.contentsGravity = .resize
        layer?.minificationFilter = .trilinear
        // The capture stays as it is, no paper around it (DECISIONS 4): only a hairline edge.
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        applyBorder()

        // A paper button in the corner, like the previews'.
        closeButton.alphaValue = CommandLine.arguments.contains("hover") ? 1 : 0 // `--debug-pins hover`
        addSubview(closeButton)

        badge.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        badge.textColor = .tagText
        badge.alignment = .center
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor.tagFill.cgColor
        badge.layer?.cornerRadius = 5
        badge.alphaValue = 0
        badge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badge)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            closeButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            badge.centerXAnchor.constraint(equalTo: centerXAnchor),
            badge.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])

        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func showBadge(_ text: String, for duration: Duration = .seconds(1)) {
        badge.stringValue = "  \(text)  "
        badge.alphaValue = 1
        hideBadge?.cancel()
        hideBadge = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self else { return }
            self.badge.animator().alphaValue = 0
        }
    }

    /// Shown while ⌥⌘ makes a click-through pin interactive.
    func setHighlighted(_ highlighted: Bool) {
        self.highlighted = highlighted
        applyBorder()
    }

    /// A hairline of the theme's border; the accent while ⌥⌘ makes the pin usable.
    private func applyBorder() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderWidth = highlighted ? 2 : 1
            layer?.borderColor = (highlighted ? Theme.shared.nsAccent : NSColor.border).cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyBorder()
    }

    // MARK: Mouse

    override func mouseEntered(with event: NSEvent) { setControlsVisible(true) }
    override func mouseExited(with event: NSEvent) { setControlsVisible(false) }

    private func setControlsVisible(_ visible: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            closeButton.animator().alphaValue = visible ? 1 : 0
        }
    }

    override func mouseDown(with event: NSEvent) {
        // Key (for Esc, ⌘C, ⌘0…) but not active: the app underneath stays frontmost.
        window?.makeKey()
        if event.clickCount == 2 {
            panel.actualSize()
        } else if !panel.isLocked {
            window?.performDrag(with: event)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.01 : event.scrollingDeltaY * 0.1
        guard delta != 0 else { return }
        if event.modifierFlags.contains(.option) {
            panel.setOpacity(panel.alphaValue + delta)
        } else {
            panel.setZoom(panel.zoom * exp(delta), anchor: NSEvent.mouseLocation)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? { panel.makeMenu() }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        let command = event.modifierFlags.contains(.command)
        switch (event.keyCode, command) {
        case (53, _): panel.closePin()                  // Esc
        case (13, true): panel.closePin()               // ⌘W
        case (8, true): panel.copyImage()               // ⌘C
        case (1, true): panel.saveAs()                  // ⌘S
        case (29, true): panel.actualSize()             // ⌘0
        case (14, true): panel.edit()                   // ⌘E
        case (24, true): panel.setZoom(panel.zoom * 1.25)  // ⌘=
        case (27, true): panel.setZoom(panel.zoom / 1.25)  // ⌘-
        default: super.keyDown(with: event)
        }
    }
}

extension PinPanel {
    func setHighlighted(_ highlighted: Bool) {
        (contentView as? PinView)?.setHighlighted(highlighted)
    }
}
