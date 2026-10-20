import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Why a capture couldn't start or finish. `errorDescription` is written to be shown to the user as is.
public enum SnipCaptureError: LocalizedError, Sendable, Equatable {
    /// Screen Recording permission is off for this app (or, for snip-cli, for the terminal running it).
    case permissionDenied
    case windowNotFound(CGWindowID)
    case displayNotFound(CGDirectDisplayID)
    /// The region doesn't overlap its display, or is smaller than a couple of pixels.
    case regionOutsideDisplay(CGRect)
    case alreadyRecording
    case notRecording
    /// The capture stopped on its own: the window closed, the display went away, or the user
    /// stopped sharing from the system menu.
    case streamStopped(String)
    case captureFailed(String)
    /// Writing the intermediate movie failed.
    case recordingFailed(String)
    /// The recording output never reported that the file was finished.
    case finishTimedOut
    /// The microphone couldn't be opened.
    case microphoneFailed(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Snip doesn't have Screen Recording permission. Turn it on in System Settings › "
                + "Privacy & Security › Screen & System Audio Recording, then quit and reopen the app."
        case .windowNotFound(let id):
            return "Window \(id) isn't there any more. It may have closed; choose it again."
        case .displayNotFound(let id):
            return "Display \(id) isn't connected."
        case .regionOutsideDisplay(let rect):
            return "The region \(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))×\(Int(rect.height)) "
                + "is not on that display."
        case .alreadyRecording:
            return "A recording is already running."
        case .notRecording:
            return "Nothing is being recorded."
        case .streamStopped(let reason):
            return "The recording stopped: \(reason)"
        case .captureFailed(let reason):
            return "Screen capture failed: \(reason)"
        case .recordingFailed(let reason):
            return "Writing the recording failed: \(reason)"
        case .finishTimedOut:
            return "The recording didn't finish writing in time; the file may be incomplete."
        case .microphoneFailed(let reason):
            return "The microphone couldn't be recorded: \(reason)"
        }
    }

    /// Maps a ScreenCaptureKit error to a `SnipCaptureError`, recognising a missing permission.
    static func from(_ error: Error, otherwise wrap: (String) -> SnipCaptureError = SnipCaptureError.captureFailed) -> SnipCaptureError {
        if let error = error as? SnipCaptureError { return error }
        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain && nsError.code == SCStreamError.Code.userDeclined.rawValue {
            return .permissionDenied
        }
        if !CGPreflightScreenCaptureAccess() { return .permissionDenied }
        return wrap(nsError.localizedDescription)
    }

    /// True when the user ended the capture from the system's screen sharing menu; the file is still good.
    static func isUserStopped(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == SCStreamErrorDomain && nsError.code == SCStreamError.Code.userStopped.rawValue
    }
}

/// Screen Recording permission (TCC). For snip-cli the permission belongs to the terminal app.
public enum ScreenCapturePermission {
    public static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt the first time and adds the app to the Screen Recording list.
    /// Returns whether access is granted now; a fresh grant usually needs a relaunch.
    @discardableResult
    public static func request() -> Bool { CGRequestScreenCaptureAccess() }

    /// Opens System Settings at Privacy & Security › Screen & System Audio Recording.
    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
}
