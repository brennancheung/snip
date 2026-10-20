import Foundation

/// The overlay's geometry, free of AppKit so it can be reasoned about (and tested) on its own.
///
/// Rects and points are in AppKit global coordinates (origin at the bottom-left of the primary
/// screen, y up) unless a name says otherwise. Quartz global coordinates (what
/// `CGWindowListCopyWindowInfo` and `CGDisplayBounds` report) put the origin at the top-left of
/// the primary display with y down.
enum SelectionGeometry {
    /// A rect in AppKit global coordinates as `CaptureTarget.region` wants it: in points, relative
    /// to the display's own top-left corner, y down. `screenFrame` is that display's `NSScreen.frame`.
    static func displayRelativeTopLeft(_ rect: CGRect, screenFrame: CGRect) -> CGRect {
        CGRect(
            x: rect.minX - screenFrame.minX,
            y: screenFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// A Quartz global rect (a window's `kCGWindowBounds`) in AppKit global coordinates.
    /// `primaryHeight` is the height of the primary screen, the one at the origin in both spaces.
    static func appKitRect(fromQuartz rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The rect spanned by two corners, in either order.
    static func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    static func clamp(_ p: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(x: min(max(p.x, bounds.minX), bounds.maxX), y: min(max(p.y, bounds.minY), bounds.maxY))
    }

    /// `rect` moved by (dx, dy), kept inside `bounds`.
    static func moved(_ rect: CGRect, dx: CGFloat, dy: CGFloat, within bounds: CGRect) -> CGRect {
        let x = min(max(rect.minX + dx, bounds.minX), bounds.maxX - rect.width)
        let y = min(max(rect.minY + dy, bounds.minY), bounds.maxY - rect.height)
        return CGRect(x: x, y: y, width: rect.width, height: rect.height)
    }

    /// Edges rounded to whole points, so the pixel size is a whole number on every display.
    static func snapped(_ rect: CGRect) -> CGRect {
        let x0 = rect.minX.rounded(), y0 = rect.minY.rounded()
        let x1 = rect.maxX.rounded(), y1 = rect.maxY.rounded()
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// "1440 × 900": `size` in points times the display's backing scale factor.
    static func pixelSizeText(_ size: CGSize, scale: CGFloat) -> String {
        let w = Int((size.width * scale).rounded())
        let h = Int((size.height * scale).rounded())
        return "\(w) × \(h)"
    }

    /// The handle at `p`, if any: a corner or edge handle within `tolerance`, else anywhere along an edge.
    static func handle(at p: CGPoint, in rect: CGRect, tolerance: CGFloat = 8) -> Handle? {
        func near(_ a: CGPoint) -> Bool { abs(a.x - p.x) <= tolerance && abs(a.y - p.y) <= tolerance }
        let corners: [Handle] = [.topLeft, .topRight, .bottomRight, .bottomLeft]
        let edges: [Handle] = [.top, .right, .bottom, .left]
        if let corner = corners.first(where: { near($0.point(in: rect)) }) { return corner }
        if let edge = edges.first(where: { near($0.point(in: rect)) }) { return edge }
        let edgeTolerance: CGFloat = 4
        let withinX = p.x >= rect.minX - edgeTolerance && p.x <= rect.maxX + edgeTolerance
        let withinY = p.y >= rect.minY - edgeTolerance && p.y <= rect.maxY + edgeTolerance
        if withinX && abs(p.y - rect.maxY) <= edgeTolerance { return .top }
        if withinX && abs(p.y - rect.minY) <= edgeTolerance { return .bottom }
        if withinY && abs(p.x - rect.minX) <= edgeTolerance { return .left }
        if withinY && abs(p.x - rect.maxX) <= edgeTolerance { return .right }
        return nil
    }

    /// `original` with `handle` dragged to `pointer`, kept inside `bounds`. The opposite corner or
    /// edge stays put, and dragging past it flips the rect. With `keepAspect`, the result keeps
    /// `original`'s aspect ratio; an edge handle then grows the other dimension about the centre.
    static func resized(
        _ original: CGRect,
        handle: Handle,
        to pointer: CGPoint,
        keepAspect: Bool,
        within bounds: CGRect
    ) -> CGRect {
        let p = clamp(pointer, to: bounds)
        var w = original.width, h = original.height
        var ax = original.minX, ay = original.minY
        var sx: CGFloat = 1, sy: CGFloat = 1
        if let edge = handle.x {
            ax = edge == .min ? original.maxX : original.minX
            w = abs(p.x - ax)
            sx = p.x >= ax ? 1 : -1
        }
        if let edge = handle.y {
            ay = edge == .min ? original.maxY : original.minY
            h = abs(p.y - ay)
            sy = p.y >= ay ? 1 : -1
        }

        let aspect = keepAspect && original.width > 0 && original.height > 0 ? original.width / original.height : nil
        if let aspect {
            switch (handle.x != nil, handle.y != nil) {
            case (true, true):
                if w / max(h, .ulpOfOne) > aspect { h = w / aspect } else { w = h * aspect }
            case (true, false):
                h = w / aspect
            default:
                w = h * aspect
            }
            // Shrink both sides together until the rect fits in the room it has.
            func room(anchor: CGFloat, sign: CGFloat, lo: CGFloat, hi: CGFloat) -> CGFloat {
                sign > 0 ? hi - anchor : anchor - lo
            }
            let roomW = handle.x != nil
                ? room(anchor: ax, sign: sx, lo: bounds.minX, hi: bounds.maxX)
                : 2 * min(original.midX - bounds.minX, bounds.maxX - original.midX)
            let roomH = handle.y != nil
                ? room(anchor: ay, sign: sy, lo: bounds.minY, hi: bounds.maxY)
                : 2 * min(original.midY - bounds.minY, bounds.maxY - original.midY)
            let scale = min(1, w > 0 ? roomW / w : 1, h > 0 ? roomH / h : 1)
            w *= scale
            h *= scale
        }

        let x: CGFloat
        if handle.x != nil { x = sx > 0 ? ax : ax - w } else if aspect != nil { x = original.midX - w / 2 } else { x = original.minX }
        let y: CGFloat
        if handle.y != nil { y = sy > 0 ? ay : ay - h } else if aspect != nil { y = original.midY - h / 2 } else { y = original.minY }
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

/// One of the eight resize handles of a drawn box. Top is the rect's maxY (AppKit, y up).
enum Handle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    enum Edge { case min, max }

    /// Which vertical edge the handle drags, if any.
    var x: Edge? {
        switch self {
        case .topLeft, .left, .bottomLeft: .min
        case .topRight, .right, .bottomRight: .max
        case .top, .bottom: nil
        }
    }

    /// Which horizontal edge the handle drags, if any.
    var y: Edge? {
        switch self {
        case .bottomLeft, .bottom, .bottomRight: .min
        case .topLeft, .top, .topRight: .max
        case .left, .right: nil
        }
    }

    func point(in rect: CGRect) -> CGPoint {
        let px: CGFloat = switch x { case .min: rect.minX; case .max: rect.maxX; case nil: rect.midX }
        let py: CGFloat = switch y { case .min: rect.minY; case .max: rect.maxY; case nil: rect.midY }
        return CGPoint(x: px, y: py)
    }
}
