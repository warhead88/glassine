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
    @State private var showsBackground = false

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
        .tooltipHost()
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
                GlassDivider()
                IconButton(symbol: "photo.artframe") { showsBackground.toggle() }
                    .background(Circle().fill(Color.accentColor.opacity(model.background != BackgroundSettings(fill: model.background.fill) ? 0.3 : 0)))
                    .tooltip("Background", "Padding, rounded corners, shadow and a background that continues the screenshot.",
                             placement: .above)
                    .popover(isPresented: $showsBackground, arrowEdge: .top) {
                        BackgroundPanel(model: model)
                    }
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
            .tooltip("Custom Color", "Pick any color from the macOS color panel.", placement: .above)
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
        .tooltip("Line Width", "Thickness of new and selected marks. Text and steps scale with it.", placement: .above)
    }

    // MARK: Actions

    private var actionBar: some View {
        GlassGroup {
            HStack(spacing: 4) {
                IconButton(symbol: "arrow.uturn.backward", action: model.undo)
                    .disabled(!model.canUndo)
                    .tooltip("Undo", "Step back through every change.", shortcut: "⌘Z", placement: .above)
                IconButton(symbol: "arrow.uturn.forward", action: model.redo)
                    .disabled(!model.canRedo)
                    .tooltip("Redo", "Bring back what you undid.", shortcut: "⇧⌘Z", placement: .above)
                if model.crop != nil {
                    GlassDivider()
                    IconButton(symbol: "crop.rotate") { model.setCrop(nil) }
                        .tooltip("Reset Crop", "Show the whole image again.", placement: .above)
                }
                GlassDivider()
                LabeledButton(symbol: "doc.on.doc", title: "Copy", action: actions.copy)
                    .tooltip("Copy", "Copy the edited image to the clipboard. Nothing is saved.", shortcut: "⌘C", placement: .above)
                LabeledButton(symbol: "square.and.arrow.down", title: "Save", action: actions.save)
                    .tooltip("Save", "Save the edited image to \(Preferences.saveFolder.lastPathComponent).", shortcut: "⌘S", placement: .above)
                LabeledButton(symbol: "pin", title: "Pin", action: actions.pin)
                    .tooltip("Pin", "Keep the edited image floating above all windows.", placement: .above)
                DoneButton(action: actions.done)
                    .padding(.leading, 4)
                    .tooltip("Done", doneDetail, shortcut: "⌘↩", placement: .above)
            }
            .padding(6)
            .glassPanel(in: Capsule())
        }
    }

    /// What Done will do with the current "After Capture" settings.
    private var doneDetail: String {
        let defaults = UserDefaults.standard
        let folder = Preferences.saveFolder.lastPathComponent
        switch (defaults.bool(forKey: PrefKey.copyToClipboard), defaults.bool(forKey: PrefKey.saveToFile)) {
        case (true, true): return "Copy to the clipboard and save to \(folder), then close."
        case (true, false): return "Copy to the clipboard, then close (saving is off in Settings)."
        case (false, true): return "Save to \(folder), then close (copying is off in Settings)."
        case (false, false): return "Close. Copy and save are both off in Settings → Output."
        }
    }
}

// MARK: - Background

private struct BackgroundPanel: View {
    @Bindable var model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Background").font(.headline)

            HStack(spacing: 8) {
                FillSwatch(fill: .extend, current: model.background.fill, help: "Continue the screenshot's edge color") {
                    RoundedRectangle(cornerRadius: 6).fill(Color(cgColor: model.renderer.edgeColor.cgColor))
                        .overlay(Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 10, weight: .bold))
                            .foregroundStyle(model.renderer.edgeColor.isLight ? Color.black.opacity(0.6) : Color.white.opacity(0.8)))
                } select: { select($0) }
                FillSwatch(fill: .none, current: model.background.fill, help: "Transparent (PNG)") {
                    Checkerboard().clipShape(RoundedRectangle(cornerRadius: 6))
                } select: { select($0) }
                ForEach(BackgroundSettings.solidColors, id: \.self) { color in
                    FillSwatch(fill: .color(color), current: model.background.fill, help: "Solid color") {
                        RoundedRectangle(cornerRadius: 6).fill(Color(cgColor: color.cgColor))
                    } select: { select($0) }
                }
            }
            HStack(spacing: 8) {
                ForEach(BackgroundSettings.gradients.indices, id: \.self) { index in
                    let preset = BackgroundSettings.gradients[index]
                    FillSwatch(fill: .gradient(index), current: model.background.fill, help: preset.name) {
                        RoundedRectangle(cornerRadius: 6).fill(LinearGradient(
                            colors: [Color(cgColor: preset.from.cgColor), Color(cgColor: preset.to.cgColor)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                    } select: { select($0) }
                }
            }

            slider("Padding", value: $model.background.padding, in: BackgroundSettings.paddingRange)
            slider("Corners", value: $model.background.cornerRadius, in: BackgroundSettings.cornerRange)
            Toggle("Shadow", isOn: $model.background.shadow)
                .onChange(of: model.background.shadow) { model.endBackgroundChange() }

            Text("The background also grows by itself when arrows, text or drawings go past the edge.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 300)
    }

    private func select(_ fill: BackgroundSettings.Fill) {
        model.background.fill = fill
        model.endBackgroundChange()
    }

    private func slider(_ title: String, value: Binding<CGFloat>, in range: ClosedRange<CGFloat>) -> some View {
        HStack {
            Text(title).frame(width: 64, alignment: .leading)
            Slider(value: value, in: range) { editing in
                if !editing { model.endBackgroundChange() }
            }
            Text("\(Int(value.wrappedValue.rounded()))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
        }
    }
}

private struct FillSwatch<Preview: View>: View {
    let fill: BackgroundSettings.Fill
    let current: BackgroundSettings.Fill
    let help: String
    @ViewBuilder let preview: Preview
    let select: (BackgroundSettings.Fill) -> Void

    var body: some View {
        Button { select(fill) } label: {
            preview
                .frame(width: 30, height: 30)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5))
                .padding(2)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(fill == current ? Color.accentColor : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(white: 0.9))
            let cell: CGFloat = 5
            for row in 0..<Int(size.height / cell) + 1 {
                for col in 0..<Int(size.width / cell) + 1 where (row + col).isMultiple(of: 2) {
                    context.fill(Path(CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)),
                                 with: .color(white: 0.72))
                }
            }
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
        .tooltip(tool.title, tool.detail, shortcut: tool.keyLabel, placement: .below)
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
    }
}

private struct LabeledButton: View {
    let symbol: String
    let title: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(Capsule().fill(Color.primary.opacity(isHovered ? 0.12 : 0.06)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
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
        } else {
            Button("Done", action: action)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
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
