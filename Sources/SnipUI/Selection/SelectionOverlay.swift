import AppKit
import Carbon.HIToolbox
import SnipCore

/// Dims every display and lets the user pick what to record: click a window, drag a box, or press
/// Space for the whole display. The pick ends at a bar with Record and Cancel.
@MainActor
public final class SelectionOverlay {
    private enum Pick {
        case region(CGRect, screen: Int)
        case window(OverlayWindow, screen: Int)
        case display(screen: Int)

        var screen: Int {
            switch self {
            case .region(_, let screen), .window(_, let screen), .display(let screen): screen
            }
        }
    }

    private enum Edit {
        case move(original: CGRect, from: CGPoint)
        /// `offset` is from the pointer to the handle when the drag began, so the handle doesn't jump.
        /// `moved` is how far holding Space has moved the box during the drag.
        case resize(original: CGRect, handle: Handle, offset: CGSize, moved: CGSize)

        var original: CGRect {
            switch self {
            case .move(let original, _), .resize(let original, _, _, _): original
            }
        }
    }

    private enum Mode {
        /// Nothing chosen; the window under the cursor, if any, is highlighted.
        case hover(OverlayWindow?)
        /// The mouse is down but hasn't moved far enough to be a drag. A click picks the window
        /// under it; with no window there, `previous` (if any) stays chosen.
        case pressing(start: CGPoint, screen: Int, previous: Pick?)
        /// Drawing a box from `start`. `offset` is from the pointer to the box's free corner; holding
        /// Space moves the box, and only a screen edge stopping it leaves the corner off the pointer.
        case drawing(start: CGPoint, screen: Int, rect: CGRect, offset: CGSize)
        /// Chosen, with the bar showing. `back` is where Space returns from the display.
        case selected(Pick, back: Pick?)
        /// A drawn box being moved or resized.
        case editing(rect: CGRect, screen: Int, edit: Edit)
    }

    private static let dragThreshold: CGFloat = 4
    private static let minimumSize: CGFloat = 4

    private var continuation: CheckedContinuation<CaptureTarget?, Never>?
    private var panels: [OverlayPanel] = []
    private var views: [OverlayView] = []
    private var screens: [ScreenInfo] = []
    private var windows: [OverlayWindow] = []
    private var mode = Mode.hover(nil)
    private var hintScreen = 0
    private var hintVisible = true
    private var pointer = CGPoint.zero
    private var shift = false
    /// Space went down while the mouse was down, and hasn't come up: the drag moves the box.
    private var spaceHeld = false
    private var previousApp: NSRunningApplication?
    private var screenObserver: NSObjectProtocol?
    private var resignObserver: NSObjectProtocol?

    public init() {}

    /// Shows the overlay on every display and returns what the user chose, or nil on Escape.
    /// The overlay is gone before this returns. Calling it again while it's open cancels the first call.
    public func choose() async -> CaptureTarget? {
        finish(nil)
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            show()
        }
    }

    // MARK: Showing and tearing down

    private func show() {
        let nsScreens = NSScreen.screens
        guard let primary = nsScreens.first else {
            finish(nil)
            return
        }
        screens = nsScreens.map(ScreenInfo.init)
        windows = WindowList.onScreen(primaryHeight: primary.frame.height)
        pointer = NSEvent.mouseLocation
        hintScreen = screenIndex(at: pointer)
        hintVisible = true
        shift = false
        spaceHeld = false
        mode = .hover(window(at: pointer))
        previousApp = NSWorkspace.shared.frontmostApplication

        for (screen, info) in zip(nsScreens, screens) {
            let panel = OverlayPanel(screen: screen)
            let view = OverlayView(screen: info, overlay: self)
            panel.contentView = view
            panel.makeFirstResponder(view)
            panels.append(panel)
            views.append(view)
        }
        render()

        NSApp.activate()
        for panel in panels { panel.orderFrontRegardless() }
        panels[hintScreen].makeKeyAndOrderFront(nil)
        NSCursor.crosshair.set()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(nil) }
        }
        // Losing focus loses the key up, so treat it as Space released.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.spaceHeld = false }
        }
    }

    private func finish(_ target: CaptureTarget?) {
        guard let continuation else { return }
        self.continuation = nil
        tearDown()
        continuation.resume(returning: target)
    }

    private func tearDown() {
        for panel in panels {
            panel.orderOut(nil)
            panel.close()
        }
        panels = []
        views = []
        windows = []
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        spaceHeld = false
        NSCursor.arrow.set()
        if let previousApp, previousApp != NSRunningApplication.current {
            previousApp.activate(options: [])
        }
        previousApp = nil
    }

    // MARK: Events from the views (global AppKit coordinates)

    func mouseMoved(to p: CGPoint) {
        pointer = p
        if case .hover(let current) = mode {
            let under = window(at: p)
            if under != current {
                mode = .hover(under)
                render()
            }
        }
        updateCursor()
    }

    func mouseDown(at p: CGPoint) {
        pointer = p
        // Only a Space pressed during this drag moves the box, not one still held from before it.
        spaceHeld = false
        switch mode {
        case .hover:
            mode = .pressing(start: p, screen: screenIndex(at: p), previous: nil)
        case .selected(let pick, _):
            if case .region(let rect, let screen) = pick {
                if let handle = SelectionGeometry.handle(at: p, in: rect) {
                    let h = handle.point(in: rect)
                    let offset = CGSize(width: h.x - p.x, height: h.y - p.y)
                    mode = .editing(rect: rect, screen: screen, edit: .resize(original: rect, handle: handle, offset: offset, moved: .zero))
                    return
                }
                if rect.contains(p) {
                    mode = .editing(rect: rect, screen: screen, edit: .move(original: rect, from: p))
                    NSCursor.closedHand.set()
                    return
                }
            }
            mode = .pressing(start: p, screen: screenIndex(at: p), previous: pick)
        default:
            break
        }
    }

    func mouseDragged(to p: CGPoint, shift: Bool) {
        let last = pointer
        pointer = p
        self.shift = shift
        switch mode {
        case .pressing(let start, let screen, _):
            guard hypot(p.x - start.x, p.y - start.y) > Self.dragThreshold else { return }
            hintVisible = false
            mode = .drawing(start: start, screen: screen, rect: drawnRect(from: start, to: p, screen: screen), offset: .zero)
            render()
        case .drawing(let start, let screen, _, let offset) where spaceHeld:
            // Move the box: the start corner and the free corner shift together.
            let bounds = screens[screen].frame
            let anchor = SelectionGeometry.clamp(start, to: bounds)
            let corner = CGPoint(x: last.x + offset.width, y: last.y + offset.height)
            let box = SelectionGeometry.rect(from: anchor, to: SelectionGeometry.clamp(corner, to: bounds))
            let move = SelectionGeometry.spaceMove(box: box, pulled: corner, from: last, to: p, within: bounds)
            let moved = CGPoint(x: anchor.x + move.shift.width, y: anchor.y + move.shift.height)
            mode = .drawing(start: moved, screen: screen, rect: drawnRect(from: moved, to: p, offset: move.offset, screen: screen), offset: move.offset)
            render()
        case .drawing(let start, let screen, _, let offset):
            mode = .drawing(start: start, screen: screen, rect: drawnRect(from: start, to: p, offset: offset, screen: screen), offset: offset)
            render()
        case .editing(let rect, let screen, .resize(let original, let handle, let offset, let moved)) where spaceHeld:
            // Move the box, and the handle's drag with it, so the resize carries on from there.
            let pulled = CGPoint(x: last.x + offset.width, y: last.y + offset.height)
            let move = SelectionGeometry.spaceMove(box: rect, pulled: pulled, from: last, to: p, within: screens[screen].frame)
            let total = CGSize(width: moved.width + move.shift.width, height: moved.height + move.shift.height)
            let edit = Edit.resize(original: original, handle: handle, offset: move.offset, moved: total)
            mode = .editing(rect: edited(edit, to: p, screen: screen), screen: screen, edit: edit)
            render()
        case .editing(_, let screen, let edit):
            mode = .editing(rect: edited(edit, to: p, screen: screen), screen: screen, edit: edit)
            render()
        default:
            break
        }
    }

    func mouseUp(at p: CGPoint) {
        pointer = p
        switch mode {
        case .pressing(_, _, let previous):
            if let under = window(at: p) {
                select(.window(under, screen: screenIndex(of: under)), back: nil)
            } else if let previous {
                select(previous, back: nil)
            } else {
                mode = .hover(nil)
                render()
            }
        case .drawing(_, let screen, let rect, _):
            if Self.isUsable(rect) {
                select(.region(rect, screen: screen), back: nil)
            } else {
                mode = .hover(window(at: p))
                render()
            }
        case .editing(let rect, let screen, let edit):
            select(.region(Self.isUsable(rect) ? rect : edit.original, screen: screen), back: nil)
        default:
            break
        }
        updateCursor()
    }

    func rightMouseDown() {
        if case .hover = mode { return }
        mode = .hover(window(at: pointer))
        render()
        updateCursor()
    }

    func flagsChanged(shift: Bool) {
        self.shift = shift
        guard case .editing(_, let screen, let edit) = mode, case .resize = edit else { return }
        mode = .editing(rect: edited(edit, to: pointer, screen: screen), screen: screen, edit: edit)
        render()
    }

    func keyDown(_ event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Escape:
            cancel()
        case kVK_Return, kVK_ANSI_KeypadEnter:
            record()
        case kVK_Space where !event.isARepeat:
            switch mode {
            case .pressing, .drawing, .editing:
                // The mouse is down: hold to move the box instead of resizing it.
                spaceHeld = true
            default:
                toggleDisplay()
            }
        default:
            break
        }
    }

    func keyUp(_ event: NSEvent) {
        if Int(event.keyCode) == kVK_Space { spaceHeld = false }
    }

    func record() {
        guard case .selected(let pick, _) = mode else { return }
        finish(target(for: pick))
    }

    func cancel() {
        finish(nil)
    }

    // MARK: State

    private func select(_ pick: Pick, back: Pick?) {
        mode = .selected(pick, back: back)
        hintVisible = false
        render()
    }

    /// Space: the whole display under the cursor, or back to what was chosen before it.
    private func toggleDisplay() {
        switch mode {
        case .hover:
            select(.display(screen: screenIndex(at: pointer)), back: nil)
        case .selected(.display(_), let back):
            if let back {
                select(back, back: nil)
            } else {
                mode = .hover(window(at: pointer))
                render()
            }
        case .selected(let pick, _):
            select(.display(screen: pick.screen), back: pick)
        default:
            break
        }
    }

    private func drawnRect(from start: CGPoint, to p: CGPoint, offset: CGSize = .zero, screen: Int) -> CGRect {
        let bounds = screens[screen].frame
        let a = SelectionGeometry.clamp(start, to: bounds)
        let b = SelectionGeometry.clamp(CGPoint(x: p.x + offset.width, y: p.y + offset.height), to: bounds)
        return SelectionGeometry.snapped(SelectionGeometry.rect(from: a, to: b))
    }

    private func edited(_ edit: Edit, to p: CGPoint, screen: Int) -> CGRect {
        let bounds = screens[screen].frame
        switch edit {
        case .move(let original, let from):
            return SelectionGeometry.snapped(SelectionGeometry.moved(original, dx: p.x - from.x, dy: p.y - from.y, within: bounds))
        case .resize(let original, let handle, let offset, let moved):
            let start = original.offsetBy(dx: moved.width, dy: moved.height)
            let target = CGPoint(x: p.x + offset.width, y: p.y + offset.height)
            return SelectionGeometry.snapped(SelectionGeometry.resized(start, handle: handle, to: target, keepAspect: shift, within: bounds))
        }
    }

    private static func isUsable(_ rect: CGRect) -> Bool {
        rect.width >= minimumSize && rect.height >= minimumSize
    }

    private func target(for pick: Pick) -> CaptureTarget {
        switch pick {
        case .region(let rect, let screen):
            let info = screens[screen]
            return .region(
                displayID: info.displayID,
                rect: SelectionGeometry.displayRelativeTopLeft(rect, screenFrame: info.frame)
            )
        case .window(let window, _):
            return .window(windowID: window.id)
        case .display(let screen):
            return .display(displayID: screens[screen].displayID)
        }
    }

    // MARK: Lookup

    /// The topmost window under `p`. `windows` is front to back.
    private func window(at p: CGPoint) -> OverlayWindow? {
        windows.first { $0.frame.contains(p) }
    }

    private func screenIndex(at p: CGPoint) -> Int {
        if let index = screens.firstIndex(where: { $0.frame.contains(p) }) { return index }
        // The mouse location can sit on a screen's top or right edge, which `contains` leaves out.
        func distance(_ r: CGRect) -> CGFloat {
            hypot(max(r.minX - p.x, 0, p.x - r.maxX), max(r.minY - p.y, 0, p.y - r.maxY))
        }
        return screens.indices.min { distance(screens[$0].frame) < distance(screens[$1].frame) } ?? 0
    }

    /// The screen showing most of `window`.
    private func screenIndex(of window: OverlayWindow) -> Int {
        func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }
        let best = screens.indices.max { area(screens[$0].frame.intersection(window.frame)) < area(screens[$1].frame.intersection(window.frame)) }
        guard let best, area(screens[best].frame.intersection(window.frame)) > 0 else {
            return screenIndex(at: CGPoint(x: window.frame.midX, y: window.frame.midY))
        }
        return best
    }

    private func rect(of pick: Pick) -> CGRect {
        switch pick {
        case .region(let rect, _): rect
        case .window(let window, _): window.frame
        case .display(let screen): screens[screen].frame
        }
    }

    private func sizeText(_ size: CGSize, screen: Int) -> String {
        SelectionGeometry.pixelSizeText(size, scale: screens[screen].scale)
    }

    // MARK: Drawing

    private func render() {
        var model = OverlayModel(hintScreen: screens[hintScreen].frame, hintVisible: hintVisible)
        switch mode {
        case .hover(let window):
            if let window {
                let screen = screenIndex(of: window)
                let name = window.appName.isEmpty ? "" : "\(window.appName) · "
                model.cutout = window.frame
                model.label = .init(
                    text: name + sizeText(window.frame.size, screen: screen),
                    inside: window.frame.intersection(screens[screen].frame)
                )
            }
        case .pressing:
            // Keep what's drawn until this turns out to be a click or a drag.
            return
        case .drawing(_, let screen, let rect, _):
            model.cutout = rect
            model.style = .region
            model.handles = true
            model.cornerSize = sizeText(rect.size, screen: screen)
        case .selected(let pick, _):
            let chosen = rect(of: pick)
            model.cutout = chosen
            if case .region = pick {
                model.style = .region
                model.handles = true
            }
            model.bar = .init(text: sizeText(chosen.size, screen: pick.screen), screenFrame: screens[pick.screen].frame)
        case .editing(let rect, let screen, _):
            model.cutout = rect
            model.style = .region
            model.handles = true
            model.bar = .init(text: sizeText(rect.size, screen: screen), screenFrame: screens[screen].frame)
        }
        for view in views { view.apply(model) }
    }

    private func updateCursor() {
        switch mode {
        case .selected(.region(let rect, _), _):
            if let handle = SelectionGeometry.handle(at: pointer, in: rect) {
                switch handle {
                case .left, .right: NSCursor.resizeLeftRight.set()
                case .top, .bottom: NSCursor.resizeUpDown.set()
                default: NSCursor.crosshair.set()
                }
            } else if rect.contains(pointer) {
                NSCursor.openHand.set()
            } else {
                NSCursor.crosshair.set()
            }
        case .editing:
            break
        default:
            NSCursor.crosshair.set()
        }
    }
}

/// A display as the overlay sees it, captured when the overlay opens.
struct ScreenInfo {
    let frame: CGRect
    let visibleFrame: CGRect
    let scale: CGFloat
    let displayID: CGDirectDisplayID

    @MainActor init(_ screen: NSScreen) {
        frame = screen.frame
        visibleFrame = screen.visibleFrame
        scale = screen.backingScaleFactor
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        displayID = number?.uint32Value ?? CGMainDisplayID()
    }
}
