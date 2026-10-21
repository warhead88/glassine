import AppKit

/// Buttons in a non-key panel must respond to the very first click.
class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// High-contrast button drawn by hand: system bezels render faded in a panel
/// that never becomes active, which is exactly how previews and pins work.
final class PillButton: FirstMouseButton {
    convenience init(label: String, target: AnyObject, action: Selector) {
        self.init(frame: .zero)
        self.target = target
        self.action = action
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous
        setLabel(label)
        highlight(false)
    }

    func setLabel(_ label: String) {
        attributedTitle = NSAttributedString(string: label, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.black.withAlphaComponent(0.85),
        ])
        invalidateIntrinsicContentSize()
    }

    override func highlight(_ flag: Bool) {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(flag ? 0.7 : 0.92).cgColor
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: super.intrinsicContentSize.width + 24, height: 24)
    }
}
