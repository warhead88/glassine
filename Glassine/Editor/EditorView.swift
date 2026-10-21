import SwiftUI

struct EditorActions {
    var copy: () -> Void
    var save: () -> Void
    var pin: () -> Void
    var done: () -> Void
}

/// Toolbar on top, canvas below.
struct EditorView: View {
    @Bindable var model: EditorModel
    let canvas: EditorCanvasView
    let actions: EditorActions

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            Divider()
            CanvasRepresentable(canvas: canvas)
        }
        .frame(minWidth: 900, minHeight: 420)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                ForEach(EditorTool.allCases) { tool in
                    Button {
                        model.tool = tool
                    } label: {
                        Image(systemName: tool.symbol)
                            .frame(width: 28, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(model.tool == tool ? Color.accentColor.opacity(0.25) : .clear,
                                in: RoundedRectangle(cornerRadius: 6))
                    .help("\(tool.title) (\(String(tool.key).uppercased()))")
                }
            }

            Divider().frame(height: 20)

            HStack(spacing: 6) {
                ForEach(RGBA.palette, id: \.self) { color in
                    Circle()
                        .fill(Color(cgColor: color.cgColor))
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(model.color == color ? Color.primary : Color.secondary.opacity(0.4),
                                                 lineWidth: model.color == color ? 2 : 1))
                        .contentShape(Circle())
                        .onTapGesture { model.color = color }
                }
            }

            Picker("Size", selection: $model.size) {
                ForEach(AnnotationSize.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 96)
            .help("Size")

            Spacer(minLength: 8)

            if let status = model.status {
                Text(status).font(.callout).foregroundStyle(.secondary)
            }
            if model.crop != nil {
                Button("Reset Crop") { model.setCrop(nil) }
            }
            HStack(spacing: 4) {
                Button(action: actions.copy) { Image(systemName: "doc.on.doc") }
                    .help("Copy to clipboard (⌘C)")
                Button(action: actions.save) { Image(systemName: "square.and.arrow.down") }
                    .help("Save to the capture folder (⌘S)")
                Button(action: actions.pin) { Image(systemName: "pin") }
                    .help("Pin to screen")
            }
            Button("Done", action: actions.done)
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .help("Apply your “After Capture” settings and close (⌘↩)")
        }
    }
}

private struct CanvasRepresentable: NSViewRepresentable {
    let canvas: EditorCanvasView

    func makeNSView(context: Context) -> EditorCanvasView { canvas }
    func updateNSView(_ nsView: EditorCanvasView, context: Context) {}
}
