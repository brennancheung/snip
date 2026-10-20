import AppKit
import SnipCore

/// Converts capture targets to AppKit screen rectangles for the countdown, border and pill.
///
/// CoreGraphics uses a global space with a top-left origin at the main display's top-left corner;
/// AppKit uses a bottom-left origin at the main display's bottom-left corner.
@MainActor
enum ScreenGeometry {
    static func appKitRect(fromGlobalCG rect: CGRect) -> CGRect {
        let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
        return CGRect(x: rect.minX, y: mainHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The target's current area in AppKit screen coordinates, or nil if a window target is gone.
    static func appKitRect(for target: CaptureTarget) -> CGRect? {
        switch target {
        case .region(let displayID, let rect):
            let display = CGDisplayBounds(displayID)
            return appKitRect(fromGlobalCG: rect.offsetBy(dx: display.minX, dy: display.minY))
        case .display(let displayID):
            return appKitRect(fromGlobalCG: CGDisplayBounds(displayID))
        case .window(let windowID):
            return windowBounds(windowID).map(appKitRect(fromGlobalCG:))
        }
    }

    /// A window's frame in global CG coordinates (without its shadow).
    static func windowBounds(_ windowID: CGWindowID) -> CGRect? {
        guard
            let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
            let info = list.first,
            let bounds = info[kCGWindowBounds as String] as? NSDictionary
        else { return nil }
        return CGRect(dictionaryRepresentation: bounds as CFDictionary)
    }

    /// The screen showing most of `rect`.
    static func screen(for rect: CGRect) -> NSScreen? {
        NSScreen.screens.max { a, b in
            area(a.frame.intersection(rect)) < area(b.frame.intersection(rect))
        } ?? NSScreen.main
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }
}

/// Window settings shared by Snip's floating windows: on every Space, over full-screen apps,
/// and kept out of screen captures.
extension NSWindow {
    func configureAsSnipOverlay(level: NSWindow.Level) {
        self.level = level
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        sharingType = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }
}
