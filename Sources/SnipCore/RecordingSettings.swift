import Foundation

/// The user's recording preferences. Persisted by `SettingsStore`.
public struct RecordingSettings: Sendable, Codable, Equatable {
    public enum Scale: String, Sendable, Codable, CaseIterable {
        /// Native pixels (2x on a Retina display).
        case full
        /// Half the native pixels: a Retina recording at 1x.
        case half
    }

    public var fps: Int = 30
    /// x264 constant rate factor. Lower is sharper and larger; 23 is the x264 default.
    public var crf: Int = 23
    /// x264 preset; slower presets give smaller files at the same quality.
    public var preset: String = "medium"
    public var scale: Scale = .full
    public var showCursor: Bool = true
    public var countdownSeconds: Int = 3
    /// Put the finished file on the pasteboard so it can be pasted into Slack, Mail and the like.
    public var copyToClipboard: Bool = true
    /// Where finished recordings go. nil means `defaultOutputDirectory`, ~/Movies/snip.
    public var outputDirectory: URL? = nil
    public var recordMicrophone: Bool = false
    /// The microphone's `AVCaptureDevice.uniqueID`. nil means the system default input.
    public var microphoneDeviceID: String? = nil
    public var recordSystemAudio: Bool = true

    public init() {}

    /// ~/Movies/snip.
    public static var defaultOutputDirectory: URL {
        FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("snip", isDirectory: true)
    }

    public var resolvedOutputDirectory: URL {
        outputDirectory ?? Self.defaultOutputDirectory
    }

    /// Sets the output folder, storing nil when `url` is the default so it follows the default.
    public mutating func setOutputDirectory(_ url: URL) {
        let isDefault = url.standardizedFileURL.path == Self.defaultOutputDirectory.standardizedFileURL.path
        outputDirectory = isDefault ? nil : url
    }

    /// The output folder, created (with any missing parents) if it doesn't exist.
    public func createOutputDirectory() throws -> URL {
        let directory = resolvedOutputDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

extension RecordingSettings {
    /// Decodes saved settings, using the default for any key that is missing or unreadable,
    /// so settings saved by an older build still load after a field is added.
    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? container.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        fps = value(.fps, fps)
        crf = value(.crf, crf)
        preset = value(.preset, preset)
        scale = value(.scale, scale)
        showCursor = value(.showCursor, showCursor)
        countdownSeconds = value(.countdownSeconds, countdownSeconds)
        copyToClipboard = value(.copyToClipboard, copyToClipboard)
        outputDirectory = value(.outputDirectory, outputDirectory)
        recordMicrophone = value(.recordMicrophone, recordMicrophone)
        microphoneDeviceID = value(.microphoneDeviceID, microphoneDeviceID)
        recordSystemAudio = value(.recordSystemAudio, recordSystemAudio)
    }
}
