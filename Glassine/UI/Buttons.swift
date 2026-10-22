import AppKit

/// Buttons in a non-key panel must respond to the very first click.
class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// High-contrast button drawn by hand: system bezels render faded in a panel
/// that never becomes active, which is exactly how previews and pins work.
/// Paper (card with ink) by default; Stamp for what Glassine found, like QR codes.
final class PillButton: FirstMouseButton {
    enum Style { case paper, stamp }

    private var style = Style.paper
    private var label = ""

    convenience init(label: String, style: Style = .paper, symbol: String? = nil, target: AnyObject, action: Selector) {
        self.init(frame: .zero)
        self.style = style
        self.target = target
        self.action = action
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 12.5
        layer?.cornerCurve = .continuous
        if let symbol {
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            symbolConfiguration = .init(pointSize: 11, weight: .semibold)
            imagePosition = .imageLeading
        }
        setLabel(label)
    }

    func setLabel(_ label: String) {
        self.label = label
        applyColors()
        invalidateIntrinsicContentSize()
    }

    private var fill: NSColor { style == .paper ? .card : .accentStamp }
    private var text: NSColor { style == .paper ? .ink : .onAccentStamp }

    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            attributedTitle = NSAttributedString(string: label, attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: text,
            ])
            contentTintColor = text
            layer?.backgroundColor = (isHighlighted ? fill.blended(withFraction: 0.12, of: .ink) ?? fill : fill).cgColor
        }
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        applyColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: super.intrinsicContentSize.width + 28, height: 25)
    }
}

/// A small round icon button on paper, for the corners of previews.
final class CircleIconButton: FirstMouseButton {
    static let size: CGFloat = 20

    convenience init(symbol: String, help: String, target: AnyObject, action: Selector) {
        self.init(frame: NSRect(x: 0, y: 0, width: Self.size, height: Self.size))
        self.target = target
        self.action = action
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: help)
        symbolConfiguration = .init(pointSize: 9.5, weight: .bold)
        imagePosition = .imageOnly
        isBordered = false
        toolTip = help
        wantsLayer = true
        layer?.cornerRadius = Self.size / 2
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.size),
            heightAnchor.constraint(equalToConstant: Self.size),
        ])
        applyColors()
    }

    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            contentTintColor = .ink
            layer?.backgroundColor = NSColor.card.cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }
}

/// A card of the theme's paper for AppKit panels (countdown, controls): its color and hairline
/// follow light and dark.
final class PaperCardView: NSView {
    private let cornerRadius: CGFloat

    init(frame: NSRect, cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.card.cgColor
        layer?.borderColor = NSColor.border.cgColor
    }
}

