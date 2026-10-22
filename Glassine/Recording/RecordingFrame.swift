import AppKit

/// The dashed frame around a recorded area, which can be moved and resized: freely before
/// recording, and while recording by its border (moving) or corners (resizing with the aspect
/// ratio kept, since the video's size is fixed — a smaller area zooms in).
///
/// It is a transparent window over the whole screen that takes the mouse only where the frame
/// can be grabbed; everywhere else clicks reach the apps below.
@MainActor
final class RecordingFrame {
    enum Mode {
        /// Before recording: drag inside or on the border to move, eight handles to resize.
        case setup
        /// While recording: the inside stays clickable for the app; border moves, corners resize.
        case recording
    }

    private let panel: NSPanel
    private let view: FrameView
    private var monitors: [Any] = []

    /// Called while the area changes, in the screen's flipped local points.
    var onChange: (CGRect) -> Void = { _ in }

    var rect: CGRect { view.rect }

    init(rect: CGRect, on screen: NSScreen) {
        panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        view = FrameView(frame: NSRect(origin: .zero, size: screen.frame.size), rect: rect, scale: screen.backingScaleFactor)
        panel.contentView = view
        view.onChange = { [weak self] in self?.onChange($0) }
    }

    var mode: Mode {
        get { view.mode }
        set {
            view.mode = newValue
            view.needsDisplay = true
        }
    }

    /// Moves the frame from code, as if dragged there.
    func setRect(_ rect: CGRect) {
        view.setRect(rect)
        onChange(view.rect)
    }

    func show() {
        panel.orderFrontRegardless()
        // Glassine isn't active, so the pointer is followed with a global monitor too.
        let follow: (NSEvent) -> Void = { [weak self] _ in self?.updateMouseHandling() }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: follow) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { follow($0); return $0 }) {
            monitors.append(local)
        }
        updateMouseHandling()
    }

    func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        panel.orderOut(nil)
    }

    /// The window takes clicks only over the parts of the frame that can be grabbed.
    private func updateMouseHandling() {
        guard !view.isDragging else { return }
        let point = view.convert(panel.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        panel.ignoresMouseEvents = !view.grabs(point)
    }
}

private final class FrameView: NSView {
    private(set) var rect: CGRect
    var mode = RecordingFrame.Mode.setup
    var onChange: (CGRect) -> Void = { _ in }
    private let scale: CGFloat
    private enum Drag {
        case move(start: CGPoint, original: CGRect)
        case resize(SelectionGeometry.Handle, start: CGPoint, original: CGRect)
    }
    private var drag: Drag?
    var isDragging: Bool { drag != nil }

    private static let minSize = CGSize(width: 64, height: 48)
    private static let handleRadius: CGFloat = 5

    init(frame: NSRect, rect: CGRect, scale: CGFloat) {
        self.rect = rect
        self.scale = scale
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate],
                                       owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var handles: [SelectionGeometry.Handle] {
        mode == .setup ? SelectionGeometry.Handle.allCases : [.topLeft, .topRight, .bottomRight, .bottomLeft]
    }

    private func handle(at point: CGPoint) -> SelectionGeometry.Handle? {
        handles.first {
            let p = SelectionGeometry.handlePoint($0, of: rect)
            return hypot(p.x - point.x, p.y - point.y) <= Self.handleRadius + 5
        }
    }

    func setRect(_ rect: CGRect) {
        self.rect = rect.integral
        needsDisplay = true
    }

    func grabs(_ point: CGPoint) -> Bool {
        handle(at: point) != nil || SelectionGeometry.isOnBorder(point, of: rect)
            || (mode == .setup && rect.contains(point))
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let outline = rect.insetBy(dx: -1.5, dy: -1.5) // just outside the recorded pixels
        for (color, width) in [(NSColor.black.withAlphaComponent(0.35), 3.0), (NSColor.white, 1.5)] {
            let path = NSBezierPath(rect: outline)
            path.lineWidth = width
            path.setLineDash([8, 5], count: 2, phase: 0)
            color.setStroke()
            path.stroke()
        }
        for handle in handles {
            let p = SelectionGeometry.handlePoint(handle, of: outline)
            let dot = NSBezierPath(ovalIn: CGRect(x: p.x - Self.handleRadius, y: p.y - Self.handleRadius,
                                                  width: Self.handleRadius * 2, height: Self.handleRadius * 2))
            NSColor.white.setFill()
            dot.fill()
            NSColor.black.withAlphaComponent(0.4).setStroke()
            dot.lineWidth = 1
            dot.stroke()
        }
        if isDragging {
            drawSizeLabel()
        }
    }

    /// "1280 × 720" under the frame while it changes: the recording's size in pixels.
    private func drawSizeLabel() {
        let pixels = RecordingMath.pixelSize(points: rect.size, scale: scale)
        let text = NSAttributedString(string: "\(pixels.width) × \(pixels.height)", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.tagText,
        ])
        let size = text.size()
        var box = CGRect(x: rect.midX - size.width / 2 - 8, y: rect.maxY + 10, width: size.width + 16, height: size.height + 6)
        if box.maxY > bounds.maxY { box.origin.y = rect.maxY - box.height - 10 }
        NSColor.tagFill.setFill()
        NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
        text.draw(at: CGPoint(x: box.minX + 8, y: box.minY + 3))
    }

    // MARK: Mouse

    override func cursorUpdate(with event: NSEvent) { updateCursor(at: convert(event.locationInWindow, from: nil)) }
    override func mouseMoved(with event: NSEvent) { updateCursor(at: convert(event.locationInWindow, from: nil)) }

    private func updateCursor(at point: CGPoint) {
        guard let handle = handle(at: point) else {
            (grabs(point) ? NSCursor.openHand : NSCursor.arrow).set()
            return
        }
        if #available(macOS 15.0, *) {
            let position: NSCursor.FrameResizePosition = switch handle {
            case .top: .top
            case .bottom: .bottom
            case .left: .left
            case .right: .right
            case .topLeft: .topLeft
            case .topRight: .topRight
            case .bottomLeft: .bottomLeft
            case .bottomRight: .bottomRight
            }
            NSCursor.frameResize(position: position, directions: .all).set()
        } else {
            switch handle {
            case .left, .right: NSCursor.resizeLeftRight.set()
            case .top, .bottom: NSCursor.resizeUpDown.set()
            default: NSCursor.crosshair.set()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let handle = handle(at: point) {
            drag = .resize(handle, start: point, original: rect)
        } else if grabs(point) {
            drag = .move(start: point, original: rect)
            NSCursor.closedHand.set()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch drag {
        case .move(let start, let original):
            rect = SelectionGeometry.fitted(original.offsetBy(dx: point.x - start.x, dy: point.y - start.y), in: bounds)
        case .resize(let handle, let start, let original):
            if mode == .recording {
                rect = SelectionGeometry.resizedKeepingAspect(original, handle: handle, dx: point.x - start.x,
                                                              in: bounds, minWidth: Self.minSize.width)
            } else {
                rect = SelectionGeometry.limited(
                    SelectionGeometry.resized(original, handle: handle, dx: point.x - start.x, dy: point.y - start.y),
                    in: bounds, minSize: Self.minSize
                )
            }
        case nil:
            return
        }
        rect = rect.integral
        needsDisplay = true
        onChange(rect)
    }

    override func mouseUp(with event: NSEvent) {
        drag = nil
        needsDisplay = true
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }
}
