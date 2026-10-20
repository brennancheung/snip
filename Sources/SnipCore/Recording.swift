import Foundation

/// One stretch of microphone audio, recorded to its own file while the microphone was on.
public struct MicrophoneSpan: Sendable, Equatable {
    public var url: URL
    /// Where the span starts on the movie's timeline, in seconds. Slightly negative when the
    /// microphone started just before the first frame.
    public var offset: Double

    public init(url: URL, offset: Double) {
        self.url = url
        self.offset = offset
    }
}

/// What a recording leaves behind: the movie (video, and system audio when it was on) and the
/// microphone spans, each in the temporary folder until encoded.
public struct RecordedMedia: Sendable, Equatable {
    public var movie: URL
    public var microphone: [MicrophoneSpan]

    public init(movie: URL, microphone: [MicrophoneSpan] = []) {
        self.movie = movie
        self.microphone = microphone
    }

    /// Deletes the movie and the microphone spans.
    public func remove() {
        for url in [movie] + microphone.map(\.url) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

/// Records a CaptureTarget to an intermediate movie file. Implemented in SnipCapture with ScreenCaptureKit.
public protocol ScreenRecorder: AnyObject {
    /// Starts recording `target` into `intermediateURL` (a .mov in a temporary directory), with the
    /// microphone when `settings.recordMicrophone` is on.
    func start(target: CaptureTarget, settings: RecordingSettings, intermediateURL: URL) async throws
    /// Turns the microphone on (`deviceID` nil is the default input) or off while recording.
    func setMicrophone(_ on: Bool, deviceID: String?) async throws
    /// Stops and finalizes the files.
    func stop() async throws -> RecordedMedia
    /// Stops and deletes whatever was recorded.
    func cancel() async
}

/// Turns the intermediate recording into the small final file. Implemented by `FFmpegEncoder`.
public protocol RecordingEncoder: Sendable {
    /// Mixes `microphone` in at its offsets. `progress` is called with 0...1 as encoding proceeds.
    func encode(
        intermediate: URL,
        microphone: [MicrophoneSpan],
        to output: URL,
        settings: RecordingSettings,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws
}

extension RecordingEncoder {
    /// Encodes a recording without microphone spans.
    public func encode(
        intermediate: URL,
        to output: URL,
        settings: RecordingSettings,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        try await encode(intermediate: intermediate, microphone: [], to: output, settings: settings, progress: progress)
    }
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
