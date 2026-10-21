import AppKit
import SwiftUI

/// Opens editor windows. While any is open Glassine shows in the Dock and ⌘-Tab, so an
/// editor can't get lost behind other apps; the icon disappears when the last one closes.
@MainActor
final class EditorController {
    private var windows: [EditorWindowController] = []

    var onPin: (CapturedImage) -> Void = { _ in }

    func open(_ capture: CapturedImage, persistsPreferences: Bool = true) {
        if windows.isEmpty {
            NSApp.setActivationPolicy(.regular)
        }
        let controller = EditorWindowController(capture: capture, editor: self, persistsPreferences: persistsPreferences)
        windows.append(controller)
        controller.show()
    }

    #if DEBUG
    /// Debug hook (`--debug-editor`): opens a crop of the main screen with one of every
    /// annotation, without the hotkey or synthetic input.
    func openDebugSample() {
        Task {
            guard let snapshot = try? await ScreenSnapshotter.snapshotAllScreens().first,
                  let image = snapshot.image.cropping(to: CGRect(x: 0, y: 0, width: snapshot.image.width / 2, height: snapshot.image.height / 2)),
                  let capture = try? CapturedImage(image: image, scale: snapshot.scale)
            else { return }
            open(capture, persistsPreferences: false)
            windows.last?.addDebugAnnotations()
        }
    }
    #endif

    fileprivate func closed(_ controller: EditorWindowController) {
        windows.removeAll { $0 === controller }
        if windows.isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    fileprivate func pin(_ capture: CapturedImage) { onPin(capture) }
}

@MainActor
private final class EditorWindowController: NSObject, NSWindowDelegate {
    private let model: EditorModel
    private let canvas: EditorCanvasView
    private let window: NSWindow
    private unowned let editor: EditorController
    private var clearStatus: Task<Void, Never>?

    init(capture: CapturedImage, editor: EditorController, persistsPreferences: Bool) {
        self.model = EditorModel(capture: capture, persistsPreferences: persistsPreferences)
        self.canvas = EditorCanvasView(model: model)
        self.editor = editor
        self.window = NSWindow(
            contentRect: Self.initialFrame(for: capture.pointSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()

        let actions = EditorActions(
            copy: { [weak self] in self?.copy() },
            save: { [weak self] in self?.save() },
            pin: { [weak self] in self?.pin() },
            done: { [weak self] in self?.done() }
        )
        canvas.onCopy = actions.copy
        canvas.onSave = actions.save

        window.contentViewController = NSHostingController(rootView: EditorView(model: model, canvas: canvas, actions: actions))
        window.setFrame(Self.initialFrame(for: capture.pointSize), display: false)
        window.title = capture.baseName
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(white: 0.12, alpha: 1)
        window.contentMinSize = NSSize(width: 980, height: 520)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
    }

    func show() {
        AppActivation.bringToFront()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
    }

    /// Big enough to show the capture at 1:1 when it fits, within 85 % of the screen.
    private static func initialFrame(for imageSize: CGSize) -> CGRect {
        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let chrome = CGSize(width: 64, height: 72 + 80)
        let width = min(max(imageSize.width + chrome.width, 980), visible.width * 0.85)
        let height = min(max(imageSize.height + chrome.height, 560), visible.height * 0.85)
        return CGRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height)
    }

    // MARK: Actions

    private func copy() {
        perform("Copied") { $0.copyToClipboard() }
    }

    private func save() {
        perform("Saved to \(Preferences.saveFolder.lastPathComponent)") { try $0.save() }
    }

    private func pin() {
        perform("Pinned") { editor.pin($0) }
    }

    /// Delivers the result like a fresh capture (clipboard / folder per settings) and closes.
    private func done() {
        do {
            try CaptureOutput.deliver(try model.renderedCapture())
            window.close()
        } catch {
            Alerts.present(error)
        }
    }

    private func perform(_ status: String, _ action: (CapturedImage) throws -> Void) {
        do {
            try action(try model.renderedCapture())
            model.status = status
            clearStatus?.cancel()
            clearStatus = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.model.status = nil
            }
        } catch {
            Alerts.present(error)
        }
    }

    #if DEBUG
    func addDebugAnnotations() {
        let s = model.imageSize
        let red = RGBA.palette[0], yellow = RGBA.palette[2], blue = RGBA.palette[4]
        let samples: [Annotation] = [
            Annotation(shape: .arrow(from: CGPoint(x: s.width * 0.55, y: s.height * 0.75), to: CGPoint(x: s.width * 0.35, y: s.height * 0.5)), color: red),
            Annotation(shape: .rectangle(CGRect(x: s.width * 0.05, y: s.height * 0.08, width: s.width * 0.3, height: s.height * 0.2)), color: red),
            Annotation(shape: .ellipse(CGRect(x: s.width * 0.6, y: s.height * 0.1, width: s.width * 0.25, height: s.height * 0.18)), color: blue, width: 2),
            Annotation(shape: .text(origin: CGPoint(x: s.width * 0.58, y: s.height * 0.78), string: "Glassine editor"), color: red, width: 8),
            Annotation(shape: .pen(points: (0...30).map { CGPoint(x: s.width * 0.42 + CGFloat($0) * 6, y: s.height * 0.6 + sin(CGFloat($0) / 3) * 14) }), color: blue, width: 3),
            Annotation(shape: .marker(points: (0...20).map { CGPoint(x: s.width * 0.05 + CGFloat($0) * 12, y: s.height * 0.45) }), color: yellow),
            Annotation(shape: .step(center: CGPoint(x: s.width * 0.08, y: s.height * 0.6)), color: red),
            Annotation(shape: .step(center: CGPoint(x: s.width * 0.14, y: s.height * 0.6)), color: yellow),
            Annotation(shape: .blur(CGRect(x: s.width * 0.05, y: s.height * 0.7, width: s.width * 0.15, height: s.height * 0.12)), color: red),
            Annotation(shape: .pixelate(CGRect(x: s.width * 0.22, y: s.height * 0.7, width: s.width * 0.15, height: s.height * 0.12)), color: red),
            Annotation(shape: .redact(CGRect(x: s.width * 0.4, y: s.height * 0.3, width: s.width * 0.15, height: s.height * 0.05)), color: RGBA.palette[6]),
        ]
        samples.forEach(model.add)
        // Past the right edge: the background grows to fit it.
        model.add(Annotation(shape: .arrow(from: CGPoint(x: s.width * 0.9, y: s.height * 0.35), to: CGPoint(x: s.width + 70, y: s.height * 0.2)), color: blue, width: 5))
        model.background = BackgroundSettings(fill: .gradient(0), padding: 48, cornerRadius: 14, shadow: true)
        model.endBackgroundChange()
        model.tool = .select
        model.selectedID = samples[1].id
    }
    #endif

    // MARK: NSWindowDelegate

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { model.undoManager }

    func windowWillClose(_ notification: Notification) {
        editor.closed(self)
    }
}
