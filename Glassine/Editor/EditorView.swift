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
    @State private var showsBackground = Self.debugShowsBackground
    @Environment(Theme.self) private var theme

    /// Debug (`--debug-editor background`): the background panel opens with the editor.
    private static var debugShowsBackground: Bool {
        #if DEBUG
        CommandLine.arguments.contains("background")
        #else
        false
        #endif
    }

    /// Padding, corners or a shadow are set: the background button shows it.
    private var backgroundIsOn: Bool { model.background != BackgroundSettings(fill: model.background.fill) }

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
        Group {
            HStack(spacing: 10) {
                ForEach(Array(Self.toolGroups.enumerated()), id: \.offset) { index, group in
                    if index > 0 { PerforationDivider() }
                    HStack(spacing: 2) {
                        ForEach(group) { tool in
                            ToolButton(tool: tool, isSelected: model.tool == tool) { model.tool = tool }
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .paperPanel(in: Capsule())
        }
    }

    /// Color and width, bottom left, close to where the eye is while drawing.
    private var styleBar: some View {
        Group {
            HStack(spacing: 10) {
                colors
                PerforationDivider()
                widthControl
                PerforationDivider()
                IconButton(symbol: "photo.artframe") { showsBackground.toggle() }
                    .background(Circle().fill(Color.key))
                    .overlay(Circle().strokeBorder(theme.accent, lineWidth: backgroundIsOn ? 1.5 : 0))
                    .tooltip("Background", "Padding, rounded corners, shadow and a background that continues the screenshot.",
                             placement: .above)
                    .popover(isPresented: $showsBackground, arrowEdge: .top) {
                        BackgroundPanel(model: model)
                            .presentationBackground(Color.card)
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .paperPanel(in: Capsule())
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
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.ink2)
                .frame(width: 18, alignment: .leading)
        }
        .tooltip("Line Width", "Thickness of new and selected marks. Text and steps scale with it.", placement: .above)
    }

    // MARK: Actions

    private var actionBar: some View {
        Group {
            HStack(spacing: 4) {
                IconButton(symbol: "arrow.uturn.backward", action: model.undo)
                    .disabled(!model.canUndo)
                    .tooltip("Undo", "Step back through every change.", shortcut: "⌘Z", placement: .above)
                IconButton(symbol: "arrow.uturn.forward", action: model.redo)
                    .disabled(!model.canRedo)
                    .tooltip("Redo", "Bring back what you undid.", shortcut: "⇧⌘Z", placement: .above)
                if model.crop != nil {
                    PerforationDivider()
                    IconButton(symbol: "crop.rotate") { model.setCrop(nil) }
                        .tooltip("Reset Crop", "Show the whole image again.", placement: .above)
                }
                PerforationDivider()
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
            .paperPanel(in: Capsule())
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
            Text("Background")
                .font(Font(Typography.fraunces(size: 20, weight: 460)))
                .foregroundStyle(Color.ink)

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
                .font(.system(size: 12))
                .foregroundStyle(Color.ink2)
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
            Text(title).foregroundStyle(Color.ink).frame(width: 64, alignment: .leading)
            Slider(value: value, in: range) { editing in
                if !editing { model.endBackgroundChange() }
            }
            Text("\(Int(value.wrappedValue.rounded()))")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Color.ink2)
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
    @Environment(Theme.self) private var theme

    var body: some View {
        Button(action: action) {
            icon
                .frame(width: 32, height: 32)
                .foregroundStyle(isSelected ? theme.onAccent : Color.ink2)
                .background {
                    if isSelected {
                        Circle().fill(theme.accent)
                    } else if isHovered {
                        Circle().fill(Color.key)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .tooltip(tool.title, tool.detail, shortcut: tool.keyLabel, placement: .below)
        .animation(.snappy(duration: 0.15), value: isSelected)
    }

    /// The text tool is a Fraunces T, the toolbar's one serif; the rest are SF Symbols.
    @ViewBuilder
    private var icon: some View {
        if tool == .text {
            Text("T").font(Font(Typography.fraunces(size: 18, weight: 500)))
        } else {
            Image(systemName: tool.symbol).font(.system(size: 14, weight: .medium))
        }
    }
}

private struct ColorSwatch: View {
    let color: RGBA
    let isSelected: Bool
    let action: () -> Void
    @Environment(Theme.self) private var theme

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(cgColor: color.cgColor))
                .frame(width: 16, height: 16)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
                .padding(3)
                .overlay(Circle().strokeBorder(isSelected ? theme.accent : .clear, lineWidth: 2))
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
                .foregroundStyle(Color.ink2)
                .frame(width: 32, height: 32)
                .background(Circle().fill(isHovered && isEnabled ? Color.key : .clear))
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
                .foregroundStyle(Color.ink)
                .padding(.horizontal, 11)
                .frame(height: 32)
                .background(Capsule().fill(isHovered ? Color.rule : Color.key))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct DoneButton: View {
    let action: () -> Void

    var body: some View {
        Button("Done", action: action)
            .buttonStyle(.paperPrimary)
            .keyboardShortcut(.return, modifiers: .command)
    }
}

private struct StatusToast: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            CheckBadge(size: 22)
            Text(text)
                .font(Font(Typography.fraunces(size: 15, weight: 480)))
                .foregroundStyle(Color.ink)
        }
        .padding(.leading, 9)
        .padding(.trailing, 16)
        .padding(.vertical, 7)
        .paperPanel(in: Capsule())
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
