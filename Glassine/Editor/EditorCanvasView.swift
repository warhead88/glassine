import AppKit

/// The editing surface: shows the capture fitted between the floating toolbars and turns
/// mouse and keyboard input into annotations. All drawing goes through `AnnotationRenderer`.
@MainActor
final class EditorCanvasView: NSView, NSTextFieldDelegate, NSMenuItemValidation {
    private let model: EditorModel
    private var renderer: AnnotationRenderer { model.renderer }

    var onCopy: () -> Void = {}
    var onSave: () -> Void = {}

    /// Space kept free for the floating toolbar (top) and action bar (bottom).
    private let insets = NSEdgeInsets(top: 72, left: 32, bottom: 80, right: 32)
    private let handleRadius: CGFloat = 5

    private enum Drag {
        case draw(start: CGPoint)
        case crop(start: CGPoint)
        case move(start: CGPoint, original: Annotation)
        case resize(Annotation.Handle, start: CGPoint, original: Annotation)
    }

    private var drag: Drag?
    private var draft: Annotation?
    private var cropDraft: CGRect?

    private var textField: NSTextField?
    private var editingText: Annotation?
    private var editingExisting = false

    init(model: EditorModel) {
        self.model = model
        super.init(frame: .zero)
        model.onChange = { [weak self] in
            guard let self else { return }
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Fitting

    private var available: CGRect {
        CGRect(x: insets.left, y: insets.top, width: bounds.width - insets.left - insets.right,
               height: bounds.height - insets.top - insets.bottom)
    }

    /// The document area being fitted: the canvas (image + padding + overflowing annotations).
    /// Frozen while dragging, so the view doesn't rescale under the pointer as the canvas grows.
    private var layoutRect: CGRect { frozenLayout ?? model.canvasRect }
    private var frozenLayout: CGRect?

    /// Fits the document between the bars; small captures may grow up to 2× so they're easy to annotate.
    private var zoom: CGFloat {
        let size = layoutRect.size
        return max(min(available.width / size.width, available.height / size.height, 2), 0.05)
    }

    /// Where the layout rect sits in the view.
    private var documentRect: CGRect {
        let size = CGSize(width: layoutRect.width * zoom, height: layoutRect.height * zoom)
        return CGRect(x: available.midX - size.width / 2, y: available.midY - size.height / 2,
                      width: size.width, height: size.height).integral
    }

    /// The canvas including the shape being drawn, so the background grows while drawing.
    private var liveCanvas: CGRect {
        guard let draft else { return model.canvasRect }
        return model.canvasRect.union(
            CanvasLayout.canvasRect(image: model.imageBounds, annotationBounds: [renderer.bounds(of: draft)], padding: 0)
        )
    }

    private func imagePoint(_ event: NSEvent) -> CGPoint {
        imagePoint(convert(event.locationInWindow, from: nil))
    }

    private func imagePoint(_ p: CGPoint) -> CGPoint {
        let doc = documentRect
        return CGPoint(x: layoutRect.minX + (p.x - doc.minX) / zoom, y: layoutRect.minY + (p.y - doc.minY) / zoom)
    }

    private func viewPoint(_ p: CGPoint) -> CGPoint {
        let doc = documentRect
        return CGPoint(x: doc.minX + (p.x - layoutRect.minX) * zoom, y: doc.minY + (p.y - layoutRect.minY) * zoom)
    }

    private func viewRect(_ rect: CGRect) -> CGRect {
        let origin = viewPoint(rect.origin)
        return CGRect(x: origin.x, y: origin.y, width: rect.width * zoom, height: rect.height * zoom)
    }

    override func setFrameSize(_ newSize: NSSize) {
        commitTextEditing()
        super.setFrameSize(newSize)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSGradient(starting: NSColor(white: 0.17, alpha: 1), ending: NSColor(white: 0.09, alpha: 1))?
            .draw(in: bounds, angle: -90)

        let canvas = liveCanvas
        let canvasInView = viewRect(canvas)
        let transparent = model.background.fill == .none && canvas != model.imageBounds
        if transparent {
            drawCheckerboard(in: canvasInView)
        } else {
            // The document floats on the backdrop with a soft shadow.
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
            shadow.shadowBlurRadius = 24
            shadow.shadowOffset = NSSize(width: 0, height: -6)
            shadow.set()
            NSColor.black.setFill()
            let radius = canvas == model.imageBounds ? model.background.cornerRadius * zoom : 0
            NSBezierPath(roundedRect: canvasInView, xRadius: radius, yRadius: radius).fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        let doc = documentRect
        transform.translateX(by: doc.minX, yBy: doc.minY)
        transform.scale(by: zoom)
        transform.translateX(by: -layoutRect.minX, yBy: -layoutRect.minY)
        transform.concat()
        NSBezierPath(rect: canvas).addClip()
        renderer.drawBase(canvas: canvas, background: model.background)
        let numbers = model.stepNumbers
        renderer.draw(model.annotations.filter { $0.id != editingText?.id }, stepNumbers: numbers)
        if let draft {
            renderer.draw(draft, number: numbers.count + 1)
        }
        NSGraphicsContext.restoreGraphicsState()

        if let crop = cropDraft ?? model.crop {
            let visible = viewRect(crop)
            let dim = NSBezierPath(rect: canvasInView)
            dim.append(NSBezierPath(rect: visible))
            dim.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(0.55).setFill()
            dim.fill()
            NSColor.white.setStroke()
            NSBezierPath(rect: visible.insetBy(dx: 0.5, dy: 0.5)).stroke()
        }

        if let selected = model.selected, editingText == nil {
            drawSelection(selected)
        }
    }

    private func drawCheckerboard(in rect: CGRect) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        NSColor(white: 0.85, alpha: 1).setFill()
        rect.fill()
        NSColor(white: 0.7, alpha: 1).setFill()
        let cell: CGFloat = 8
        var y = rect.minY
        var row = 0
        while y < rect.maxY {
            var x = rect.minX + (row.isMultiple(of: 2) ? 0 : cell)
            while x < rect.maxX {
                CGRect(x: x, y: y, width: cell, height: cell).fill()
                x += cell * 2
            }
            y += cell
            row += 1
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawSelection(_ annotation: Annotation) {
        let handles = annotation.handles()
        if handles.isEmpty || handles.count == 8 {
            let outline = NSBezierPath(rect: viewRect(renderer.bounds(of: annotation)).insetBy(dx: -3, dy: -3))
            outline.setLineDash([4, 3], count: 2, phase: 0)
            outline.lineWidth = 1
            NSColor.controlAccentColor.setStroke()
            outline.stroke()
        }
        for (_, point) in handles {
            let center = viewPoint(point)
            let dot = NSBezierPath(ovalIn: CGRect(x: center.x - handleRadius, y: center.y - handleRadius,
                                                  width: handleRadius * 2, height: handleRadius * 2))
            NSColor.white.setFill()
            dot.fill()
            NSColor.controlAccentColor.setStroke()
            dot.lineWidth = 1.5
            dot.stroke()
        }
    }

    override func resetCursorRects() {
        let cursor: NSCursor = switch model.tool {
        case .select: .arrow
        case .text: .iBeam
        default: .crosshair
        }
        addCursorRect(bounds, cursor: cursor)
        if model.tool == .select, let selected = model.selected {
            for (handle, point) in selected.handles() {
                let c = viewPoint(point)
                let rect = CGRect(x: c.x - handleRadius - 2, y: c.y - handleRadius - 2,
                                  width: (handleRadius + 2) * 2, height: (handleRadius + 2) * 2)
                addCursorRect(rect, cursor: resizeCursor(for: handle))
            }
        }
    }

    private func resizeCursor(for handle: Annotation.Handle) -> NSCursor {
        switch handle {
        case .box(.left), .box(.right): .resizeLeftRight
        case .box(.top), .box(.bottom): .resizeUpDown
        default: .crosshair
        }
    }

    // MARK: Mouse

    private func handle(at viewLocation: CGPoint) -> Annotation.Handle? {
        guard model.tool == .select, let selected = model.selected else { return nil }
        return selected.handles().first { _, point in
            let c = viewPoint(point)
            return hypot(c.x - viewLocation.x, c.y - viewLocation.y) <= handleRadius + 3
        }?.0
    }

    override func mouseDown(with event: NSEvent) {
        commitTextEditing()
        window?.makeFirstResponder(self)
        frozenLayout = model.canvasRect
        let location = convert(event.locationInWindow, from: nil)
        let point = imagePoint(location)

        switch model.tool {
        case .select:
            if let handle = handle(at: location), let selected = model.selected {
                drag = .resize(handle, start: point, original: selected)
                return
            }
            let hit = renderer.hitTest(model.annotations, at: point)
            if event.clickCount == 2, let hit, case .text = hit.shape {
                beginTextEditing(hit, existing: true)
                return
            }
            model.selectedID = hit?.id
            if let hit { drag = .move(start: point, original: hit) }
        case .text:
            if let hit = renderer.hitTest(model.annotations, at: point), case .text = hit.shape {
                beginTextEditing(hit, existing: true)
            } else {
                beginTextEditing(newAnnotation(.text(origin: point, string: "")), existing: false)
            }
        case .step:
            model.add(newAnnotation(.step(center: point)))
        case .crop:
            drag = .crop(start: point)
            cropDraft = CGRect(origin: point, size: .zero)
        case .pen:
            drag = .draw(start: point)
            draft = newAnnotation(.pen(points: [point]))
        case .marker:
            drag = .draw(start: point)
            draft = newAnnotation(.marker(points: [point]))
        default:
            drag = .draw(start: point)
            draft = makeDraft(from: point, to: point, shift: false)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag else { return }
        let point = imagePoint(event)
        let shift = event.modifierFlags.contains(.shift)

        switch drag {
        case .move(let start, let original):
            model.previewEdit(original.moved(by: CGVector(dx: point.x - start.x, dy: point.y - start.y)))
        case .resize(let handle, let start, let original):
            var target = point
            if shift, case .arrow(let a, let b) = original.shape {
                target = AnnotationGeometry.snapped(point, from: handle == .start ? b : a)
            } else if shift, case .line(let a, let b) = original.shape {
                target = AnnotationGeometry.snapped(point, from: handle == .start ? b : a)
            }
            model.previewEdit(original.resized(handle, by: CGVector(dx: target.x - start.x, dy: target.y - start.y)))
        case .crop(let start):
            cropDraft = AnnotationGeometry.rect(from: start, to: point, square: shift).intersection(model.canvasRect)
        case .draw(let start):
            switch draft?.shape {
            case .pen(let points): draft?.shape = .pen(points: points + [point])
            case .marker(let points): draft?.shape = .marker(points: points + [point])
            default: draft = makeDraft(from: start, to: point, shift: shift)
            }
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            drag = nil
            draft = nil
            cropDraft = nil
            frozenLayout = nil
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
        }
        switch drag {
        case .move(_, let original):
            model.finishEdit(from: original, actionName: "Move")
        case .resize(_, _, let original):
            model.finishEdit(from: original, actionName: "Resize")
        case .crop:
            if let cropDraft, cropDraft.width >= 4, cropDraft.height >= 4 { model.setCrop(cropDraft) }
        case .draw:
            if let draft, isUsable(draft) { model.addDrawn(draft) }
        case nil:
            break
        }
    }

    private func newAnnotation(_ shape: Annotation.Shape) -> Annotation {
        Annotation(shape: shape, color: model.color, width: model.width)
    }

    private func makeDraft(from a: CGPoint, to b: CGPoint, shift: Bool) -> Annotation? {
        let shape: Annotation.Shape? = switch model.tool {
        case .arrow: .arrow(from: a, to: shift ? AnnotationGeometry.snapped(b, from: a) : b)
        case .line: .line(from: a, to: shift ? AnnotationGeometry.snapped(b, from: a) : b)
        case .rectangle: .rectangle(AnnotationGeometry.rect(from: a, to: b, square: shift))
        case .ellipse: .ellipse(AnnotationGeometry.rect(from: a, to: b, square: shift))
        case .blur: .blur(AnnotationGeometry.rect(from: a, to: b, square: shift))
        case .pixelate: .pixelate(AnnotationGeometry.rect(from: a, to: b, square: shift))
        case .redact: .redact(AnnotationGeometry.rect(from: a, to: b, square: shift))
        default: nil
        }
        return shape.map(newAnnotation)
    }

    /// Ignores accidental clicks that would leave invisible annotations.
    private func isUsable(_ annotation: Annotation) -> Bool {
        switch annotation.shape {
        case .arrow(let a, let b), .line(let a, let b): hypot(b.x - a.x, b.y - a.y) >= 4
        case .rectangle(let r), .ellipse(let r), .blur(let r), .pixelate(let r), .redact(let r): r.width >= 3 && r.height >= 3
        case .pen, .marker, .text, .step: true
        }
    }

    // MARK: Text

    private func beginTextEditing(_ annotation: Annotation, existing: Bool) {
        guard case .text(let origin, let string) = annotation.shape else { return }
        editingText = annotation
        editingExisting = existing

        let field = NSTextField(string: string)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: annotation.fontSize * zoom, weight: .semibold)
        field.textColor = NSColor(cgColor: annotation.color.cgColor)
        field.delegate = self
        field.placeholderString = "Text"
        let start = viewPoint(origin)
        let fieldOrigin = CGPoint(x: start.x - 2, y: start.y - 1)
        field.frame = CGRect(origin: fieldOrigin, size: CGSize(width: max(bounds.maxX - fieldOrigin.x - 8, 60),
                                                                height: annotation.fontSize * zoom * 1.35))
        addSubview(field)
        textField = field
        window?.makeFirstResponder(field)
        needsDisplay = true
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        commitTextEditing()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(cancelOperation(_:)) {
            finishTextField()
            return true
        }
        return false
    }

    private func commitTextEditing() {
        guard let field = textField, var annotation = editingText, case .text(let origin, _) = annotation.shape else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        finishTextField()
        annotation.shape = .text(origin: origin, string: text)
        if editingExisting {
            if text.isEmpty {
                model.selectedID = annotation.id
                model.deleteSelected()
            } else {
                model.replace(annotation, actionName: "Edit Text")
            }
        } else if !text.isEmpty {
            model.addDrawn(annotation)
        }
    }

    private func finishTextField() {
        textField?.delegate = nil
        textField?.removeFromSuperview()
        textField = nil
        editingText = nil
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        switch event.keyCode {
        case 51, 117: // Delete, Forward Delete
            model.deleteSelected()
            return
        case 53: // Esc: cancel the drag, then deselect
            if drag != nil {
                if case .move(_, let original)? = drag { model.previewEdit(original) }
                if case .resize(_, _, let original)? = drag { model.previewEdit(original) }
                drag = nil
                draft = nil
                cropDraft = nil
                frozenLayout = nil
                needsDisplay = true
            } else {
                model.selectedID = nil
            }
            return
        case 123, 124, 125, 126: // Arrows nudge the selection
            guard let selected = model.selected else { break }
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            let delta: CGVector = switch event.keyCode {
            case 123: CGVector(dx: -step, dy: 0)
            case 124: CGVector(dx: step, dy: 0)
            case 125: CGVector(dx: 0, dy: step)
            default: CGVector(dx: 0, dy: -step)
            }
            model.replace(selected.moved(by: delta), actionName: "Move")
            return
        default:
            break
        }

        // Tools by physical key, so they work in any keyboard layout (e.g. Russian).
        if modifiers.isEmpty, let tool = EditorTool.forKeyCode(event.keyCode) {
            model.tool = tool
            return
        }
        super.keyDown(with: event)
    }

    // Responder-chain actions from the main menu: ⌘Z, ⇧⌘Z, ⌘C, ⌘S, Delete.
    @objc func undo(_ sender: Any?) { model.undo() }
    @objc func redo(_ sender: Any?) { model.redo() }
    @objc func copy(_ sender: Any?) { onCopy() }
    @objc func saveDocument(_ sender: Any?) { onSave() }
    @objc func delete(_ sender: Any?) { model.deleteSelected() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(undo(_:)):
            menuItem.title = model.undoManager.undoMenuItemTitle
            return model.undoManager.canUndo
        case #selector(redo(_:)):
            menuItem.title = model.undoManager.redoMenuItemTitle
            return model.undoManager.canRedo
        case #selector(delete(_:)):
            return model.selected != nil
        default:
            return true
        }
    }
}
