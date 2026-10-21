import SwiftUI

struct EditorActions {
    var copy: () -> Void
    var save: () -> Void
    var pin: () -> Void
    var done: () -> Void
}

/// The canvas fills the window; tools float on top and actions at the bottom, on glass.
struct EditorView: View {
    @Bindable var model: EditorModel
    let canvas: EditorCanvasView
    let actions: EditorActions

    private static let toolGroups: [[EditorTool]] = [
        [.select],
        [.arrow, .line, .rectangle, .ellipse],
        [.text, .pen, .marker, .step],
        [.blur, .pixelate, .redact],
        [.crop],
    ]

    var body: some View {
        ZStack {
            CanvasRepresentable(canvas: canvas)

            VStack(spacing: 0) {
                toolbar
                    .padding(.top, 10)
                Spacer()
                ZStack(alignment: .bottom) {
                    if let status = model.status {
                        StatusToast(text: status)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    HStack(alignment: .bottom) {
                        styleBar
                        Spacer()
                        actionBar
                    }
                }
                .padding(16)
            }
            .animation(.snappy(duration: 0.25), value: model.status)
        }
        .ignoresSafeArea()
        .frame(minWidth: 980, minHeight: 520)
    }

    // MARK: Toolbar

    private var toolbar: some View {
        GlassGroup {
            HStack(spacing: 10) {
                ForEach(Array(Self.toolGroups.enumerated()), id: \.offset) { index, group in
                    if index > 0 { GlassDivider() }
                    HStack(spacing: 2) {
                        ForEach(group) { tool in
                            ToolButton(tool: tool, isSelected: model.tool == tool) { model.tool = tool }
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .glassPanel(in: Capsule())
        }
    }

    /// Color and width, bottom left, close to where the eye is while drawing.
    private var styleBar: some View {
        GlassGroup {
            HStack(spacing: 10) {
                colors
                GlassDivider()
                widthControl
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassPanel(in: Capsule())
        }
    }

    private var colors: some View {
        HStack(spacing: 5) {
            ForEach(RGBA.palette, id: \.self) { color in
                ColorSwatch(color: color, isSelected: model.color == color) { model.color = color }
            }
            ColorPicker("Custom color", selection: Binding(
                get: { Color(cgColor: model.color.cgColor) },
                set: { if let rgba = RGBA($0) { model.color = rgba } }
            ), supportsOpacity: false)
            .labelsHidden()
            .controlSize(.small)
            .help("Custom color")
        }
    }

    private var widthControl: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(cgColor: model.color.cgColor))
                .frame(width: min(max(model.width, 3), 18), height: min(max(model.width, 3), 18))
                .frame(width: 20, height: 20)
            Slider(value: $model.width, in: StrokeWidth.range) { editing in
                if !editing { model.endWidthChange() }
            }
            .controlSize(.small)
            .frame(width: 96)
            Text("\(Int(model.width.rounded()))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .leading)
        }
        .help("Line width — text and steps scale with it")
    }

    // MARK: Actions

    private var actionBar: some View {
        GlassGroup {
            HStack(spacing: 4) {
                IconButton(symbol: "arrow.uturn.backward", help: "Undo (⌘Z)", action: model.undo)
                    .disabled(!model.canUndo)
                IconButton(symbol: "arrow.uturn.forward", help: "Redo (⇧⌘Z)", action: model.redo)
                    .disabled(!model.canRedo)
                if model.crop != nil {
                    GlassDivider()
                    IconButton(symbol: "crop.rotate", help: "Reset crop") { model.setCrop(nil) }
                }
                GlassDivider()
                IconButton(symbol: "doc.on.doc", help: "Copy to clipboard (⌘C)", action: actions.copy)
                IconButton(symbol: "square.and.arrow.down", help: "Save to the capture folder (⌘S)", action: actions.save)
                IconButton(symbol: "pin", help: "Pin to screen", action: actions.pin)
                DoneButton(action: actions.done)
                    .padding(.leading, 4)
            }
            .padding(6)
            .glassPanel(in: Capsule())
        }
    }
}

// MARK: - Pieces

private struct ToolButton: View {
    let tool: EditorTool
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: tool.symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 32, height: 32)
                .foregroundStyle(isSelected ? Accent.foreground : Color.primary)
                .background {
                    if isSelected {
                        Circle().fill(Color.accentColor)
                    } else if isHovered {
                        Circle().fill(Color.primary.opacity(0.1))
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("\(tool.title)  \(tool.keyLabel)")
        .animation(.snappy(duration: 0.15), value: isSelected)
    }
}

private struct ColorSwatch: View {
    let color: RGBA
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(cgColor: color.cgColor))
                .frame(width: 16, height: 16)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
                .padding(3)
                .overlay(Circle().strokeBorder(isSelected ? Color.primary : .clear, lineWidth: 1.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.15), value: isSelected)
    }
}

private struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.primary.opacity(isHovered && isEnabled ? 0.1 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.35)
        .onHover { isHovered = $0 }
        .help(help)
    }
}

private struct DoneButton: View {
    let action: () -> Void

    var body: some View {
        if #available(macOS 26.0, *) {
            Button("Done", action: action)
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Copy or save per your “After Capture” settings and close (⌘↩)")
        } else {
            Button("Done", action: action)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Copy or save per your “After Capture” settings and close (⌘↩)")
        }
    }
}

private struct StatusToast: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.callout.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassPanel(in: Capsule())
    }
}

private struct GlassDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.15))
            .frame(width: 1, height: 20)
    }
}

/// Groups glass shapes so they blend together on macOS 26+.
private struct GlassGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer { content }
        } else {
            content
        }
    }
}

private enum Accent {
    /// Icon color on the accent fill: dark on light accents (yellow), white otherwise.
    static var foreground: Color {
        guard let rgb = NSColor.controlAccentColor.usingColorSpace(.sRGB) else { return .white }
        let luminance = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return luminance > 0.6 ? Color.black.opacity(0.85) : .white
    }
}

extension View {
    /// Liquid Glass on macOS 26+, a translucent material with a hairline and shadow before.
    @ViewBuilder
    func glassPanel(in shape: some Shape) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        }
    }
}

extension RGBA {
    init?(_ color: Color) {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        self.init(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
    }
}

private struct CanvasRepresentable: NSViewRepresentable {
    let canvas: EditorCanvasView

    func makeNSView(context: Context) -> EditorCanvasView { canvas }
    func updateNSView(_ nsView: EditorCanvasView, context: Context) {}
}
