import Foundation

/// Records a CaptureTarget to an intermediate movie file. Implemented in SnipCapture with ScreenCaptureKit.
public protocol ScreenRecorder: AnyObject {
    /// Starts recording `target` into `intermediateURL` (a .mov in a temporary directory).
    func start(target: CaptureTarget, settings: RecordingSettings, intermediateURL: URL) async throws
    /// Stops and finalizes the file. Returns the intermediate file's URL.
    func stop() async throws -> URL
    /// Stops and deletes whatever was recorded.
    func cancel() async
}

/// Turns the intermediate recording into the small final file. Implemented by `FFmpegEncoder`.
public protocol RecordingEncoder: Sendable {
    /// `progress` is called with 0...1 as encoding proceeds.
    func encode(
        intermediate: URL,
        to output: URL,
        settings: RecordingSettings,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws
}

/// Where the app is, for the menu bar icon and HUD.
public enum RecorderState: Sendable, Equatable {
    case idle
    case selecting
    case countingDown(remaining: Int)
    case recording(startedAt: Date)
    case encoding(progress: Double)
    case finished(output: URL)
    case failed(message: String)
}
