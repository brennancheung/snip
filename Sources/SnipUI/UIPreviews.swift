import AppKit
import SnipCore
import SwiftUI

/// Snip's own UI drawn at a chosen interface size and saved as PNGs, to check how it looks without
/// recording anything: `swift run snip-ui-preview`. Each window is ordered in far off-screen while it
/// is drawn, so nothing appears, and nothing is saved to settings. One pixel per point, as on a 1x display.
@MainActor
public enum UIPreviews {
    public struct RenderError: Error, CustomStringConvertible {
        public let description: String
    }

    /// Renders every preview at each of `scales` (1 = 100%) into `directory`, one PNG each named
    /// like "selection-bar@200.png", and returns their URLs.
    public static func write(scales: [Double], to directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var written: [URL] = []
        for factor in scales {
            let ui = UIScale(CGFloat(factor))
            for name in names {
                let (view, background) = preview(name, ui)
                let url = directory.appendingPathComponent("\(name)@\(Int((factor * 100).rounded())).png")
                try png(of: view, background: background).write(to: url)
                written.append(url)
            }
        }
        keptAlive = []
        return written
    }

    // MARK: The views

    private static let names = [
        "selection-bar", "overlay-hover", "overlay-drawing", "overlay-selected",
        "pill", "pill-compressing", "countdown", "settings",
    ]

    /// The pills and countdowns being drawn, which own the panels their views are in.
    private static var keptAlive: [AnyObject] = []

    /// The view called `name` at `ui`, and what to draw behind it (the desktop, roughly).
    private static func preview(_ name: String, _ ui: UIScale) -> (NSView, NSColor) {
        let desktop = NSColor(white: 0.55, alpha: 1)
        switch name {
        case "selection-bar": return (selectionBar(ui), NSColor(white: 0.3, alpha: 1))
        case "overlay-hover": return (overlay(ui, .hover), desktop)
        case "overlay-drawing": return (overlay(ui, .drawing), desktop)
        case "overlay-selected": return (overlay(ui, .selected), desktop)
        case "pill": return (pill(ui, compressing: false), NSColor(white: 0.2, alpha: 1))
        case "pill-compressing": return (pill(ui, compressing: true), NSColor(white: 0.2, alpha: 1))
        case "countdown": return (countdown(ui), desktop)
        default: return (settings(ui), .windowBackgroundColor)
        }
    }

    /// The bar under a selection: size, microphone and speaker, Record ↩, Cancel esc.
    static func selectionBar(_ ui: UIScale) -> NSView {
        let bar = SelectionBar(scale: ui)
        bar.setText("1680 × 1000")
        return bar
    }

    enum OverlayStep { case hover, drawing, selected }

    /// A made-up display, its size in proportion to the interface size so the layout matches at
    /// every size, with the overlay as it is at `step`: the hint and a hovered window's name and
    /// size; a box being drawn and its size readout; or a chosen box, its handles and the bar.
    static func overlay(_ ui: UIScale, _ step: OverlayStep) -> NSView {
        let frame = CGRect(x: 0, y: 0, width: ui.metric(960), height: ui.metric(600))
        let screen = ScreenInfo(
            frame: frame,
            visibleFrame: CGRect(x: 0, y: 0, width: frame.width, height: frame.height - ui.metric(24)),
            scale: 1,
            displayID: 0
        )
        let view = OverlayView(screen: screen, overlay: nil, scale: ui)
        let box = CGRect(x: ui.metric(200), y: ui.metric(170), width: ui.metric(560), height: ui.metric(300))
        var model = OverlayModel(cutout: box, hintScreen: frame, hintVisible: step == .hover)
        switch step {
        case .hover:
            model.label = .init(text: "Safari · 1680 × 1000", inside: box)
        case .drawing:
            model.style = .region
            model.handles = true
            model.cornerSize = "1120 × 600"
        case .selected:
            model.style = .region
            model.handles = true
            model.bar = .init(text: "1120 × 600", screenFrame: frame)
        }
        view.apply(model)
        return view
    }

    /// The recording pill at 0:12, or compressing at 60%.
    static func pill(_ ui: UIScale, compressing: Bool) -> NSView {
        let pill = RecordingPill(scale: ui)
        keptAlive.append(pill)
        pill.setElapsed(12)
        return pill.previewView(compressing: compressing)
    }

    /// The countdown showing 3.
    static func countdown(_ ui: UIScale) -> NSView {
        let countdown = CountdownPanel(centredOn: .zero, scale: ui)
        keptAlive.append(countdown)
        return countdown.previewView(number: 3)
    }

    /// The Settings window's content as it is now, at `ui`.
    static func settings(_ ui: UIScale) -> NSView {
        let model = SettingsModel(applyHotKey: { _ in nil }, pauseHotKey: { _ in })
        model.reload()
        let hosting = NSHostingView(rootView: SettingsView(model: model, scaleOverride: ui))
        hosting.setFrameSize(hosting.fittingSize)
        return hosting
    }

    // MARK: Rendering

    /// Draws `view` over `background`, one pixel per point.
    static func png(of view: NSView, background: NSColor) throws -> Data {
        let size = CGSize(width: ceil(view.frame.width), height: ceil(view.frame.height))
        guard size.width > 0, size.height > 0 else { throw RenderError(description: "\(type(of: view)) has no size") }
        let window: NSWindow
        if let existing = view.window {
            window = existing
        } else {
            window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
        }
        view.wantsLayer = true
        window.setFrame(CGRect(origin: CGPoint(x: -30_000, y: -30_000), size: size), display: false)
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        view.layoutSubtreeIfNeeded()
        view.display()
        // Let Core Animation and SwiftUI commit what they drew.
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        guard
            let layer = view.layer,
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { throw RenderError(description: "can't make a bitmap for \(type(of: view))") }
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            context.setFillColor(background.cgColor)
        }
        context.fill(CGRect(origin: .zero, size: size))
        layer.render(in: context)
        guard let image = context.makeImage(),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw RenderError(description: "can't encode \(type(of: view)) as PNG") }
        return data
    }
}
