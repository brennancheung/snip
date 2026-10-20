import AppKit
import SnipCore

/// A thin red outline just outside the recorded area. Click-through and kept out of the capture.
/// For a window target it follows the window's frame.
@MainActor
final class RecordingBorder {
    private static let width: CGFloat = 2

    private let target: CaptureTarget
    private let window: NSWindow
    private var timer: Timer?
    private var currentArea: CGRect = .null
    /// Called when a followed window moves or resizes, with its new area.
    var onAreaChange: ((CGRect) -> Void)?

    init(target: CaptureTarget, area: CGRect) {
        self.target = target
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.configureAsSnipOverlay(level: .screenSaver)
        window.ignoresMouseEvents = true

        let ring = NSView()
        ring.wantsLayer = true
        ring.layer?.borderColor = NSColor.systemRed.cgColor
        ring.layer?.borderWidth = Self.width
        window.contentView = ring
        place(around: area)
    }

    func show() {
        window.orderFrontRegardless()
        guard case .window(let windowID) = target else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.follow(windowID) }
        }
    }

    func close() {
        timer?.invalidate()
        timer = nil
        window.orderOut(nil)
    }

    private func follow(_ windowID: CGWindowID) {
        guard let bounds = ScreenGeometry.windowBounds(windowID) else {
            window.orderOut(nil)
            return
        }
        let area = ScreenGeometry.appKitRect(fromGlobalCG: bounds)
        guard area != currentArea else { return }
        place(around: area)
        window.orderFrontRegardless()
        onAreaChange?(area)
    }

    private func place(around area: CGRect) {
        currentArea = area
        // A whole display has no outside, so its outline sits just inside the edges.
        if case .display = target {
            window.setFrame(area, display: true)
        } else {
            window.setFrame(area.insetBy(dx: -Self.width, dy: -Self.width), display: true)
        }
    }
}
