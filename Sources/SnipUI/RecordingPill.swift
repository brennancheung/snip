import AppKit
import SnipCore

/// The floating HUD while recording: ● 0:12, the microphone and system audio toggles, Stop,
/// Discard. During encoding it becomes
/// "Compressing…" with a thin progress bar. Draggable; never takes focus. Drawn at the interface size.
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

    var onStop: (() -> Void)?
    var onDiscard: (() -> Void)?

    private let ui: UIScale
    private let height: CGFloat
    private let panel: Panel
    private let background = DragView()
    private let timeLabel = NSTextField(labelWithString: "0:00")
    private let recordingRow = NSStackView()
    private let compressingRow = NSStackView()
    private let progressBar: ProgressBar
    private var userMoved = false

    /// At the saved interface size.
    override convenience init() {
        self.init(scale: nil)
    }

    /// `scale`: the interface size, the saved one if nil.
    init(scale: UIScale?) {
        let ui = scale ?? .current
        self.ui = ui
        let height = ui.metric(36)
        self.height = height
        panel = Panel(contentRect: CGRect(x: 0, y: 0, width: ui.metric(200), height: height),
                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        progressBar = ProgressBar()
        super.init()
        panel.configureAsSnipOverlay(level: .statusBar)
        panel.hasShadow = true
        panel.hidesOnDeactivate = false

        let dot = NSImageView(image: NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Recording")!)
        dot.symbolConfiguration = .init(pointSize: ui.metric(9), weight: .regular)
        dot.contentTintColor = .systemRed

        timeLabel.font = ui.monospacedDigitFont(13, weight: .medium)
        timeLabel.textColor = .labelColor

        let stop = BezelButton(title: "Stop", font: ui.font(12, weight: .medium), scale: ui)
        stop.target = self
        stop.action = #selector(stopClicked)
        let discard = NSButton(image: NSImage(systemSymbolName: "trash", accessibilityDescription: "Discard")!,
                               target: self, action: #selector(discardClicked))
        discard.isBordered = false
        discard.symbolConfiguration = .init(pointSize: ui.metric(13), weight: .regular)
        discard.toolTip = "Discard"
        discard.contentTintColor = .secondaryLabelColor

        let audio = AudioToggles(scale: ui)

        recordingRow.setViews([dot, timeLabel, audio, stop, discard], in: .leading)
        recordingRow.spacing = ui.metric(8)
        recordingRow.setCustomSpacing(ui.metric(12), after: audio)

        let compressing = NSTextField(labelWithString: "Compressing…")
        compressing.font = ui.font(12, weight: .medium)
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            progressBar.widthAnchor.constraint(equalToConstant: ui.metric(120)),
            progressBar.heightAnchor.constraint(equalToConstant: ui.metric(4)),
        ])
        compressingRow.setViews([compressing, progressBar], in: .leading)
        compressingRow.orientation = .vertical
        compressingRow.alignment = .leading
        compressingRow.spacing = ui.metric(4)
        compressingRow.isHidden = true

        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.appearance = NSAppearance(named: .vibrantDark)
        background.wantsLayer = true
        background.layer?.cornerRadius = height / 2
        background.layer?.masksToBounds = true
        for row in [recordingRow, compressingRow] {
            row.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(row)
            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: ui.metric(14)),
                row.trailingAnchor.constraint(lessThanOrEqualTo: background.trailingAnchor, constant: -ui.metric(10)),
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
        progressBar.progress = 0
        let centre = panel.frame.midX
        resize()
        panel.setFrameOrigin(CGPoint(x: centre - panel.frame.width / 2, y: panel.frame.minY))
    }

    func setProgress(_ progress: Double) {
        progressBar.progress = progress
    }

    func close() {
        panel.orderOut(nil)
    }

    /// m:ss.
    private static func formatElapsed(_ seconds: Int) -> String {
        String(format: "%ld:%02ld", seconds / 60, seconds % 60)
    }

    /// The pill's content, sized, for rendering it without showing it (UIPreviews).
    /// Its background is a behind-window material, which draws nothing off-screen.
    func previewView(compressing: Bool) -> NSView {
        if compressing {
            showCompressing()
            setProgress(0.6)
        } else {
            resize()
        }
        background.layoutSubtreeIfNeeded()
        return background
    }

    private func resize() {
        let row = recordingRow.isHidden ? compressingRow : recordingRow
        let width = max(row.fittingSize.width + ui.metric(24), ui.metric(120))
        panel.setContentSize(CGSize(width: width, height: height))
    }

    /// Below the area, or above it if there is no room, or inside its bottom edge for a whole display.
    private func place(near area: CGRect, target: CaptureTarget) {
        guard let screen = ScreenGeometry.screen(for: area) else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let gap = ui.metric(10)
        let below = area.minY - gap - size.height
        let above = area.maxY + gap
        let inside = max(area.minY, visible.minY) + ui.metric(24)
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
        let margin = ui.metric(8)
        let x = min(max(area.midX - size.width / 2, visible.minX + margin), visible.maxX - size.width - margin)
        panel.setFrameOrigin(CGPoint(x: x, y: y))
    }

    @objc private func stopClicked() { onStop?() }
    @objc private func discardClicked() { onDiscard?() }
}

/// A thin rounded progress bar that keeps its proportions at any interface size
/// (NSProgressIndicator's bar has a fixed thickness).
private final class ProgressBar: NSView {
    /// 0 to 1.
    var progress: Double = 0 {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        NSColor.labelColor.withAlphaComponent(0.2).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        let filled = CGRect(x: 0, y: 0, width: bounds.width * min(max(progress, 0), 1), height: bounds.height)
        guard filled.width > 0 else { return }
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
    }
}
