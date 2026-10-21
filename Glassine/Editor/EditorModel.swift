import AppKit
import Observation

/// State of one editor window: the capture, its annotations and crop, the current tool and style.
/// Every change to annotations or crop goes through `commit`, which registers undo.
@MainActor
@Observable
final class EditorModel {
    let capture: CapturedImage
    let renderer: AnnotationRenderer

    private(set) var annotations: [Annotation] = []
    private(set) var crop: CGRect?
    var selectedID: UUID? { didSet { changed() } }

    var tool: EditorTool = EditorPrefs.tool {
        didSet {
            if tool.isDrawingTool { EditorPrefs.tool = tool }
            if tool != .select { selectedID = nil }
            changed()
        }
    }

    var color: RGBA = EditorPrefs.color {
        didSet {
            EditorPrefs.color = color
            restyleSelection { $0.color = color }
        }
    }

    /// Stroke width from the slider. While the slider is dragged the selection updates live;
    /// `endWidthChange` records the whole drag as one undo step.
    var width: CGFloat = EditorPrefs.width {
        didSet {
            EditorPrefs.width = width
            guard var annotation = selected else { return }
            if widthEditOriginal == nil { widthEditOriginal = annotation }
            annotation.width = width
            previewEdit(annotation)
        }
    }
    @ObservationIgnored private var widthEditOriginal: Annotation?

    /// Transient status shown in the editor ("Copied", "Saved").
    var status: String?

    /// Bumped on every change, so SwiftUI refreshes undo/redo availability.
    private(set) var revision = 0

    @ObservationIgnored let undoManager = UndoManager()
    /// Lets the canvas redraw after any change.
    @ObservationIgnored var onChange: (() -> Void)?

    init(capture: CapturedImage) {
        self.capture = capture
        self.renderer = AnnotationRenderer(image: capture.image, pointSize: capture.pointSize)
    }

    var imageSize: CGSize { capture.pointSize }

    var selected: Annotation? { annotations.first { $0.id == selectedID } }

    var stepNumbers: [UUID: Int] { AnnotationGeometry.stepNumbers(annotations) }

    var canUndo: Bool { _ = revision; return undoManager.canUndo }
    var canRedo: Bool { _ = revision; return undoManager.canRedo }

    func undo() { if undoManager.canUndo { undoManager.undo() } }
    func redo() { if undoManager.canRedo { undoManager.redo() } }

    // MARK: Changes (undoable)

    func add(_ annotation: Annotation) {
        commit("Add \(annotation.name)") { $0.annotations.append(annotation) }
    }

    /// Adds a freshly drawn shape; for one-shot tools switches to Select with it selected.
    func addDrawn(_ annotation: Annotation) {
        add(annotation)
        if tool.switchesToSelectAfterDrawing {
            tool = .select
            selectedID = annotation.id
        }
    }

    func replace(_ annotation: Annotation, actionName: String = "Edit") {
        guard let index = annotations.firstIndex(where: { $0.id == annotation.id }) else { return }
        commit(actionName) { $0.annotations[index] = annotation }
    }

    func deleteSelected() {
        guard let selectedID else { return }
        commit("Delete") { $0.annotations.removeAll { $0.id == selectedID } }
        self.selectedID = nil
    }

    func setCrop(_ rect: CGRect?) {
        let bounds = CGRect(origin: .zero, size: imageSize)
        let clipped = rect.map { $0.intersection(bounds).integral }
        commit(clipped == nil ? "Reset Crop" : "Crop") {
            $0.crop = (clipped?.isEmpty ?? true) || clipped == bounds ? nil : clipped
        }
    }

    /// Updates an annotation live while dragging, without an undo step per mouse event.
    func previewEdit(_ annotation: Annotation) {
        guard let index = annotations.firstIndex(where: { $0.id == annotation.id }) else { return }
        annotations[index] = annotation
        changed()
    }

    /// Records a finished drag (move or resize) as one undo step, from `original` to now.
    func finishEdit(from original: Annotation, actionName: String) {
        guard let edited = annotations.first(where: { $0.id == original.id }), edited != original else { return }
        previewEdit(original)
        replace(edited, actionName: actionName)
    }

    /// Called when the width slider is released.
    func endWidthChange() {
        guard let original = widthEditOriginal else { return }
        widthEditOriginal = nil
        finishEdit(from: original, actionName: "Change Width")
    }

    private func restyleSelection(_ change: (inout Annotation) -> Void) {
        guard var annotation = selected else { return }
        change(&annotation)
        replace(annotation, actionName: "Change Color")
    }

    private func changed() {
        revision += 1
        onChange?()
    }

    private func commit(_ actionName: String, _ change: (EditorModel) -> Void) {
        let before = (annotations, crop)
        change(self)
        registerUndo(restoring: before, actionName: actionName)
        changed()
    }

    private func registerUndo(restoring state: ([Annotation], CGRect?), actionName: String) {
        undoManager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                let current = (model.annotations, model.crop)
                (model.annotations, model.crop) = state
                if let selected = model.selectedID, !model.annotations.contains(where: { $0.id == selected }) {
                    model.selectedID = nil
                }
                model.registerUndo(restoring: current, actionName: actionName)
                model.changed()
            }
        }
        undoManager.setActionName(actionName)
    }

    // MARK: Export

    /// The final image: capture, annotations and crop, at the capture's full resolution.
    func renderedImage() -> CGImage? {
        renderer.render(annotations: annotations, stepNumbers: stepNumbers, crop: crop, scale: capture.scale)
    }

    /// A new capture of the edited image, keeping the original's screen position (for pins).
    func renderedCapture() throws -> CapturedImage {
        guard let image = renderedImage() else { throw CocoaError(.fileWriteUnknown) }
        let result = try CapturedImage(image: image, scale: capture.scale)
        if let source = capture.sourceFrame {
            let area = crop ?? CGRect(origin: .zero, size: imageSize)
            result.sourceFrame = CGRect(
                x: source.minX + area.minX, y: source.maxY - area.maxY,
                width: area.width, height: area.height
            )
        }
        return result
    }
}

extension Annotation {
    var name: String {
        switch shape {
        case .arrow: "Arrow"
        case .line: "Line"
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .text: "Text"
        case .pen: "Drawing"
        case .marker: "Marker"
        case .step: "Step"
        case .blur: "Blur"
        case .pixelate: "Pixelate"
        case .redact: "Redaction"
        }
    }
}

/// Last used drawing tool, color and width, remembered between editor windows and launches.
enum EditorPrefs {
    private static var defaults: UserDefaults { .standard }

    static var tool: EditorTool {
        get { EditorTool(rawValue: defaults.string(forKey: "editorTool") ?? "") ?? .arrow }
        set { defaults.set(newValue.rawValue, forKey: "editorTool") }
    }

    static var color: RGBA {
        get {
            guard let c = defaults.array(forKey: "editorColor") as? [Double], c.count == 3 else { return RGBA.palette[0] }
            return RGBA(red: c[0], green: c[1], blue: c[2])
        }
        set { defaults.set([newValue.red, newValue.green, newValue.blue].map(Double.init), forKey: "editorColor") }
    }

    static var width: CGFloat {
        get {
            let value = defaults.double(forKey: "editorWidth")
            return value > 0 ? min(max(value, StrokeWidth.range.lowerBound), StrokeWidth.range.upperBound) : StrokeWidth.default
        }
        set { defaults.set(Double(newValue), forKey: "editorWidth") }
    }
}
