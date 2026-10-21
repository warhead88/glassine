import AppKit

enum OverlayResult {
    /// The cropped image and the selected rect in the screen's flipped local points.
    case area(CGImage, rect: NSRect)
    case window(CGWindowID)
    case cancelled
}

/// Borderless full-screen panel showing a frozen snapshot of one screen.
///
/// - Drag to select an area (Shift: square, Option: from center, hold Space: move).
/// - Click a window to capture it; click the desktop to capture the whole screen.
/// - With "adjust before capture" on, the selection stays editable after release:
///   drag handles or the inside, arrows nudge (Shift: 10 px), Return captures.
@MainActor
final class SelectionOverlayWindow: NSPanel {
    init(
        snapshot: ScreenSnapshot,
        windows: [WindowCandidate],
        onFinish: @escaping (OverlayResult) -> Void
    ) {
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

        // The frozen image lives in a layer so mouse moves only redraw the overlay on top.
        let background = NSView()
        background.wantsLayer = true
        background.layer?.contents = snapshot.image
        background.layer?.contentsGravity = .resize
        contentView = background

        let selection = SelectionView(
            snapshot: snapshot,
            windows: windows.map { snapshot.screen.localFlippedRect(fromGlobal: $0.frame) }
                .enumerated()
                .map { (id: windows[$0.offset].id, rect: $0.element) },
            onFinish: onFinish
        )
        selection.frame = background.bounds
        selection.autoresizingMask = [.width, .height]
        background.addSubview(selection)
    }

    override var canBecomeKey: Bool { true }
}

@MainActor
private final class SelectionView: NSView {
    private enum Handle: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    }

    private enum DragMode {
        case create(anchor: NSPoint)
        case move(start: NSPoint, original: NSRect)
        case resize(Handle, start: NSPoint, original: NSRect)
    }

    private let snapshot: ScreenSnapshot
    private let windows: [(id: CGWindowID, rect: NSRect)]
    private let onFinish: (OverlayResult) -> Void

    private let showMagnifier = UserDefaults.standard.bool(forKey: PrefKey.showMagnifier)
    private let adjustBeforeCapture = UserDefaults.standard.bool(forKey: PrefKey.adjustBeforeCapture)

    private var selection: NSRect?
    private var dragMode: DragMode?
    private var isAdjusting = false
    private var mouseDownPoint: NSPoint?
    private var didDrag = false
    private var cursorPoint: NSPoint?
    private var cursorColor: NSColor?
    private var hoveredWindow: (id: CGWindowID, rect: NSRect)?

    // Hold Space while creating a selection to move it instead of resizing.
    private var isSpaceMoving = false
    private var lastDragPoint: NSPoint?

    init(snapshot: ScreenSnapshot, windows: [(id: CGWindowID, rect: NSRect)], onFinish: @escaping (OverlayResult) -> Void) {
        self.snapshot = snapshot
        self.windows = windows
        self.onFinish = onFinish
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // Top-left origin matches CGImage pixel rows, which keeps cropping math simple.
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
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
        if let window {
            let local = window.convertPoint(fromScreen: NSEvent.mouseLocation)
            if bounds.contains(convert(local, from: nil)) {
                updateHover(at: convert(local, from: nil))
            }
        }
    }

    override func cursorUpdate(with event: NSEvent) { updateCursor() }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let dim = NSColor.black.withAlphaComponent(0.35).cgColor

        let highlight = selection ?? hoveredWindow?.rect.intersection(bounds)
        ctx.setFillColor(dim)
        if let highlight {
            let dimmed = CGMutablePath()
            dimmed.addRect(bounds)
            dimmed.addRect(highlight)
            ctx.addPath(dimmed)
            ctx.fillPath(using: .evenOdd)
        } else {
            ctx.fill(bounds)
        }

        if let selection {
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(selection.insetBy(dx: 0.5, dy: 0.5))
            if isAdjusting { drawHandles(for: selection, in: ctx) }
            drawSizeLabel(for: selection)
        } else if let hovered = hoveredWindow?.rect.intersection(bounds) {
            ctx.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor)
            ctx.fill(hovered)
            ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
            ctx.setLineWidth(2)
            ctx.stroke(hovered.insetBy(dx: 1, dy: 1))
        }

        if let cursorPoint, !isAdjusting || dragMode != nil {
            if selection == nil && hoveredWindow == nil {
                drawCrosshair(at: cursorPoint, in: ctx)
            }
            if showMagnifier {
                drawMagnifier(at: cursorPoint, in: ctx)
            }
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

    private func drawHandles(for rect: NSRect, in ctx: CGContext) {
        for handle in Handle.allCases {
            let center = handlePoint(handle, of: rect)
            let box = NSRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: box)
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.4).cgColor)
            ctx.setLineWidth(1)
            ctx.strokeEllipse(in: box)
        }
    }

    /// Zoomed pixels around the cursor with a grid, plus coordinates and the color under it.
    private func drawMagnifier(at point: NSPoint, in ctx: CGContext) {
        let pixelsAcross = 15
        let cell: CGFloat = 8
        let side = CGFloat(pixelsAcross) * cell
        let labelHeight: CGFloat = 34
        let offset: CGFloat = 24

        var origin = NSPoint(x: point.x + offset, y: point.y + offset)
        if origin.x + side > bounds.maxX { origin.x = point.x - offset - side }
        if origin.y + side + labelHeight > bounds.maxY { origin.y = point.y - offset - side - labelHeight }
        let loupe = NSRect(origin: origin, size: NSSize(width: side, height: side))
        let clip = NSBezierPath(roundedRect: loupe, xRadius: 8, yRadius: 8)

        // Source pixels, centered on the pixel under the cursor and clamped to the image.
        let center = pixelPoint(for: point)
        let half = CGFloat(pixelsAcross / 2)
        let wanted = CGRect(x: center.x - half, y: center.y - half, width: CGFloat(pixelsAcross), height: CGFloat(pixelsAcross))
        let available = wanted.intersection(CGRect(x: 0, y: 0, width: snapshot.image.width, height: snapshot.image.height))

        NSGraphicsContext.saveGraphicsState()
        clip.addClip()
        NSColor.black.setFill()
        loupe.fill()
        if !available.isEmpty, let pixels = snapshot.image.cropping(to: available) {
            let target = NSRect(
                x: loupe.minX + (available.minX - wanted.minX) * cell,
                y: loupe.minY + (available.minY - wanted.minY) * cell,
                width: available.width * cell,
                height: available.height * cell
            )
            NSGraphicsContext.current?.imageInterpolation = .none
            NSImage(cgImage: pixels, size: target.size)
                .draw(in: target, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        }

        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.12).cgColor)
        ctx.setLineWidth(0.5)
        for i in 1..<pixelsAcross {
            let offset = CGFloat(i) * cell
            ctx.strokeLineSegments(between: [
                CGPoint(x: loupe.minX + offset, y: loupe.minY), CGPoint(x: loupe.minX + offset, y: loupe.maxY),
                CGPoint(x: loupe.minX, y: loupe.minY + offset), CGPoint(x: loupe.maxX, y: loupe.minY + offset),
            ])
        }
        let centerCell = NSRect(x: loupe.minX + half * cell, y: loupe.minY + half * cell, width: cell, height: cell)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1.5)
        ctx.stroke(centerCell)
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.withAlphaComponent(0.8).setStroke()
        clip.lineWidth = 1.5
        clip.stroke()

        var lines = ["\(Int(center.x)), \(Int(center.y)) px"]
        if let cursorColor { lines.append(cursorColor.hexString) }
        drawLabel(lines.joined(separator: "\n"), at: NSPoint(x: loupe.minX, y: loupe.maxY + 4), width: side)
    }

    private func drawSizeLabel(for rect: NSRect) {
        let pixels = pixelRect(for: rect)
        var origin = NSPoint(x: rect.minX, y: rect.maxY + 6)
        if origin.y + 22 > bounds.maxY { origin.y = rect.minY - 28 }
        if origin.y < bounds.minY { origin.y = rect.minY + 6 }
        drawLabel("\(Int(pixels.width)) × \(Int(pixels.height))", at: origin, width: nil)
    }

    private func drawLabel(_ text: String, at origin: NSPoint, width: CGFloat?) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let string = text as NSString
        let size = string.boundingRect(with: NSSize(width: 400, height: 100), options: .usesLineFragmentOrigin, attributes: attributes).size
        let padding = NSSize(width: 6, height: 3)
        let background = NSRect(
            origin: origin,
            size: NSSize(width: width ?? (size.width + padding.width * 2), height: size.height + padding.height * 2)
        )
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: background, xRadius: 4, yRadius: 4).fill()
        string.draw(
            with: NSRect(x: origin.x + padding.width, y: origin.y + padding.height, width: size.width, height: size.height),
            options: .usesLineFragmentOrigin,
            attributes: attributes
        )
    }

    // MARK: Mouse

    override func mouseMoved(with event: NSEvent) {
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        let point = clamped(convert(event.locationInWindow, from: nil))
        mouseDownPoint = point
        lastDragPoint = point
        didDrag = false

        if isAdjusting, let selection {
            if event.clickCount == 2, selection.contains(point) {
                captureSelection()
                return
            }
            if let handle = handle(at: point, of: selection) {
                dragMode = .resize(handle, start: point, original: selection)
                return
            }
            if selection.contains(point) {
                dragMode = .move(start: point, original: selection)
                return
            }
        }
        dragMode = .create(anchor: point)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = clamped(convert(event.locationInWindow, from: nil))
        if let start = mouseDownPoint, !didDrag {
            guard hypot(point.x - start.x, point.y - start.y) > 3 else { return }
            didDrag = true
            hoveredWindow = nil
        }
        updateDrag(to: point, modifiers: event.modifierFlags)
        cursorPoint = point
        updateCursorColor()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragMode = nil
            mouseDownPoint = nil
            isSpaceMoving = false
            needsDisplay = true
        }

        guard didDrag else {
            // A plain click: capture the window under the cursor, or the whole screen.
            if isAdjusting {
                if case .create = dragMode { selection = nil; isAdjusting = false }
                return
            }
            if let hoveredWindow {
                onFinish(.window(hoveredWindow.id))
            } else {
                onFinish(.area(snapshot.image, rect: bounds))
            }
            return
        }

        guard let selection, selection.width >= 2, selection.height >= 2 else {
            self.selection = nil
            isAdjusting = false
            return
        }
        if adjustBeforeCapture {
            isAdjusting = true
            updateCursor()
        } else {
            captureSelection()
        }
    }

    override func rightMouseDown(with event: NSEvent) { onFinish(.cancelled) }

    private func updateDrag(to point: NSPoint, modifiers: NSEvent.ModifierFlags) {
        defer { lastDragPoint = point }
        guard let dragMode else { return }

        switch dragMode {
        case .create(let anchor):
            if isSpaceMoving, let last = lastDragPoint, let current = selection {
                let moved = fitted(current.offsetBy(dx: point.x - last.x, dy: point.y - last.y))
                self.dragMode = .create(anchor: NSPoint(
                    x: anchor.x + moved.minX - current.minX,
                    y: anchor.y + moved.minY - current.minY
                ))
                selection = moved
            } else {
                selection = Self.rect(
                    anchor: anchor, point: point,
                    square: modifiers.contains(.shift), fromCenter: modifiers.contains(.option)
                ).intersection(bounds)
            }
        case .move(let start, let original):
            selection = fitted(original.offsetBy(dx: point.x - start.x, dy: point.y - start.y))
        case .resize(let handle, let start, let original):
            selection = Self.resized(original, handle: handle, dx: point.x - start.x, dy: point.y - start.y)
                .intersection(bounds)
        }
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Escape
            onFinish(.cancelled)
        case 36, 76: // Return, Enter
            if isAdjusting { captureSelection() }
        case 49: // Space
            if case .create = dragMode, selection != nil { isSpaceMoving = true }
        case 123, 124, 125, 126: // Arrows
            guard isAdjusting, let selection else { return }
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1 / snapshot.scale
            let delta: (CGFloat, CGFloat) = switch event.keyCode {
            case 123: (-step, 0)
            case 124: (step, 0)
            case 125: (0, step)
            default: (0, -step)
            }
            self.selection = fitted(selection.offsetBy(dx: delta.0, dy: delta.1))
            needsDisplay = true
        default:
            super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 { isSpaceMoving = false }
    }

    override func flagsChanged(with event: NSEvent) {
        guard let lastDragPoint, didDrag else { return }
        updateDrag(to: lastDragPoint, modifiers: event.modifierFlags)
        needsDisplay = true
    }

    // MARK: Helpers

    private func captureSelection() {
        guard let selection, let image = snapshot.image.cropping(to: pixelRect(for: selection)) else { return }
        onFinish(.area(image, rect: selection))
    }

    private func updateHover(at point: NSPoint) {
        cursorPoint = point
        if !isAdjusting && dragMode == nil {
            hoveredWindow = windows.first { $0.rect.contains(point) }
        }
        updateCursorColor()
        updateCursor()
        needsDisplay = true
    }

    private func updateCursor() {
        guard isAdjusting, let selection, let cursorPoint else {
            NSCursor.crosshair.set()
            return
        }
        switch handle(at: cursorPoint, of: selection) {
        case .left, .right: NSCursor.resizeLeftRight.set()
        case .top, .bottom: NSCursor.resizeUpDown.set()
        case .some: NSCursor.crosshair.set()
        case nil: (selection.contains(cursorPoint) ? NSCursor.openHand : NSCursor.crosshair).set()
        }
    }

    private func updateCursorColor() {
        guard showMagnifier, let cursorPoint else { return }
        let pixel = pixelPoint(for: cursorPoint)
        cursorColor = snapshot.image.cropping(to: CGRect(x: pixel.x, y: pixel.y, width: 1, height: 1))
            .flatMap { NSBitmapImageRep(cgImage: $0).colorAt(x: 0, y: 0) }
    }

    private func pixelPoint(for point: NSPoint) -> CGPoint {
        let sx = CGFloat(snapshot.image.width) / bounds.width
        let sy = CGFloat(snapshot.image.height) / bounds.height
        return CGPoint(
            x: min(max(floor(point.x * sx), 0), CGFloat(snapshot.image.width - 1)),
            y: min(max(floor(point.y * sy), 0), CGFloat(snapshot.image.height - 1))
        )
    }

    private func pixelRect(for rect: NSRect) -> CGRect {
        let sx = CGFloat(snapshot.image.width) / bounds.width
        let sy = CGFloat(snapshot.image.height) / bounds.height
        return CGRect(x: rect.minX * sx, y: rect.minY * sy, width: rect.width * sx, height: rect.height * sy).integral
    }

    private func clamped(_ point: NSPoint) -> NSPoint {
        NSPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
    }

    /// Keeps a moved rect inside the screen without changing its size.
    private func fitted(_ rect: NSRect) -> NSRect {
        var rect = rect
        rect.origin.x = min(max(rect.minX, bounds.minX), bounds.maxX - rect.width)
        rect.origin.y = min(max(rect.minY, bounds.minY), bounds.maxY - rect.height)
        return rect
    }

    private func handlePoint(_ handle: Handle, of rect: NSRect) -> NSPoint {
        switch handle {
        case .topLeft: NSPoint(x: rect.minX, y: rect.minY)
        case .top: NSPoint(x: rect.midX, y: rect.minY)
        case .topRight: NSPoint(x: rect.maxX, y: rect.minY)
        case .right: NSPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: NSPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: NSPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: NSPoint(x: rect.minX, y: rect.maxY)
        case .left: NSPoint(x: rect.minX, y: rect.midY)
        }
    }

    private func handle(at point: NSPoint, of rect: NSRect) -> Handle? {
        Handle.allCases.first { hypot(handlePoint($0, of: rect).x - point.x, handlePoint($0, of: rect).y - point.y) <= 8 }
    }

    static func rect(anchor: NSPoint, point: NSPoint, square: Bool, fromCenter: Bool) -> NSRect {
        var dx = point.x - anchor.x
        var dy = point.y - anchor.y
        if square {
            let side = max(abs(dx), abs(dy))
            dx = dx < 0 ? -side : side
            dy = dy < 0 ? -side : side
        }
        if fromCenter {
            return NSRect(x: anchor.x - abs(dx), y: anchor.y - abs(dy), width: abs(dx) * 2, height: abs(dy) * 2)
        }
        return NSRect(x: min(anchor.x, anchor.x + dx), y: min(anchor.y, anchor.y + dy), width: abs(dx), height: abs(dy))
    }

    /// Moves the edges a handle controls; dragging past the opposite edge flips the rect.
    private static func resized(_ rect: NSRect, handle: Handle, dx: CGFloat, dy: CGFloat) -> NSRect {
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        switch handle {
        case .topLeft: minX += dx; minY += dy
        case .top: minY += dy
        case .topRight: maxX += dx; minY += dy
        case .right: maxX += dx
        case .bottomRight: maxX += dx; maxY += dy
        case .bottom: maxY += dy
        case .bottomLeft: minX += dx; maxY += dy
        case .left: minX += dx
        }
        return NSRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))
    }
}

private extension NSColor {
    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "" }
        return String(
            format: "#%02X%02X%02X",
            Int((rgb.redComponent * 255).rounded()),
            Int((rgb.greenComponent * 255).rounded()),
            Int((rgb.blueComponent * 255).rounded())
        )
    }
}
