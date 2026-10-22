import AppKit

/// A preview as a postage stamp: the capture in a paper mat with perforated edges, and a
/// postmark below — the date on the left, a detail (size, format) on the right. On hover the
/// capture dims and shows its buttons. Shared by screenshot and recording previews; subclasses
/// add their buttons and actions. With Increase Contrast or Reduce Transparency the paper is
/// plain, without perforation.
@MainActor
class PreviewStampView: NSView {
    unowned let previewPanel: PreviewPanel

    /// The capture itself, neutral: no paper tint behind it.
    let imageArea = NSView()
    /// Shown over the capture while hovered.
    let overlay = NSView()
    /// The main buttons, centered on the capture.
    let buttons = NSStackView()
    let topLeading = NSStackView()
    let topTrailing = NSStackView()

    private let paper = CAShapeLayer()
    private let perforated = Theme.shared.showsPaperDetails
    private let detailLabel: NSTextField

    init(panel: PreviewPanel, image: CGImage?, date: Date, detail: String) {
        previewPanel = panel
        detailLabel = NSTextField(labelWithString: detail)
        super.init(frame: NSRect(origin: .zero, size: panel.frame.size))
        wantsLayer = true
        layer?.addSublayer(paper)

        let margin = QuickAccessLayout.matMargin, caption = QuickAccessLayout.captionHeight
        imageArea.frame = NSRect(x: margin, y: caption, width: bounds.width - margin * 2,
                                 height: bounds.height - margin - caption)
        imageArea.autoresizingMask = [.width, .height]
        imageArea.wantsLayer = true
        imageArea.layer?.contents = image
        imageArea.layer?.contentsGravity = .resizeAspect
        imageArea.layer?.backgroundColor = NSColor(white: 0.5, alpha: 0.16).cgColor
        imageArea.layer?.cornerRadius = 3
        imageArea.layer?.masksToBounds = true
        addSubview(imageArea)

        // A fixed dark scrim: the buttons on it are paper in both themes.
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor(srgbRed: 0x1C / 255, green: 0x22 / 255, blue: 0x30 / 255, alpha: 0.42).cgColor
        overlay.alphaValue = 0
        #if DEBUG
        if CommandLine.arguments.contains("hover") { overlay.alphaValue = 1 } // `--debug-preview hover`
        #endif
        overlay.frame = imageArea.bounds
        overlay.autoresizingMask = [.width, .height]
        imageArea.addSubview(overlay)

        for stack in [buttons, topLeading, topTrailing] {
            stack.translatesAutoresizingMaskIntoConstraints = false
            overlay.addSubview(stack)
        }
        buttons.orientation = .vertical
        buttons.spacing = 6
        topLeading.spacing = 4
        topTrailing.spacing = 4
        // The main buttons sit in the space below the corner buttons, so they never overlap.
        let cornerRow = CircleIconButton.size + 12
        NSLayoutConstraint.activate([
            buttons.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            buttons.centerYAnchor.constraint(equalTo: overlay.centerYAnchor, constant: cornerRow / 2),
            topLeading.topAnchor.constraint(equalTo: overlay.topAnchor, constant: 6),
            topLeading.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 6),
            topTrailing.topAnchor.constraint(equalTo: overlay.topAnchor, constant: 6),
            topTrailing.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -6),
        ])

        let dateLabel = NSTextField(labelWithString: QuickAccessLayout.postmark(date))
        dateLabel.font = Typography.nsFont(ThemeTokens.date)
        dateLabel.textColor = .ink
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .ink2
        detailLabel.alignment = .right
        detailLabel.lineBreakMode = .byTruncatingTail
        for label in [dateLabel, detailLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }
        // The caption strip runs from the mat's edge to the bottom perforation.
        let captionCenter = caption / 2 + 1
        NSLayoutConstraint.activate([
            dateLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin + 1),
            dateLabel.centerYAnchor.constraint(equalTo: bottomAnchor, constant: -captionCenter),
            detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            detailLabel.firstBaselineAnchor.constraint(equalTo: dateLabel.firstBaselineAnchor),
            detailLabel.leadingAnchor.constraint(greaterThanOrEqualTo: dateLabel.trailingAnchor, constant: 8),
        ])
        // The stamp keeps its size: a long date squeezes the detail, never widens the preview.
        dateLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: bounds.width),
            heightAnchor.constraint(equalToConstant: bounds.height),
        ])

        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        // Runs with the view's appearance current, so the dynamic color resolves for it.
        paper.fillColor = NSColor.card.cgColor
    }

    override func layout() {
        super.layout()
        paper.frame = bounds
        paper.path = Self.paperPath(in: bounds, perforated: perforated)
        paper.fillRule = .evenOdd
    }

    /// The stamp's outline: a sheet with holes bitten out of every edge, or a plain card.
    static func paperPath(in bounds: CGRect, perforated: Bool) -> CGPath {
        guard perforated else {
            return CGPath(roundedRect: bounds, cornerWidth: 8, cornerHeight: 8, transform: nil)
        }
        let path = CGMutablePath()
        path.addRect(bounds)
        let r = ThemeTokens.Perforation.hole
        for center in QuickAccessLayout.perforation(of: bounds, pitch: ThemeTokens.Perforation.pitch) {
            path.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        }
        return path
    }

    func setDetail(_ text: String) {
        detailLabel.stringValue = text
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Hover

    override func mouseEntered(with event: NSEvent) { setHovering(true) }
    override func mouseExited(with event: NSEvent) { setHovering(false) }

    func setHovering(_ hovering: Bool) {
        previewPanel.setHovering(hovering)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            overlay.animator().alphaValue = hovering ? 1 : 0
        }
    }

    /// A small dark badge in the capture's bottom-left corner (length, QR found).
    func addBadge(_ badge: NSView) {
        badge.translatesAutoresizingMaskIntoConstraints = false
        imageArea.addSubview(badge, positioned: .below, relativeTo: overlay)
        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: imageArea.leadingAnchor, constant: 6),
            badge.bottomAnchor.constraint(equalTo: imageArea.bottomAnchor, constant: -6),
        ])
    }
}
