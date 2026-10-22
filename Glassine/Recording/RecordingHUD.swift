import AppKit
import SwiftUI

/// The controls while recording: a small pill next to the recorded area with the time, Stop and
/// Discard, and a frame around the area. Both are Glassine windows, which the recording leaves out.
@MainActor
final class RecordingHUD {
    @MainActor @Observable
    final class Model {
        enum Phase: Equatable {
            case recording(since: Date)
            case saving
            case makingGIF(progress: Double)
        }
        var phase = Phase.saving
    }

    let model = Model()
    private let pill: NSPanel
    private let outline: NSPanel?

    /// `area` is the recorded region in global Cocoa coordinates; nil records it whole (no frame).
    init(area: NSRect, on screen: NSScreen, framed: Bool, onStop: @escaping () -> Void, onDiscard: @escaping () -> Void) {
        let view = PillHostingView(rootView: RecordingPill(model: model, stop: onStop, discard: onDiscard))
        let size = view.fittingSize
        pill = Self.panel(frame: NSRect(origin: RecordingHUD.pillOrigin(for: size, area: area, visible: screen.visibleFrame), size: size))
        pill.contentView = view

        if framed {
            let outlineFrame = area.insetBy(dx: -OutlineView.width, dy: -OutlineView.width)
            let outline = Self.panel(frame: outlineFrame)
            outline.ignoresMouseEvents = true
            outline.hasShadow = false
            outline.contentView = OutlineView(frame: NSRect(origin: .zero, size: outlineFrame.size))
            self.outline = outline
        } else {
            outline = nil
        }
    }

    func show() {
        outline?.orderFrontRegardless()
        pill.orderFrontRegardless()
    }

    /// While the file is saved or the GIF made, only the pill stays.
    func hideOutline() {
        outline?.orderOut(nil)
    }

    func close() {
        outline?.orderOut(nil)
        pill.orderOut(nil)
    }

    /// Below the area if there is room, else above it, else inside its bottom edge.
    nonisolated static func pillOrigin(for size: NSSize, area: NSRect, visible: NSRect) -> NSPoint {
        let gap: CGFloat = 12
        let x = min(max(area.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
        if area.minY - gap - size.height >= visible.minY {
            return NSPoint(x: x, y: area.minY - gap - size.height)
        }
        if area.maxY + gap + size.height <= visible.maxY {
            return NSPoint(x: x, y: area.maxY + gap)
        }
        return NSPoint(x: x, y: max(area.minY, visible.minY) + 24)
    }

    private static func panel(frame: NSRect) -> NSPanel {
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        return panel
    }
}

private final class PillHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A thin frame just outside the recorded area.
private final class OutlineView: NSView {
    static let width: CGFloat = 3

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(rect: bounds.insetBy(dx: Self.width / 2, dy: Self.width / 2))
        path.lineWidth = Self.width
        path.setLineDash([8, 5], count: 2, phase: 0)
        NSColor.black.withAlphaComponent(0.35).setStroke()
        path.stroke()
        let inner = NSBezierPath(rect: bounds.insetBy(dx: Self.width / 2, dy: Self.width / 2))
        inner.lineWidth = 1.5
        inner.setLineDash([8, 5], count: 2, phase: 0)
        NSColor.white.setStroke()
        inner.stroke()
    }
}

private struct RecordingPill: View {
    let model: RecordingHUD.Model
    let stop: () -> Void
    let discard: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            switch model.phase {
            case .recording(let since):
                RecordingDot()
                TimelineView(.periodic(from: since, by: 1)) { context in
                    Text(RecordingMath.clock(context.date.timeIntervalSince(since)))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .frame(minWidth: 38, alignment: .leading)
                }
                Spacer(minLength: 0)
                PillIconButton(symbol: "stop.fill", help: "Stop and save", tint: .red, action: stop)
                PillIconButton(symbol: "trash", help: "Discard the recording", tint: .secondary, action: discard)
            case .saving:
                ProgressView().controlSize(.small)
                Text("Saving…").font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
            case .makingGIF(let progress):
                Text("Making GIF…").font(.system(size: 13, weight: .medium)).fixedSize()
                ProgressView(value: progress)
            }
        }
        // One width for every phase, so the panel never has to resize.
        .frame(width: 170)
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: 38)
        .glassPanel(in: Capsule())
        .padding(10) // room for the shadow
    }
}

private struct RecordingDot: View {
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 9, height: 9)
            .opacity(dim ? 0.35 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { dim = true }
            }
    }
}

private struct PillIconButton: View {
    let symbol: String
    let help: String
    let tint: Color
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(hovered ? 0.15 : 0.07)))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovered = $0 }
    }
}
