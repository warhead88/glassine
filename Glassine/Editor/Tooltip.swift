import SwiftUI

// Rich tooltips for the editor: after a short hover delay a small glass card shows a title,
// a one- or two-line description and the keyboard shortcut. Cards are drawn in one overlay
// on the editor (`tooltipHost()`), so they are never clipped by the bars they belong to.

struct TooltipContent: Equatable {
    var title: String
    var detail: String
    var shortcut: String?
}

enum TooltipPlacement {
    case below, above
}

private struct TooltipItem {
    let content: TooltipContent
    let placement: TooltipPlacement
    let anchor: Anchor<CGRect>
}

private struct TooltipPreferenceKey: PreferenceKey {
    static let defaultValue: [TooltipItem] = []
    static func reduce(value: inout [TooltipItem], nextValue: () -> [TooltipItem]) {
        value.append(contentsOf: nextValue())
    }
}

private struct TooltipModifier: ViewModifier {
    let content: TooltipContent
    let placement: TooltipPlacement
    @State private var isShown = false
    @State private var hoverTask: Task<Void, Never>?

    func body(content view: Content) -> some View {
        view
            .onHover { hovering in
                hoverTask?.cancel()
                if hovering {
                    hoverTask = Task {
                        try? await Task.sleep(for: .milliseconds(500))
                        guard !Task.isCancelled else { return }
                        isShown = true
                    }
                } else {
                    isShown = false
                }
            }
            // A click means the user knows what they want: hide until the next hover.
            .simultaneousGesture(TapGesture().onEnded {
                hoverTask?.cancel()
                isShown = false
            })
            .anchorPreference(key: TooltipPreferenceKey.self, value: .bounds) { anchor in
                isShown ? [TooltipItem(content: content, placement: placement, anchor: anchor)] : []
            }
    }
}

extension View {
    func tooltip(_ title: String, _ detail: String, shortcut: String? = nil, placement: TooltipPlacement) -> some View {
        modifier(TooltipModifier(content: TooltipContent(title: title, detail: detail, shortcut: shortcut), placement: placement))
    }

    /// Draws the tooltip of whichever control inside is hovered.
    func tooltipHost() -> some View {
        overlayPreferenceValue(TooltipPreferenceKey.self) { items in
            GeometryReader { proxy in
                if let item = items.last {
                    let rect = proxy[item.anchor]
                    let containerWidth = proxy.size.width
                    let placement = item.placement
                    ZStack(alignment: .topLeading) {
                        Color.clear
                        TooltipCard(content: item.content)
                            .alignmentGuide(.leading) { d in
                                let x = min(max(rect.midX, d.width / 2 + 8), containerWidth - d.width / 2 - 8)
                                return d.width / 2 - x
                            }
                            .alignmentGuide(.top) { d in
                                placement == .below ? -(rect.maxY + 8) : d.height - (rect.minY - 8)
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                            .id(item.content.title)
                    }
                    .allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: 0.12), value: items.last?.content)
        }
    }
}

private struct TooltipCard: View {
    let content: TooltipContent

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(content.title).font(.callout.weight(.semibold))
                Spacer(minLength: 12)
                if let shortcut = content.shortcut {
                    KeyCap(text: shortcut)
                }
            }
            Text(content.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 230, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .glassPanel(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold).monospaced())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5))
    }
}

extension EditorTool {
    /// One or two lines for the tooltip.
    var detail: String {
        switch self {
        case .select: "Select, move and resize marks. Double-click text to edit it."
        case .arrow: "Drag to point at something. Hold Shift for 45° angles."
        case .line: "Draw a straight line. Hold Shift for 45° angles."
        case .rectangle: "Frame an area. Hold Shift for a square."
        case .ellipse: "Circle something. Hold Shift for a perfect circle."
        case .text: "Click and type. Text size follows the width slider."
        case .pen: "Draw freehand."
        case .marker: "Highlight like a text marker."
        case .step: "Click to place numbered steps: 1, 2, 3…"
        case .blur: "Blur passwords, names and other private details."
        case .pixelate: "Pixelate private details."
        case .redact: "Cover an area with a solid color."
        case .crop: "Drag to keep only part of the image. Undo or reset any time."
        }
    }
}
