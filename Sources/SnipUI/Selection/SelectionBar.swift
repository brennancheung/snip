import AppKit

/// The small bar by the selection: its pixel size, the microphone and system audio toggles,
/// Record ↩ and Cancel esc, all at the interface size.
final class SelectionBar: NSView {
    var onRecord: @MainActor () -> Void = {}
    var onCancel: @MainActor () -> Void = {}

    private let sizeLabel = NSTextField(labelWithString: "")
    private let stack: NSStackView

    init(scale: UIScale) {
        let record = BezelButton(title: "Record", keycap: "↩", font: scale.font(13, weight: .medium), scale: scale)
        record.isProminent = true
        let cancel = BezelButton(title: "Cancel", keycap: "esc", font: scale.font(13), scale: scale)
        stack = NSStackView(views: [sizeLabel, AudioToggles(scale: scale), record, cancel])
        super.init(frame: .zero)

        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.92).cgColor
        layer?.cornerRadius = scale.metric(8)

        sizeLabel.font = scale.monospacedDigitFont(12, weight: .medium)
        sizeLabel.textColor = .white
        record.target = self
        record.action = #selector(recordClicked)
        record.keyEquivalent = "\r"
        cancel.target = self
        cancel.action = #selector(cancelClicked)
        cancel.keyEquivalent = "\u{1b}"

        stack.orientation = .horizontal
        stack.spacing = scale.metric(8)
        let inset = scale.metric(6)
        stack.edgeInsets = NSEdgeInsets(top: inset, left: scale.metric(12), bottom: inset, right: inset)
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
