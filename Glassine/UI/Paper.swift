import SwiftUI

// Shared pieces of the 0.4 look for SwiftUI windows: buttons, key caps, the done check, the
// stamp in its sleeve.

/// Primary: the accent, filled. Secondary: a card with a hairline. Quiet: text only.
struct PaperButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet }
    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        PaperButton(configuration: configuration, kind: kind)
    }
}

extension ButtonStyle where Self == PaperButtonStyle {
    static var paperPrimary: PaperButtonStyle { PaperButtonStyle(kind: .primary) }
    static var paperSecondary: PaperButtonStyle { PaperButtonStyle(kind: .secondary) }
    static var paperQuiet: PaperButtonStyle { PaperButtonStyle(kind: .quiet) }
}

private struct PaperButton: View {
    let configuration: ButtonStyle.Configuration
    let kind: PaperButtonStyle.Kind
    @Environment(Theme.self) private var theme
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.system(size: 14, weight: kind == .primary ? .semibold : .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, kind == .quiet ? 4 : 18)
            .padding(.vertical, 8)
            .background {
                switch kind {
                case .primary: Capsule().fill(theme.accent)
                case .secondary: Capsule().fill(Color.card).overlay(Capsule().strokeBorder(Color.border))
                case .quiet: EmptyView()
                }
            }
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
    }

    private var foreground: Color {
        switch kind {
        case .primary: theme.onAccent
        case .secondary: .ink
        case .quiet: .ink2
        }
    }
}

/// A shortcut as separate keys: ⌥ ⇧ ⌘ R.
struct KeyCaps: View {
    let shortcut: String

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(KeyCapParts.split(shortcut).enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.ink2)
                    .frame(minWidth: 21, minHeight: 20)
                    .padding(.horizontal, key.count > 1 ? 4 : 0)
                    .background(RoundedRectangle(cornerRadius: ThemeTokens.Radius.key, style: .continuous).fill(Color.key))
                    .overlay(RoundedRectangle(cornerRadius: ThemeTokens.Radius.key, style: .continuous).strokeBorder(Color.border))
                    // The cap's edge, a hairline lower: keys, not buttons.
                    .background(RoundedRectangle(cornerRadius: ThemeTokens.Radius.key, style: .continuous)
                        .fill(Color.border).offset(y: 1.5))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shortcut)
    }
}

enum KeyCapParts {
    static let modifiers: Set<Character> = ["⌃", "⌥", "⇧", "⌘"]

    /// Modifier glyphs one per cap, the rest as one key: "⌥⇧⌘F12" → ["⌥", "⇧", "⌘", "F12"].
    static func split(_ shortcut: String) -> [String] {
        let mods = shortcut.prefix { modifiers.contains($0) }
        let key = shortcut.dropFirst(mods.count)
        return mods.map(String.init) + (key.isEmpty ? [] : [String(key)])
    }
}

/// Done: a sage check in a pale sage circle.
struct CheckBadge: View {
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: size * 0.45, weight: .bold))
            .foregroundStyle(Color.sageDeep)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.sageTint))
            .accessibilityHidden(true)
    }
}

/// A stamp half slid into a glassine sleeve — Glassine's name, drawn. `caption` sits on the
/// stamp's top-left like a denomination.
struct StampInSleeve: View {
    let caption: String
    @Environment(Theme.self) private var theme

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                let stamp = CGRect(x: 14, y: 4, width: 88, height: 108)
                var paper = Path(stamp)
                if theme.showsPaperDetails {
                    for c in QuickAccessLayout.perforation(of: stamp, pitch: 7.7) {
                        paper.addEllipse(in: CGRect(x: c.x - 2.3, y: c.y - 2.3, width: 4.6, height: 4.6))
                    }
                }
                context.drawLayer { layer in
                    layer.rotate(by: .degrees(-5))
                    layer.addFilter(.shadow(color: Color.shadow.opacity(0.18), radius: 4, y: 3))
                    layer.fill(paper, with: .color(.card), style: FillStyle(eoFill: true))
                    layer.fill(Path(CGRect(x: stamp.minX + 8, y: stamp.minY + 8, width: 72, height: 70)), with: .color(.sage))
                    layer.fill(Path(ellipseIn: CGRect(x: stamp.minX + 50, y: stamp.minY + 46, width: 26, height: 26)),
                               with: .color(.peach))
                    layer.draw(Text(caption).font(Font(Typography.fraunces(size: 13, weight: 500))).foregroundStyle(Color.onInk),
                               at: CGPoint(x: stamp.minX + 13, y: stamp.minY + 18), anchor: .leading)
                    layer.draw(Text("Glassine").font(Font(Typography.fraunces(size: 11, italic: true))).foregroundStyle(Color.ink2),
                               at: CGPoint(x: stamp.midX, y: stamp.maxY - 11))
                }
                // The sleeve in front, with a thumb cut; the stamp shows through.
                var sleeve = Path()
                let top: CGFloat = 60, cut = CGRect(x: 40, y: top - 11, width: 36, height: 22)
                sleeve.move(to: CGPoint(x: 0, y: top))
                sleeve.addLine(to: CGPoint(x: cut.minX, y: top))
                sleeve.addArc(center: CGPoint(x: cut.midX, y: top), radius: cut.width / 2,
                              startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
                sleeve.addLine(to: CGPoint(x: size.width, y: top))
                sleeve.addLine(to: CGPoint(x: size.width, y: size.height - 5))
                sleeve.addQuadCurve(to: CGPoint(x: size.width - 5, y: size.height), control: CGPoint(x: size.width, y: size.height))
                sleeve.addLine(to: CGPoint(x: 5, y: size.height))
                sleeve.addQuadCurve(to: CGPoint(x: 0, y: size.height - 5), control: CGPoint(x: 0, y: size.height))
                sleeve.closeSubpath()
                context.fill(sleeve, with: .color(Color.card.opacity(theme.showsPaperDetails ? 0.68 : 0.95)))
                context.stroke(sleeve, with: .color(.border), lineWidth: 1)
            }
        }
        .frame(width: 118, height: 132)
        .accessibilityHidden(true)
    }
}
