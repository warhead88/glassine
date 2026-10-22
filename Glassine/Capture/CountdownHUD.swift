import AppKit

/// Small countdown shown in the middle of the screen before a timed capture.
/// Click it to cancel. Hides itself before the capture so it never ends up in the image.
@MainActor
final class CountdownHUD {
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    private var remaining: Int
    private var task: Task<Void, Never>?
    private let onFinish: (_ completed: Bool) -> Void

    init(seconds: Int, onFinish: @escaping (_ completed: Bool) -> Void) {
        self.remaining = seconds
        self.onFinish = onFinish

        let size = NSSize(width: 120, height: 120)
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let frame = screen.map {
            NSRect(x: $0.frame.midX - size.width / 2, y: $0.frame.midY - size.height / 2, width: size.width, height: size.height)
        } ?? NSRect(origin: .zero, size: size)

        panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false

        let background = PaperCardView(frame: NSRect(origin: .zero, size: size), cornerRadius: 28)

        // One digit at a time, so Fraunces' proportional figures can't make it jump.
        label.font = Typography.fraunces(size: 64, weight: 460)
        label.alignment = .center
        label.textColor = .ink
        label.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: background.centerYAnchor),
        ])

        let click = NSClickGestureRecognizer(target: nil, action: nil)
        background.addGestureRecognizer(click)
        panel.contentView = background
        click.target = self
        click.action = #selector(cancel)
        background.toolTip = "Click to cancel"
    }

    func start() {
        label.stringValue = "\(remaining)"
        panel.orderFrontRegardless()
        task = Task { [weak self] in
            while let self, self.remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self.remaining -= 1
                self.label.stringValue = "\(self.remaining)"
            }
            guard let self else { return }
            self.panel.orderOut(nil)
            // Let the window server drop the HUD before the screen is frozen.
            try? await Task.sleep(for: .milliseconds(100))
            self.onFinish(true)
        }
    }

    @objc func cancel() {
        task?.cancel()
        panel.orderOut(nil)
        onFinish(false)
    }
}
