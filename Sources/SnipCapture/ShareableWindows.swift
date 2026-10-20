import CoreGraphics
import Foundation
import ScreenCaptureKit

/// A window that can be recorded, as offered to the selection overlay and `snip-cli windows`.
public struct WindowInfo: Sendable, Equatable, Identifiable {
    public let id: CGWindowID
    public let appName: String
    public let bundleIdentifier: String
    public let processID: pid_t
    /// Empty when the app doesn't title the window.
    public let title: String
    /// Global points with a top-left origin (the `CGDisplayBounds` / `CGWindowList` space).
    public let frame: CGRect
    /// The display holding most of the window.
    public let displayID: CGDirectDisplayID
}

public enum ShareableWindows {
    /// Windows smaller than this in either dimension (points) are left out: tooltips, status items, slivers.
    public static let minimumSize: CGFloat = 40

    /// On-screen, normal-layer windows of other apps, front to back. Snip's own windows are left out.
    public static func list() async throws -> [WindowInfo] {
        let content = try await ShareableContent.fetch(onScreenWindowsOnly: true)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let order = frontToBackOrder()

        let windows = content.windows.compactMap { window -> WindowInfo? in
            guard window.isOnScreen, window.windowLayer == 0 else { return nil }
            guard let app = window.owningApplication, app.processID != ownPID else { return nil }
            let frame = window.frame
            guard frame.width >= minimumSize, frame.height >= minimumSize else { return nil }
            guard let displayID = Displays.displayID(holding: frame) else { return nil }
            return WindowInfo(
                id: window.windowID,
                appName: app.applicationName,
                bundleIdentifier: app.bundleIdentifier,
                processID: app.processID,
                title: window.title ?? "",
                frame: frame,
                displayID: displayID
            )
        }
        return windows.sorted { (order[$0.id] ?? .max) < (order[$1.id] ?? .max) }
    }

    /// Window numbers in z-order (0 is frontmost), from the window server.
    private static func frontToBackOrder() -> [CGWindowID: Int] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infos = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [:] }
        var order: [CGWindowID: Int] = [:]
        for (index, info) in infos.enumerated() {
            guard let number = info[kCGWindowNumber as String] as? NSNumber else { continue }
            order[number.uint32Value] = index
        }
        return order
    }
}

/// Fetches `SCShareableContent`, mapping a missing permission to `SnipCaptureError.permissionDenied`.
enum ShareableContent {
    static func fetch(onScreenWindowsOnly: Bool) async throws -> SCShareableContent {
        do {
            return try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: onScreenWindowsOnly)
        } catch {
            throw SnipCaptureError.from(error)
        }
    }
}

enum Displays {
    /// The active display with the largest overlap with `frame` (global points, top-left origin).
    static func displayID(holding frame: CGRect) -> CGDirectDisplayID? {
        var best: (id: CGDirectDisplayID, area: CGFloat)?
        for id in activeDisplayIDs() {
            let overlap = CGDisplayBounds(id).intersection(frame)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > (best?.area ?? 0) { best = (id, area) }
        }
        return best?.id
    }

    static func activeDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    /// Pixels per point for a display (2 on Retina), from its current display mode.
    static func backingScale(of displayID: CGDirectDisplayID) -> CGFloat {
        guard let mode = CGDisplayCopyDisplayMode(displayID), mode.width > 0 else { return 1 }
        return CGFloat(mode.pixelWidth) / CGFloat(mode.width)
    }
}
