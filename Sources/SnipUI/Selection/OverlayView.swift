import AppKit

/// What every screen's view draws, in AppKit global coordinates. Built by `SelectionOverlay`;
/// each view draws the part on its own screen.
struct OverlayModel {
    enum Style { case accent, region }

    struct Label {
        var text: String
        /// The label sits just inside this rect's top-left corner.
        var inside: CGRect
    }

    struct Bar {
        var text: String
        /// The frame of the screen that shows the bar.
        var screenFrame: CGRect
    }

    /// The part left undimmed.
    var cutout: CGRect?
    var style: Style = .accent
    var handles = false
    var label: Label?
    /// The live pixel size beside the bottom-right corner while a box is being drawn.
    var cornerSize: String?
    var bar: Bar?
    var hintScreen: CGRect
    var hintVisible: Bool
}

/// One screen's overlay: dimming, cut-out, outline, handles and labels on Core Animation layers
/// (frame changes only, so a 5K display stays smooth), the Record/Cancel bar, and the mouse and
/// keys, which it hands to `SelectionOverlay` in global coordinates.
final class OverlayView: NSView {
    private weak var overlay: SelectionOverlay?
    private let screen: ScreenInfo
    private let canvas = LayerCanvas()
    private let dims = (0..<4).map { _ in CALayer() }
    private let outline = CALayer()
    private let handleLayers = Handle.allCases.map { _ in CALayer() }
    private let label: Pill
    private let corner: Pill
    private let hint: Pill
    private let bar = SelectionBar()
    private var hintFaded = false

    init(screen: ScreenInfo, overlay: SelectionOverlay) {
        self.screen = screen
        self.overlay = overlay
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label = Pill(font: font, scale: screen.scale)
        corner = Pill(font: font, scale: screen.scale)
        hint = Pill(font: .systemFont(ofSize: 13, weight: .medium), scale: screen.scale)
        super.init(frame: CGRect(origin: .zero, size: screen.frame.size))
        wantsLayer = true

        canvas.frame = bounds
        canvas.autoresizingMask = [.width, .height]
        addSubview(canvas)
        let root = canvas.layer!
        let dim = NSColor.black.withAlphaComponent(0.35).cgColor
        for layer in dims {
            layer.backgroundColor = dim
            root.addSublayer(layer)
        }
        root.addSublayer(outline)
        for layer in handleLayers {
            layer.bounds = CGRect(x: 0, y: 0, width: 8, height: 8)
            layer.backgroundColor = NSColor.white.cgColor
            layer.borderColor = NSColor.black.withAlphaComponent(0.4).cgColor
            layer.borderWidth = 0.5
            layer.cornerRadius = 1.5
            layer.contentsScale = screen.scale
            root.addSublayer(layer)
        }
        root.addSublayer(label.layer)
        root.addSublayer(corner.layer)
        root.addSublayer(hint.layer)
        hint.set("Click a window, or drag to select an area · esc to cancel")

        bar.isHidden = true
        bar.onRecord = { [weak self] in self?.overlay?.record() }
        bar.onCancel = { [weak self] in self?.overlay?.cancel() }
        addSubview(bar)

        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Drawing

    func apply(_ model: OverlayModel) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let cut = model.cutout.map(local)
        layoutDims(around: cut)

        if let cut {
            let width: CGFloat = model.style == .region ? 1 : 3
            let frame = cut.insetBy(dx: -width, dy: -width).intersection(bounds)
            outline.borderWidth = width
            outline.borderColor = (model.style == .region ? NSColor.white : NSColor.controlAccentColor).cgColor
            outline.frame = frame.isNull ? .zero : frame
            outline.isHidden = frame.isNull || frame.isEmpty
        } else {
            outline.isHidden = true
        }

        for (layer, handle) in zip(handleLayers, Handle.allCases) {
            guard model.handles, let cut else {
                layer.isHidden = true
                continue
            }
            layer.isHidden = false
            layer.position = handle.point(in: cut)
        }

        if let labelModel = model.label, case let inside = local(labelModel.inside).intersection(bounds), !inside.isNull, !inside.isEmpty {
            label.set(labelModel.text)
            label.layer.frame = CGRect(
                origin: CGPoint(x: inside.minX + 6, y: inside.maxY - 6 - label.size.height),
                size: label.size
            )
            label.layer.isHidden = false
        } else {
            label.layer.isHidden = true
        }

        if let text = model.cornerSize, let cut {
            corner.set(text)
            let size = corner.size
            let x = max(4, min(cut.maxX - size.width, bounds.maxX - size.width - 4))
            var y = cut.minY - 6 - size.height
            if y < 4 { y = cut.minY + 6 }
            corner.layer.frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
            corner.layer.isHidden = false
        } else {
            corner.layer.isHidden = true
        }

        layoutHint(model)
        CATransaction.commit()
        layoutBar(model.bar, cut: cut)
    }

    private func local(_ rect: CGRect) -> CGRect {
        rect.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
    }

    /// Four dim rects around the cut-out: below, above, left and right of it.
    private func layoutDims(around cutout: CGRect?) {
        let b = bounds
        guard let cutout, case let c = cutout.intersection(b), !c.isNull, !c.isEmpty else {
            dims[0].frame = b
            for layer in dims.dropFirst() { layer.frame = .zero }
            return
        }
        dims[0].frame = CGRect(x: b.minX, y: b.minY, width: b.width, height: c.minY - b.minY)
        dims[1].frame = CGRect(x: b.minX, y: c.maxY, width: b.width, height: b.maxY - c.maxY)
        dims[2].frame = CGRect(x: b.minX, y: c.minY, width: c.minX - b.minX, height: c.height)
        dims[3].frame = CGRect(x: c.maxX, y: c.minY, width: b.maxX - c.maxX, height: c.height)
    }

    private func layoutHint(_ model: OverlayModel) {
        guard model.hintScreen == screen.frame else {
            hint.layer.isHidden = true
            return
        }
        let visibleTop = screen.visibleFrame.maxY - screen.frame.minY
        hint.layer.frame = CGRect(
            origin: CGPoint(x: (bounds.width - hint.size.width) / 2, y: visibleTop - 24 - hint.size.height),
            size: hint.size
        )
        hint.layer.isHidden = false
        if !model.hintVisible && !hintFaded {
            hintFaded = true
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            fade.duration = 0.25
            hint.layer.add(fade, forKey: "fade")
            hint.layer.opacity = 0
        }
    }

    /// Under the selection, above it if there's no room, inside its bottom edge if neither fits.
    private func layoutBar(_ barModel: OverlayModel.Bar?, cut: CGRect?) {
        guard let barModel, barModel.screenFrame == screen.frame, let cut, case let sel = cut.intersection(bounds), !sel.isNull else {
            bar.isHidden = true
            return
        }
        bar.setText(barModel.text)
        let size = bar.frame.size
        let x = max(8, min(sel.midX - size.width / 2, bounds.maxX - size.width - 8))
        var y = sel.minY - 10 - size.height
        if y < 8 {
            y = sel.maxY + 10
            if y + size.height > bounds.maxY - 8 { y = sel.minY + 16 }
        }
        bar.setFrameOrigin(CGPoint(x: x, y: y))
        bar.isHidden = false
    }

    // MARK: Events

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func globalPoint(_ event: NSEvent) -> CGPoint {
        guard let window else { return NSEvent.mouseLocation }
        return window.convertPoint(toScreen: event.locationInWindow)
    }

    override func mouseEntered(with event: NSEvent) { overlay?.mouseMoved(to: globalPoint(event)) }
    override func mouseMoved(with event: NSEvent) { overlay?.mouseMoved(to: globalPoint(event)) }
    override func mouseDown(with event: NSEvent) { overlay?.mouseDown(at: globalPoint(event)) }
    override func mouseUp(with event: NSEvent) { overlay?.mouseUp(at: globalPoint(event)) }
    override func rightMouseDown(with event: NSEvent) { overlay?.rightMouseDown() }

    override func mouseDragged(with event: NSEvent) {
        overlay?.mouseDragged(to: globalPoint(event), shift: event.modifierFlags.contains(.shift))
    }

    override func flagsChanged(with event: NSEvent) {
        overlay?.flagsChanged(shift: event.modifierFlags.contains(.shift))
    }

    override func keyDown(with event: NSEvent) { overlay?.keyDown(event) }
    override func keyUp(with event: NSEvent) { overlay?.keyUp(event) }
}

/// Hosts the overlay's layers and lets every click through to `OverlayView`.
private final class LayerCanvas: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// A line of white text on a small dark rounded rect.
@MainActor
private final class Pill {
    let layer = CALayer()
    private let text = CATextLayer()
    private let font: NSFont
    private var current: String?
    private(set) var size = CGSize.zero

    init(font: NSFont, scale: CGFloat) {
        self.font = font
        layer.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        layer.cornerRadius = 5
        layer.contentsScale = scale
        text.contentsScale = scale
        layer.addSublayer(text)
        layer.isHidden = true
    }

    func set(_ string: String) {
        guard string != current else { return }
        current = string
        let attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: NSColor.white])
        text.string = attributed
        let measured = attributed.size()
        let w = ceil(measured.width), h = ceil(measured.height)
        size = CGSize(width: w + 16, height: h + 6)
        text.frame = CGRect(x: 8, y: 3, width: w, height: h)
    }
}
