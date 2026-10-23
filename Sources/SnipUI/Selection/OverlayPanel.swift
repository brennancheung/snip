import AppKit

/// A borderless, transparent panel over one whole screen, above everything including the menu bar,
/// on every space. Kept out of screen captures so it can never end up in a recording.
///
/// Non-activating: it takes the keys and the mouse without bringing Snip to the front. macOS may
/// refuse to activate a menu bar app opened by a shortcut, and then the first drag only activated
/// Snip and Escape went to the app underneath.
final class OverlayPanel: NSPanel {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        animationBehavior = .none
        sharingType = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
