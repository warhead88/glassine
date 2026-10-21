import AppKit

/// Borderless full-screen panel showing a frozen snapshot of one screen.
/// Calls `onFinish` with the cropped image, or nil if the user cancelled.
@MainActor
final class SelectionOverlayWindow: NSPanel {
    init(snapshot: ScreenSnapshot, onFinish: @escaping (CGImage?) -> Void) {
        super.init(
            contentRect: snapshot.screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = true
        hasShadow = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        setFrame(snapshot.screen.frame, display: false)

        contentView = SelectionView(snapshot: snapshot, onFinish: onFinish)
    }

    override var canBecomeKey: Bool { true }
}

@MainActor
private final class SelectionView: NSView {
    private let snapshot: ScreenSnapshot
    private let onFinish: (CGImage?) -> Void

    private var dragStart: NSPoint?
    private var selection: NSRect?
    private var cursorPoint: NSPoint?

    init(snapshot: ScreenSnapshot, onFinish: @escaping (CGImage?) -> Void) {
        self.snapshot = snapshot
        self.onFinish = onFinish
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // Top-left origin matches CGImage pixel rows, which keeps cropping math simple.
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate],
            owner: self
        ))
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // CGContext.draw flips images in a flipped view, so draw through NSImage instead.
        NSImage(cgImage: snapshot.image, size: bounds.size)
            .draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)

        ctx.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        if let selection {
            let dimmed = CGMutablePath()
            dimmed.addRect(bounds)
            dimmed.addRect(selection)
            ctx.addPath(dimmed)
            ctx.fillPath(using: .evenOdd)

            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(selection.insetBy(dx: 0.5, dy: 0.5))

            drawSizeLabel(for: selection)
        } else {
            ctx.fill(bounds)
            if let cursorPoint { drawCrosshair(at: cursorPoint, in: ctx) }
        }
    }

    private func drawCrosshair(at point: NSPoint, in ctx: CGContext) {
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.6).cgColor)
        ctx.setLineWidth(1)
        ctx.strokeLineSegments(between: [
            CGPoint(x: bounds.minX, y: point.y.rounded() + 0.5), CGPoint(x: bounds.maxX, y: point.y.rounded() + 0.5),
            CGPoint(x: point.x.rounded() + 0.5, y: bounds.minY), CGPoint(x: point.x.rounded() + 0.5, y: bounds.maxY),
        ])
    }

    private func drawSizeLabel(for rect: NSRect) {
        let pixels = pixelRect(for: rect)
        let text = "\(Int(pixels.width)) × \(Int(pixels.height))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        let padding = NSSize(width: 6, height: 3)
        var origin = NSPoint(x: rect.minX, y: rect.maxY + 6)
        if origin.y + size.height + padding.height * 2 > bounds.maxY {
            origin.y = rect.minY - size.height - padding.height * 2 - 6
        }
        let background = NSRect(
            origin: origin,
            size: NSSize(width: size.width + padding.width * 2, height: size.height + padding.height * 2)
        )
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: background, xRadius: 4, yRadius: 4).fill()
        text.draw(at: NSPoint(x: origin.x + padding.width, y: origin.y + padding.height), withAttributes: attributes)
    }

    // MARK: Input

    override func mouseMoved(with event: NSEvent) {
        cursorPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        dragStart = convert(event.locationInWindow, from: nil)
        selection = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        selection = NSRect(
            x: min(dragStart.x, point.x), y: min(dragStart.y, point.y),
            width: abs(point.x - dragStart.x), height: abs(point.y - dragStart.y)
        ).intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil }
        guard let selection, selection.width >= 2, selection.height >= 2 else {
            self.selection = nil
            needsDisplay = true
            return
        }
        onFinish(snapshot.image.cropping(to: pixelRect(for: selection)))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onFinish(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) { onFinish(nil) }

    private func pixelRect(for rect: NSRect) -> CGRect {
        let sx = CGFloat(snapshot.image.width) / bounds.width
        let sy = CGFloat(snapshot.image.height) / bounds.height
        return CGRect(x: rect.minX * sx, y: rect.minY * sy, width: rect.width * sx, height: rect.height * sy).integral
    }
}
