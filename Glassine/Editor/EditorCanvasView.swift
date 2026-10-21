import AppKit

/// The editing surface: shows the capture fitted to the view and turns mouse and keyboard
/// input into annotations. All drawing goes through `AnnotationRenderer`.
@MainActor
final class EditorCanvasView: NSView, NSTextFieldDelegate {
    private let model: EditorModel
    private var renderer: AnnotationRenderer { model.renderer }

    var onCopy: () -> Void = {}
    var onSave: () -> Void = {}

    private var dragStart: CGPoint?
    private var draft: Annotation?
    private var cropDraft: CGRect?
    private var moveOriginal: Annotation?

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

    /// Fits the image with a margin; small captures may grow up to 2× so they're easy to annotate.
    private var zoom: CGFloat {
        let margin: CGFloat = 32
        let size = model.imageSize
        return max(min((bounds.width - margin * 2) / size.width, (bounds.height - margin * 2) / size.height, 2), 0.05)
    }

    private var imageRect: CGRect {
        let size = CGSize(width: model.imageSize.width * zoom, height: model.imageSize.height * zoom)
        return CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                      width: size.width, height: size.height).integral
    }

    private func imagePoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: (p.x - imageRect.minX) / zoom, y: (p.y - imageRect.minY) / zoom)
    }

    private func viewRect(_ rect: CGRect) -> CGRect {
        CGRect(x: imageRect.minX + rect.minX * zoom, y: imageRect.minY + rect.minY * zoom,
               width: rect.width * zoom, height: rect.height * zoom)
    }

    override func setFrameSize(_ newSize: NSSize) {
        commitTextEditing()
        super.setFrameSize(newSize)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.13, alpha: 1).setFill()
        bounds.fill()

        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: imageRect.minX, yBy: imageRect.minY)
        transform.scale(by: zoom)
        transform.concat()
        NSBezierPath(rect: renderer.imageBounds).addClip()
        renderer.drawImage()
        let numbers = model.stepNumbers
        renderer.draw(model.annotations.filter { $0.id != editingText?.id }, stepNumbers: numbers)
        if let draft {
            renderer.draw(draft, number: numbers.count + 1)
        }
        NSGraphicsContext.restoreGraphicsState()

        if let crop = cropDraft ?? model.crop {
            let visible = viewRect(crop)
            let dim = NSBezierPath(rect: imageRect)
            dim.append(NSBezierPath(rect: visible))
            dim.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(0.55).setFill()
            dim.fill()
            NSColor.white.setStroke()
            NSBezierPath(rect: visible.insetBy(dx: 0.5, dy: 0.5)).stroke()
        }

        if let selected = model.selected {
            let outline = NSBezierPath(rect: viewRect(renderer.bounds(of: selected)).insetBy(dx: -4, dy: -4))
            outline.setLineDash([4, 3], count: 2, phase: 0)
            outline.lineWidth = 1
            NSColor.controlAccentColor.setStroke()
            outline.stroke()
        }
    }

    override func resetCursorRects() {
        let cursor: NSCursor = switch model.tool {
        case .select: .arrow
        case .text: .iBeam
        default: .crosshair
        }
        addCursorRect(imageRect, cursor: cursor)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        commitTextEditing()
        window?.makeFirstResponder(self)
        let point = imagePoint(event)
        dragStart = point

        switch model.tool {
        case .select:
            let hit = renderer.hitTest(model.annotations, at: point)
            if event.clickCount == 2, let hit, case .text = hit.shape {
                beginTextEditing(hit, existing: true)
                return
            }
            model.selectedID = hit?.id
            moveOriginal = hit
        case .text:
            if let hit = renderer.hitTest(model.annotations, at: point), case .text = hit.shape {
                beginTextEditing(hit, existing: true)
            } else {
                beginTextEditing(Annotation(shape: .text(origin: point, string: ""), color: model.color, size: model.size), existing: false)
            }
        case .step:
            model.add(Annotation(shape: .step(center: point), color: model.color, size: model.size))
        case .crop:
            cropDraft = CGRect(origin: point, size: .zero)
        case .marker:
            draft = Annotation(shape: .marker(points: [point]), color: model.color, size: model.size)
        default:
            draft = makeDraft(from: point, to: point, shift: false)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let point = imagePoint(event)
        let shift = event.modifierFlags.contains(.shift)

        switch model.tool {
        case .select:
            if let moveOriginal {
                model.previewMove(moveOriginal.moved(by: CGVector(dx: point.x - start.x, dy: point.y - start.y)))
            }
        case .crop:
            cropDraft = AnnotationGeometry.rect(from: start, to: point, square: shift).intersection(renderer.imageBounds)
        case .marker:
            if case .marker(let points)? = draft?.shape {
                draft?.shape = .marker(points: points + [point])
            }
        case .text, .step:
            break
        default:
            draft = makeDraft(from: start, to: point, shift: shift)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStart = nil
            draft = nil
            cropDraft = nil
            moveOriginal = nil
            needsDisplay = true
        }
        if let moveOriginal {
            model.finishMove(from: moveOriginal)
        }
        if let cropDraft, cropDraft.width >= 4, cropDraft.height >= 4 {
            model.setCrop(cropDraft)
        }
        if let draft, isUsable(draft) {
            model.add(draft)
        }
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
        return shape.map { Annotation(shape: $0, color: model.color, size: model.size) }
    }

    /// Ignores accidental clicks that would leave invisible annotations.
    private func isUsable(_ annotation: Annotation) -> Bool {
        switch annotation.shape {
        case .arrow(let a, let b), .line(let a, let b): hypot(b.x - a.x, b.y - a.y) >= 4
        case .rectangle(let r), .ellipse(let r), .blur(let r), .pixelate(let r), .redact(let r): r.width >= 3 && r.height >= 3
        case .marker, .text, .step: true
        }
    }

    // MARK: Text

    private func beginTextEditing(_ annotation: Annotation, existing: Bool) {
        guard case .text(let origin, let string) = annotation.shape else { return }
        editingText = annotation
        editingExisting = existing
        model.selectedID = nil

        let field = NSTextField(string: string)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: annotation.size.fontSize * zoom, weight: .semibold)
        field.textColor = NSColor(cgColor: annotation.color.cgColor)
        field.delegate = self
        field.placeholderString = "Text"
        let fieldOrigin = CGPoint(x: imageRect.minX + origin.x * zoom - 2, y: imageRect.minY + origin.y * zoom - 1)
        field.frame = CGRect(origin: fieldOrigin, size: CGSize(width: max(bounds.maxX - fieldOrigin.x - 8, 60),
                                                           height: annotation.size.fontSize * zoom * 1.35))
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
            cancelTextEditing()
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
            model.add(annotation)
        }
    }

    private func cancelTextEditing() {
        finishTextField()
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
        case 53: // Esc
            if draft != nil || cropDraft != nil {
                draft = nil
                cropDraft = nil
                dragStart = nil
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

        if modifiers.isEmpty, let key = event.charactersIgnoringModifiers?.lowercased().first,
           let tool = EditorTool.allCases.first(where: { $0.key == key }) {
            model.tool = tool
            return
        }
        super.keyDown(with: event)
    }

    // Responder-chain actions from the main menu (⌘C, ⌘S, Delete).
    @objc func copy(_ sender: Any?) { onCopy() }
    @objc func saveDocument(_ sender: Any?) { onSave() }
    @objc func delete(_ sender: Any?) { model.deleteSelected() }
}
