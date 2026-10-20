import AppKit
import SnipCapture
import SnipCore

/// Owns the app's state machine: idle → selecting → countingDown → recording → encoding → finished.
/// Stub: the app shell worker fills it in.
@MainActor
public final class AppController: NSObject, NSApplicationDelegate {
    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {}
}
