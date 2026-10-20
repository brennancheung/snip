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

/// A stretch of the movie where system audio was turned off, in seconds on the movie's timeline.
public struct MuteSpan: Sendable, Equatable {
    public var start: Double
    /// nil: still off when the recording stopped.
    public var end: Double?

    public init(start: Double, end: Double?) {
        self.start = start
        self.end = end
    }
}

/// What a recording leaves behind: the movie (video and system audio) and the microphone spans,
/// each in the temporary folder until encoded, and where system audio was off.
public struct RecordedMedia: Sendable, Equatable {
    public var movie: URL
    public var microphone: [MicrophoneSpan]
    /// System audio is always captured, so it can be turned on mid-recording; these stretches are muted.
    public var systemAudioOff: [MuteSpan]

    public init(movie: URL, microphone: [MicrophoneSpan] = [], systemAudioOff: [MuteSpan] = []) {
        self.movie = movie
        self.microphone = microphone
        self.systemAudioOff = systemAudioOff
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
    /// Turns system audio on or off while recording (off stretches are muted when encoding).
    func setSystemAudio(_ on: Bool)
    /// Stops and finalizes the files.
    func stop() async throws -> RecordedMedia
    /// Stops and deletes whatever was recorded.
    func cancel() async
}

/// Turns the intermediate recording into the small final file. Implemented by `FFmpegEncoder`.
public protocol RecordingEncoder: Sendable {
    /// Encodes `media.movie`, muting system audio where it was off and mixing the microphone spans
    /// in at their offsets. `progress` is called with 0...1 as encoding proceeds.
    func encode(
        _ media: RecordedMedia,
        to output: URL,
        settings: RecordingSettings,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws
}

extension RecordingEncoder {
    /// Encodes a movie as it is, without microphone spans or muting.
    public func encode(
        intermediate: URL,
        to output: URL,
        settings: RecordingSettings,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        try await encode(RecordedMedia(movie: intermediate), to: output, settings: settings, progress: progress)
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
