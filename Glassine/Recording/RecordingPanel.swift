import AppKit
import SwiftUI

/// Where the recording controls go: beside the recorded area, or — when the area leaves no room
/// there (the whole screen, say) — docked to that edge of the screen.
enum PanelSide: String, CaseIterable, Identifiable {
    case right, below, left, above

    var id: Self { self }

    var title: String {
        switch self {
        case .right: "Right"
        case .below: "Below"
        case .left: "Left"
        case .above: "Above"
        }
    }

    var symbol: String {
        switch self {
        case .right: "rectangle.righthalf.inset.filled"
        case .below: "rectangle.bottomhalf.inset.filled"
        case .left: "rectangle.lefthalf.inset.filled"
        case .above: "rectangle.tophalf.inset.filled"
        }
    }

    /// Controls beside the area or on a side edge are a column; above and below, a row.
    var isVertical: Bool { self == .right || self == .left }
}

enum RecordingPanelLayout {
    static let gap: CGFloat = 12
    static let margin: CGFloat = 8

    /// The panel's origin beside `area`, or nil when it doesn't fit on that side of the screen.
    static func besideArea(size: CGSize, area: CGRect, visible: CGRect, side: PanelSide) -> CGPoint? {
        let x = min(max(area.midX - size.width / 2, visible.minX + margin), visible.maxX - margin - size.width)
        let y = min(max(area.midY - size.height / 2, visible.minY + margin), visible.maxY - margin - size.height)
        switch side {
        case .right:
            let left = area.maxX + gap
            return left + size.width <= visible.maxX - margin ? CGPoint(x: left, y: y) : nil
        case .left:
            let left = area.minX - gap - size.width
            return left >= visible.minX + margin ? CGPoint(x: left, y: y) : nil
        case .below:
            let bottom = area.minY - gap - size.height
            return bottom >= visible.minY + margin ? CGPoint(x: x, y: bottom) : nil
        case .above:
            let bottom = area.maxY + gap
            return bottom + size.height <= visible.maxY - margin ? CGPoint(x: x, y: bottom) : nil
        }
    }

    /// The panel's origin flush with that edge of the usable screen, centered along it.
    static func docked(size: CGSize, visible: CGRect, side: PanelSide) -> CGPoint {
        switch side {
        case .right: CGPoint(x: visible.maxX - size.width, y: visible.midY - size.height / 2)
        case .left: CGPoint(x: visible.minX, y: visible.midY - size.height / 2)
        case .below: CGPoint(x: visible.midX - size.width / 2, y: visible.minY)
        case .above: CGPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height)
        }
    }
}

/// The recording controls window and the dashed frame around the area. Both are Glassine
/// windows, which the recording leaves out.
@MainActor
final class RecordingPanel {
    let model: RecordingPanelModel
    private let panel: ControlsPanel
    private let hosting: ControlsHostingView
    private let outline: NSPanel?
    private let area: NSRect
    private let screen: NSScreen

    init(model: RecordingPanelModel, area: NSRect, on screen: NSScreen, framed: Bool) {
        self.model = model
        self.area = area
        self.screen = screen
        hosting = ControlsHostingView(rootView: RecordingPanelView(model: model))
        panel = ControlsPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        Self.configure(panel)
        panel.contentView = hosting

        if framed {
            let frame = area.insetBy(dx: -OutlineView.width, dy: -OutlineView.width)
            let outline = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            Self.configure(outline)
            outline.ignoresMouseEvents = true
            outline.hasShadow = false
            outline.contentView = OutlineView(frame: NSRect(origin: .zero, size: frame.size))
            self.outline = outline
        } else {
            outline = nil
        }
        // After the view has taken the change in.
        model.onLayoutChange = { [weak self] in
            Task { @MainActor in self?.relayout(animated: true) }
        }
    }

    /// Shows the controls; while setting up they take the keyboard (↩ records, Esc cancels)
    /// without activating Glassine.
    func show() {
        relayout(animated: false)
        outline?.orderFrontRegardless()
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    /// Once recording, the keyboard goes back to the app being recorded.
    func releaseKeyboard() {
        guard panel.allowsKey else { return }
        panel.allowsKey = false
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    func hideOutline() {
        outline?.orderOut(nil)
    }

    func close() {
        outline?.orderOut(nil)
        panel.orderOut(nil)
    }

    /// Sizes the panel for what it shows now and places it beside the area or on the edge.
    private func relayout(animated: Bool) {
        let side = model.side
        let visible = screen.visibleFrame
        hosting.rootView = RecordingPanelView(model: model, dockedEdge: nil)
        var size = hosting.fittingSize
        var origin = RecordingPanelLayout.besideArea(size: size, area: area, visible: visible, side: side)
        if origin == nil {
            hosting.rootView = RecordingPanelView(model: model, dockedEdge: side)
            size = hosting.fittingSize
            origin = RecordingPanelLayout.docked(size: size, visible: visible, side: side)
        }
        let frame = NSRect(origin: origin ?? .zero, size: size)
        if animated, panel.isVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private static func configure(_ panel: NSPanel) {
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false // the SwiftUI shape draws its own
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
    }
}

private final class ControlsPanel: NSPanel {
    var allowsKey = true
    override var canBecomeKey: Bool { allowsKey }
}

private final class ControlsHostingView: NSHostingView<RecordingPanelView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A thin dashed frame just outside the recorded area.
private final class OutlineView: NSView {
    static let width: CGFloat = 3

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: Self.width / 2, dy: Self.width / 2)
        for (color, width) in [(NSColor.black.withAlphaComponent(0.35), Self.width), (NSColor.white, 1.5)] {
            let path = NSBezierPath(rect: rect)
            path.lineWidth = width
            path.setLineDash([8, 5], count: 2, phase: 0)
            color.setStroke()
            path.stroke()
        }
    }
}
