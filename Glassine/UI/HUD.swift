import AppKit
import SwiftUI

/// A short glass notice at the bottom of the screen ("Text copied", "Color copied"),
/// optionally with one button. Never takes focus from the app the user works in.
@MainActor
enum HUD {
    private static var panel: NSPanel?
    private static var hideTask: Task<Void, Never>?

    static func show(
        _ title: String,
        detail: String? = nil,
        symbol: String = "checkmark.circle.fill",
        swatch: NSColor? = nil,
        action: (title: String, run: () -> Void)? = nil,
        autoHide: Bool = true
    ) {
        hideTask?.cancel()
        panel?.orderOut(nil)

        let view = HUDView(title: title, detail: detail, symbol: symbol, swatch: swatch.map(Color.init(nsColor:)),
                           actionTitle: action?.title, onAction: {
                               action?.run()
                               hide()
                           })
        let hosting = FirstMouseHostingView(rootView: view.themed())
        let size = hosting.fittingSize

        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let frame = NSRect(x: visible.midX - size.width / 2, y: visible.minY + 60, width: size.width, height: size.height)

        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel.animator().alphaValue = 1 }
        self.panel = panel

        guard autoHide else { return }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(action == nil ? 2.2 : 5))
            guard !Task.isCancelled else { return }
            hide()
        }
    }

    static func hide() {
        hideTask?.cancel()
        guard let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; panel.animator().alphaValue = 0 },
                                             completionHandler: { MainActor.assumeIsolated { panel.orderOut(nil) } })
    }
}

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct HUDView: View {
    let title: String
    let detail: String?
    let symbol: String
    let swatch: Color?
    let actionTitle: String?
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let swatch {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(swatch)
                    .frame(width: 28, height: 28)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: 320, alignment: .leading)
            if let actionTitle {
                Button(actionTitle, action: onAction)
                    .controlSize(.regular)
                    .buttonBorderShape(.capsule)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassPanel(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(20) // room for the fallback shadow
        .fixedSize()
    }
}
