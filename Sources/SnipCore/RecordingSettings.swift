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
    /// Where finished recordings go. nil means ~/Downloads.
    public var outputDirectory: URL? = nil

    public init() {}

    public var resolvedOutputDirectory: URL {
        outputDirectory ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }
}
