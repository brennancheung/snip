import AppKit
import SnipCore

/// The floating HUD while recording: ● 0:12, Stop, Discard, with a mic glyph before the time
/// while the microphone is recorded. During encoding it becomes
/// "Compressing…" with a thin progress bar. Draggable; never takes focus.
@MainActor
final class RecordingPill: NSObject {
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    /// Drags the panel from anywhere except its buttons.
    private final class DragView: NSVisualEffectView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            let hit = super.hitTest(point)
            return hit is NSButton ? hit : (hit == nil ? nil : self)
        }
        var onDragged: (() -> Void)?
        override func mouseDown(with event: NSEvent) {
            onDragged?()
            window?.performDrag(with: event)
        }
    }

    private static let height: CGFloat = 36
    private static let gap: CGFloat = 10

    var onStop: (() -> Void)?
    var onDiscard: (() -> Void)?

    private let panel = Panel(contentRect: CGRect(x: 0, y: 0, width: 200, height: RecordingPill.height),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let background = DragView()
    private let timeLabel = NSTextField(labelWithString: "0:00")
    private let recordingRow = NSStackView()
    private let compressingRow = NSStackView()
    private let progressBar = NSProgressIndicator()
    private var userMoved = false

    /// `microphone`: the microphone is being recorded.
    init(microphone: Bool) {
        super.init()
        panel.configureAsSnipOverlay(level: .statusBar)
        panel.hasShadow = true
        panel.hidesOnDeactivate = false

        let dot = NSImageView(image: NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Recording")!)
        dot.symbolConfiguration = .init(pointSize: 9, weight: .regular)
        dot.contentTintColor = .systemRed

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        timeLabel.textColor = .labelColor

        let stop = NSButton(title: "Stop", target: self, action: #selector(stopClicked))
        stop.bezelStyle = .push
        stop.controlSize = .small
        let discard = NSButton(image: NSImage(systemSymbolName: "trash", accessibilityDescription: "Discard")!,
                               target: self, action: #selector(discardClicked))
        discard.isBordered = false
        discard.toolTip = "Discard"
        discard.contentTintColor = .secondaryLabelColor

        let mic = NSImageView(image: NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Microphone on")!)
        mic.symbolConfiguration = .init(pointSize: 11, weight: .regular)
        mic.contentTintColor = .secondaryLabelColor
        mic.isHidden = !microphone

        recordingRow.setViews([dot, mic, timeLabel, stop, discard], in: .leading)
        recordingRow.spacing = 8
        recordingRow.setCustomSpacing(12, after: timeLabel)

        let compressing = NSTextField(labelWithString: "Compressing…")
        compressing.font = .systemFont(ofSize: 12, weight: .medium)
        progressBar.style = .bar
        progressBar.controlSize = .mini
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressBar.widthAnchor.constraint(equalToConstant: 120).isActive = true
        compressingRow.setViews([compressing, progressBar], in: .leading)
        compressingRow.orientation = .vertical
        compressingRow.alignment = .leading
        compressingRow.spacing = 4
        compressingRow.isHidden = true

        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.appearance = NSAppearance(named: .vibrantDark)
        background.wantsLayer = true
        background.layer?.cornerRadius = Self.height / 2
        background.layer?.masksToBounds = true
        for row in [recordingRow, compressingRow] {
            row.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(row)
            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 14),
                row.trailingAnchor.constraint(lessThanOrEqualTo: background.trailingAnchor, constant: -10),
                row.centerYAnchor.constraint(equalTo: background.centerYAnchor),
            ])
        }
        panel.contentView = background

        background.onDragged = { [weak self] in self?.userMoved = true }
    }

    func show(near area: CGRect, target: CaptureTarget) {
        resize()
        place(near: area, target: target)
        panel.orderFrontRegardless()
    }

    /// Keeps the pill beside a followed window, until the user drags it somewhere else.
    func follow(_ area: CGRect, target: CaptureTarget) {
        guard !userMoved else { return }
        place(near: area, target: target)
    }

    func setElapsed(_ seconds: Int) {
        timeLabel.stringValue = Self.formatElapsed(seconds)
    }

    func showCompressing() {
        recordingRow.isHidden = true
        compressingRow.isHidden = false
        progressBar.doubleValue = 0
        let centre = panel.frame.midX
        resize()
        panel.setFrameOrigin(CGPoint(x: centre - panel.frame.width / 2, y: panel.frame.minY))
    }

    func setProgress(_ progress: Double) {
        progressBar.doubleValue = progress
    }

    func close() {
        panel.orderOut(nil)
    }

    /// m:ss.
    private static func formatElapsed(_ seconds: Int) -> String {
        String(format: "%ld:%02ld", seconds / 60, seconds % 60)
    }

    private func resize() {
        let row = recordingRow.isHidden ? compressingRow : recordingRow
        let width = max(row.fittingSize.width + 24, 120)
        panel.setContentSize(CGSize(width: width, height: Self.height))
    }

    /// Below the area, or above it if there is no room, or inside its bottom edge for a whole display.
    private func place(near area: CGRect, target: CaptureTarget) {
        guard let screen = ScreenGeometry.screen(for: area) else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let below = area.minY - Self.gap - size.height
        let above = area.maxY + Self.gap
        let inside = max(area.minY, visible.minY) + 24
        let y: CGFloat
        if case .display = target {
            y = inside
        } else if below >= visible.minY {
            y = below
        } else if above + size.height <= visible.maxY {
            y = above
        } else {
            y = inside
        }
        let x = min(max(area.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
        panel.setFrameOrigin(CGPoint(x: x, y: y))
    }

    @objc private func stopClicked() { onStop?() }
    @objc private func discardClicked() { onDiscard?() }
}
