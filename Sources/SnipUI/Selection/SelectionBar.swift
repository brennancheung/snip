import AppKit

/// The small bar by the selection: its pixel size, the microphone and system audio toggles,
/// Record ↩ and Cancel esc.
final class SelectionBar: NSView {
    var onRecord: @MainActor () -> Void = {}
    var onCancel: @MainActor () -> Void = {}

    private let sizeLabel = NSTextField(labelWithString: "")
    private let stack: NSStackView

    init() {
        let record = BarButton(title: "Record ↩", target: nil, action: nil)
        let cancel = BarButton(title: "Cancel esc", target: nil, action: nil)
        stack = NSStackView(views: [sizeLabel, AudioToggles(), record, cancel])
        super.init(frame: .zero)

        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.92).cgColor
        layer?.cornerRadius = 8

        sizeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        sizeLabel.textColor = .white
        record.target = self
        record.action = #selector(recordClicked)
        record.keyEquivalent = "\r"
        cancel.target = self
        cancel.action = #selector(cancelClicked)
        cancel.keyEquivalent = "\u{1b}"

        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 6)
        stack.autoresizingMask = [.width, .height]
        addSubview(stack)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func setText(_ text: String) {
        guard text != sizeLabel.stringValue || frame.size == .zero else { return }
        sizeLabel.stringValue = text
        setFrameSize(stack.fittingSize)
        stack.frame = bounds
    }

    @objc private func recordClicked() { onRecord() }
    @objc private func cancelClicked() { onCancel() }

    // Clicks on the bar's background mustn't reach the overlay and start a new box.
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
}

/// Works on the first click even when its panel isn't key yet.
private final class BarButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
