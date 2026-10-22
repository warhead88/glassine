import SwiftUI

// Visual choices for Settings: each option is a card with a small rendered preview of what
// the setting does, so it's clear before trying it.

/// A titled row of option cards, bound to any stored value.
struct OptionCards<Value: Hashable, Preview: View>: View {
    let title: String
    var note: String?
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    @ViewBuilder let preview: (Value) -> Preview

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsLabel(title)
            HStack(spacing: 12) {
                ForEach(options, id: \.value) { option in
                    OptionCard(label: option.label, isSelected: selection == option.value) {
                        selection = option.value
                    } preview: {
                        preview(option.value)
                    }
                }
            }
            if let note {
                SettingsNote(note)
            }
        }
    }
}

struct OptionCard<Preview: View>: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let preview: Preview
    @State private var isHovered = false
    @Environment(Theme.self) private var theme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                preview
                    .frame(maxWidth: .infinity)
                    .frame(height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isHovered && !isSelected ? Color.ink3 : Color.border))
                    // The selection ring sits just outside the render, like the scene's; its room is
                    // kept on every card so they line up.
                    .padding(3)
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(isSelected ? theme.accent : .clear, lineWidth: 2))
                Text(label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.ink : Color.ink2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.snappy(duration: 0.15), value: isSelected)
    }
}

// MARK: - Mini renders

/// A tiny desktop: a neutral screen with a window and a peach card. The base for most previews.
struct MiniDesktop: View {
    var dimmed = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                Color.screen
                MiniWindow().frame(width: w * 0.42, height: h * 0.44).offset(x: w * 0.09, y: h * 0.26)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.peach)
                    .frame(width: w * 0.38, height: h * 0.40)
                    .offset(x: w * 0.38, y: h * 0.46)
                if dimmed { Color.black.opacity(0.35) }
            }
        }
    }
}

struct MiniWindow: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2.5) {
                ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0.opacity(0.9)).frame(width: 4, height: 4) }
                Spacer()
            }
            .padding(.horizontal, 4)
            .frame(height: 9)
            .background(Color.key)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1).fill(Color.rule).frame(width: [34, 24, 30][i], height: 2.5)
                }
                Spacer(minLength: 0)
            }
            .padding(5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.card)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// Area capture: the dimmed screen and its frame (straight, tracing the notch, or none) —
/// drawn with the same path code as the real frame.
struct FrameStylePreview: View {
    let style: AreaFrameStyle
    var bottom = FrameBottomCorners.rounded

    var body: some View {
        ZStack {
            MiniDesktop(dimmed: true)
            Canvas { context, size in
                let notch = CGRect(x: size.width / 2 - 17, y: 0, width: 34, height: 8)
                context.fill(Path(roundedRect: notch, cornerRadius: 3), with: .color(.black))
                guard style != .off else { return }
                let path = ScreenFrame.path(in: CGRect(origin: .zero, size: size), inset: 2,
                                            notch: style == .notch ? notch : nil, bottomRadius: bottom.radius)
                context.stroke(Path(path), with: .color(.white.opacity(0.95)), lineWidth: 2)
            }
        }
    }
}

/// Close-up of the screen's bottom-left corner inside the bezel — the display itself is square
/// there — with the frame rounded or square.
struct FrameCornerPreview: View {
    let bottom: FrameBottomCorners

    var body: some View {
        GeometryReader { geo in
            let bezel: CGFloat = 12
            // The screen runs off the card at the top and right; only its bottom-left corner shows.
            let screen = CGRect(x: bezel, y: -60, width: geo.size.width + 60, height: geo.size.height - bezel + 60)
            ZStack(alignment: .topLeading) {
                Color(white: 0.1)
                Color.screen
                    .overlay(Color.black.opacity(0.35))
                    .frame(width: screen.width, height: screen.height)
                    .offset(x: screen.minX, y: screen.minY)
                Canvas { context, _ in
                    let path = ScreenFrame.path(in: screen, inset: 2, notch: nil, bottomRadius: bottom.radius * 1.5)
                    context.stroke(Path(path), with: .color(.white.opacity(0.95)), lineWidth: 3)
                }
            }
            .clipped()
        }
    }
}

/// After selecting an area: captured at once, or kept adjustable until Return.
struct SelectionModePreview: View {
    let adjust: Bool

    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(x: geo.size.width * 0.22, y: geo.size.height * 0.24,
                              width: geo.size.width * 0.5, height: geo.size.height * 0.48)
            ZStack(alignment: .topLeading) {
                MiniDesktop()
                Canvas { context, size in
                    var dim = Path(CGRect(origin: .zero, size: size))
                    dim.addRect(rect)
                    context.fill(dim, with: .color(.black.opacity(0.4)), style: FillStyle(eoFill: true))
                }
                Rectangle().strokeBorder(.white, lineWidth: 1)
                    .frame(width: rect.width, height: rect.height).offset(x: rect.minX, y: rect.minY)
                if adjust {
                    ForEach(0..<8, id: \.self) { i in
                        let p = handlePoint(i, rect)
                        Circle().fill(.white).frame(width: 5, height: 5).offset(x: p.x - 2.5, y: p.y - 2.5)
                    }
                    KeyCapLabel(text: "↩").offset(x: rect.maxX + 6, y: rect.maxY - 10)
                } else {
                    Image(systemName: "camera.shutter.button.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                        .offset(x: rect.maxX + 5, y: rect.maxY - 12)
                }
            }
        }
    }

    private func handlePoint(_ i: Int, _ r: CGRect) -> CGPoint {
        [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
         CGPoint(x: r.maxX, y: r.midY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.midX, y: r.maxY),
         CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.minX, y: r.midY)][i]
    }
}

/// The overlay's magnifier next to the crosshair, or the crosshair alone.
struct MagnifierPreview: View {
    let on: Bool

    var body: some View {
        GeometryReader { geo in
            let c = CGPoint(x: geo.size.width * 0.38, y: geo.size.height * 0.3)
            ZStack(alignment: .topLeading) {
                MiniDesktop(dimmed: true)
                Path { p in
                    p.move(to: CGPoint(x: 0, y: c.y)); p.addLine(to: CGPoint(x: geo.size.width, y: c.y))
                    p.move(to: CGPoint(x: c.x, y: 0)); p.addLine(to: CGPoint(x: c.x, y: geo.size.height))
                }
                .stroke(.white.opacity(0.7), lineWidth: 0.75)
                if on {
                    Canvas { context, size in
                        let cell: CGFloat = 4
                        for row in 0..<7 {
                            for col in 0..<7 {
                                let shade = 0.3 + 0.08 * Double((row * 3 + col * 5) % 7)
                                context.fill(Path(CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)),
                                             with: .color(Color(red: shade * 1.05, green: shade * 1.18, blue: shade * 1.0)))
                            }
                        }
                        context.stroke(Path(CGRect(x: 3 * cell, y: 3 * cell, width: cell, height: cell)), with: .color(.white), lineWidth: 1)
                    }
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.85), lineWidth: 1))
                    .offset(x: c.x + 8, y: c.y + 6)
                    Text("#869B80")
                        .font(.system(size: 6, weight: .semibold).monospaced())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 2)
                        .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 2))
                        .offset(x: c.x + 8, y: c.y + 37)
                }
            }
        }
    }
}

/// A captured window on a checkerboard (its transparent surroundings), with or without shadow.
struct WindowShadowPreview: View {
    let shadow: Bool

    var body: some View {
        ZStack {
            CheckerPattern()
            MiniWindow()
                .frame(width: 80, height: 48)
                .shadow(color: .black.opacity(shadow ? 0.55 : 0), radius: shadow ? 7 : 0, y: shadow ? 4 : 0)
        }
    }
}

struct CheckerPattern: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(white: 0.88))
            let cell: CGFloat = 6
            for row in 0..<Int(size.height / cell) + 1 {
                for col in 0..<Int(size.width / cell) + 1 where (row + col).isMultiple(of: 2) {
                    context.fill(Path(CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)),
                                 with: .color(white: 0.76))
                }
            }
        }
    }
}

/// The copied text for an orange sample color in each format.
struct ColorFormatPreview: View {
    let format: ColorFormat

    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 5).fill(Color(red: 1, green: 0.5, blue: 0)).frame(width: 30, height: 22)
            Text(format.string(red: 1, green: 0.5, blue: 0))
                .font(.system(size: 10, weight: .medium).monospaced())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Color.ink)
        .background(Color.key)
    }
}

/// The stamp-like preview after a capture, or nothing.
struct QuickAccessPreview: View {
    let on: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            MiniDesktop()
            if on {
                MiniStamp()
                    .frame(width: 40, height: 36)
                    .shadow(color: Color.shadow.opacity(0.25), radius: 2, y: 1)
                    .padding(7)
            }
        }
    }
}

/// The preview stamp in miniature: perforated paper, a capture, a caption line.
struct MiniStamp: View {
    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            var paper = Path(bounds)
            for center in QuickAccessLayout.perforation(of: bounds, pitch: 4.4) {
                paper.addEllipse(in: CGRect(x: center.x - 1.2, y: center.y - 1.2, width: 2.4, height: 2.4))
            }
            context.fill(paper, with: .color(.card), style: FillStyle(eoFill: true))
            context.fill(Path(CGRect(x: 4, y: 4, width: size.width - 8, height: size.height - 13)), with: .color(.sage))
            context.fill(Path(CGRect(x: 4, y: size.height - 6.5, width: size.width * 0.45, height: 2)), with: .color(.ink2))
        }
    }
}

/// A slice of the menu bar, with or without Glassine's icon.
struct MenuBarIconPreview: View {
    let on: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Spacer()
                if on {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(3)
                        .background(Color.accentColor.opacity(0.35), in: RoundedRectangle(cornerRadius: 3))
                }
                ForEach(["wifi", "battery.75percent", "magnifyingglass"], id: \.self) {
                    Image(systemName: $0).font(.system(size: 9))
                }
                Text("12:08").font(.system(size: 8, weight: .medium))
            }
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Color(white: 0.2))
            .foregroundStyle(.white)
            MiniDesktop()
        }
    }
}

struct KeyCapLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 2))
    }
}
