import CoreGraphics
import Foundation

/// What to record. Chosen by the selection overlay (SnipUI) or passed on the command line (snip-cli).
public enum CaptureTarget: Sendable, Equatable {
    /// A rectangle on one display, in that display's points with a top-left origin
    /// (the same space as `CGDisplayBounds`, relative to the display's own origin).
    case region(displayID: CGDirectDisplayID, rect: CGRect)
    /// One window, followed wherever it moves (ScreenCaptureKit desktop-independent window filter).
    case window(windowID: CGWindowID)
    /// A whole display.
    case display(displayID: CGDirectDisplayID)
}
