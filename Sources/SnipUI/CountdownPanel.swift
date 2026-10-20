import AppKit

/// A big 3, 2, 1 centred on the selection, at the interface size. Click-through; Escape cancels.
@MainActor
final class CountdownPanel {
    private final class Panel: NSPanel {
        var onEscape: (() -> Void)?
        override var canBecomeKey: Bool { true }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
        }
        override func cancelOperation(_ sender: Any?) { onEscape?() }
    }

    private let panel: Panel
    private let label = NSTextField(labelWithString: "")
    private var cancelled = false

    /// `scale`: the interface size, the saved one if nil.
    init(centredOn area: CGRect, scale: UIScale? = nil) {
        let ui = scale ?? .current
        let side = ui.metric(132)
        let frame = CGRect(x: area.midX - side / 2, y: area.midY - side / 2, width: side, height: side)
        panel = Panel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.configureAsSnipOverlay(level: .screenSaver)
        panel.ignoresMouseEvents = true
        panel.becomesKeyOnlyIfNeeded = false

        let background = NSView(frame: CGRect(origin: .zero, size: frame.size))
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        background.layer?.cornerRadius = ui.metric(28)

        label.font = ui.monospacedDigitFont(80, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: background.centerYAnchor),
        ])
        panel.contentView = background
        panel.onEscape = { [weak self] in self?.cancel() }
    }

    /// The panel's content showing `number`, for rendering it without showing it (UIPreviews).
    func previewView(number: Int) -> NSView {
        label.stringValue = "\(number)"
        let view = panel.contentView!
        view.layoutSubtreeIfNeeded()
        return view
    }

    /// Counts down from `seconds`, calling `tick` with each number. Returns false if cancelled.
    func run(seconds: Int, tick: (Int) -> Void) async -> Bool {
        panel.makeKeyAndOrderFront(nil)
        defer { panel.orderOut(nil) }
        for remaining in stride(from: seconds, through: 1, by: -1) {
            if cancelled { return false }
            label.stringValue = "\(remaining)"
            tick(remaining)
            // Short naps so Escape takes effect at once.
            for _ in 0..<20 where !cancelled {
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        return !cancelled
    }

    /// Escape, or the hotkey during the countdown.
    func cancel() {
        cancelled = true
        panel.orderOut(nil)
    }
}
