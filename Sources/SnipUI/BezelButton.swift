import AppKit

/// A push button that draws its own rounded bezel around its title, so it grows with the text at
/// any interface size. AppKit's bezelled buttons have a fixed height for each control size and
/// clip larger text. Used by the selection bar, the recording pill and the Settings shortcut field;
/// `BezelButtonStyle` (SettingsControls.swift) is the same look in SwiftUI.
class BezelButton: NSButton {
    var text: String { didSet { refreshTitle() } }
    /// The key that presses it, drawn dimmer after the title: "↩", "esc".
    var keycap: String? { didSet { refreshTitle() } }
    var titleFont: NSFont { didSet { refreshTitle() } }
    var scale: UIScale { didSet { refreshTitle() } }
    /// Filled with the accent colour, white text: the default action.
    var isProminent = false { didSet { refreshTitle() } }
    /// Drawn round the bezel in place of its border, e.g. while the shortcut field waits for keys.
    var outlineColor: NSColor? { didSet { needsDisplay = true } }
    /// Unscaled; `scale` applies.
    var minimumWidth: CGFloat = 0 { didSet { invalidateIntrinsicContentSize() } }

    init(title: String, keycap: String? = nil, font: NSFont, scale: UIScale) {
        text = title
        self.keycap = keycap
        titleFont = font
        self.scale = scale
        super.init(frame: .zero)
        isBordered = false
        setButtonType(.momentaryPushIn)
        refreshTitle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // Works on the first click even when its panel isn't key yet (the selection overlay).
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var intrinsicContentSize: NSSize {
        let title = attributedTitle.size()
        return NSSize(
            width: max(ceil(title.width) + 2 * scale.metric(10), scale.metric(minimumWidth)),
            height: ceil(title.height) + 2 * scale.metric(4)
        )
    }

    override var isHighlighted: Bool {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = scale.metric(6)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        let pressed = isHighlighted || (cell?.isHighlighted ?? false)
        if isProminent {
            let accent = NSColor.controlAccentColor
            (pressed ? accent.shadow(withLevel: 0.2) ?? accent : accent).setFill()
            path.fill()
        } else {
            NSColor.labelColor.withAlphaComponent(pressed ? 0.2 : 0.1).setFill()
            path.fill()
            NSColor.labelColor.withAlphaComponent(0.18).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
        if let outlineColor {
            let width = scale.metric(2)
            let ring = NSBezierPath(
                roundedRect: bounds.insetBy(dx: width / 2, dy: width / 2),
                xRadius: radius - width / 2,
                yRadius: radius - width / 2
            )
            ring.lineWidth = width
            outlineColor.setStroke()
            ring.stroke()
        }
        let title = attributedTitle
        let size = title.size()
        title.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }

    private func refreshTitle() {
        let colour: NSColor = isProminent ? .white : .labelColor
        let title = NSMutableAttributedString(string: text, attributes: [.font: titleFont, .foregroundColor: colour])
        if let keycap {
            title.append(NSAttributedString(string: "  " + keycap, attributes: [
                .font: titleFont,
                .foregroundColor: colour.withAlphaComponent(0.6),
            ]))
        }
        attributedTitle = title
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }
}
