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
    var selectedID: UUID? { didSet { onChange?() } }

    var tool: EditorTool = EditorPrefs.tool {
        didSet {
            EditorPrefs.tool = tool
            if tool != .select { selectedID = nil }
            onChange?()
        }
    }

    var color: RGBA = EditorPrefs.color {
        didSet {
            EditorPrefs.color = color
            restyleSelection { $0.color = color }
        }
    }

    var size: AnnotationSize = EditorPrefs.size {
        didSet {
            EditorPrefs.size = size
            restyleSelection { $0.size = size }
        }
    }

    /// Transient status shown in the toolbar ("Copied", "Saved").
    var status: String?

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

    // MARK: Changes (undoable)

    func add(_ annotation: Annotation) {
        commit("Add \(annotationName(annotation))") { $0.annotations.append(annotation) }
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

    /// Moves an annotation live while dragging, without an undo step per mouse event.
    func previewMove(_ annotation: Annotation) {
        guard let index = annotations.firstIndex(where: { $0.id == annotation.id }) else { return }
        annotations[index] = annotation
        onChange?()
    }

    /// Records a finished drag as one undo step, from `original` to the current state.
    func finishMove(from original: Annotation) {
        guard let moved = annotations.first(where: { $0.id == original.id }), moved != original else { return }
        previewMove(original)
        replace(moved, actionName: "Move")
    }

    private func restyleSelection(_ change: (inout Annotation) -> Void) {
        guard var annotation = selected else { return }
        change(&annotation)
        replace(annotation, actionName: "Change Style")
    }

    private func commit(_ actionName: String, _ change: (EditorModel) -> Void) {
        let before = (annotations, crop)
        change(self)
        registerUndo(restoring: before, actionName: actionName)
        onChange?()
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
                model.onChange?()
            }
        }
        undoManager.setActionName(actionName)
    }

    private func annotationName(_ annotation: Annotation) -> String {
        switch annotation.shape {
        case .arrow: "Arrow"
        case .line: "Line"
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .text: "Text"
        case .marker: "Marker"
        case .step: "Step"
        case .blur: "Blur"
        case .pixelate: "Pixelate"
        case .redact: "Redaction"
        }
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

/// Last used tool, color and size, remembered between editor windows and launches.
enum EditorPrefs {
    private static var defaults: UserDefaults { .standard }

    static var tool: EditorTool {
        get { EditorTool(rawValue: defaults.string(forKey: "editorTool") ?? "") ?? .arrow }
        set { defaults.set(newValue == .crop ? EditorTool.arrow.rawValue : newValue.rawValue, forKey: "editorTool") }
    }

    static var color: RGBA {
        get { RGBA.palette[min(max(defaults.integer(forKey: "editorColorIndex"), 0), RGBA.palette.count - 1)] }
        set { defaults.set(RGBA.palette.firstIndex(of: newValue) ?? 0, forKey: "editorColorIndex") }
    }

    static var size: AnnotationSize {
        get { AnnotationSize(rawValue: defaults.integer(forKey: "editorSize")) ?? .medium }
        set { defaults.set(newValue.rawValue, forKey: "editorSize") }
    }
}
