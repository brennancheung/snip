import Foundation

public enum EncodeError: Error, Equatable, LocalizedError {
    /// No ffmpeg binary was found. Use `FFmpegEncoder.fallbackCopy` to keep the recording.
    case ffmpegMissing
    /// ffmpeg exited with `status`; `log` is the end of what it wrote to stderr.
    case ffmpegFailed(status: Int32, log: String)

    public var errorDescription: String? {
        switch self {
        case .ffmpegMissing:
            return "ffmpeg wasn't found. Install it with: brew install ffmpeg"
        case let .ffmpegFailed(status, log):
            let lastLine = log.split(separator: "\n").last.map(String.init) ?? ""
            return "ffmpeg failed (exit \(status)): \(lastLine)"
        }
    }
}

/// Re-encodes the intermediate recording with x264 at the chosen CRF, which makes screen
/// recordings several times smaller than the hardware encode.
public struct FFmpegEncoder: RecordingEncoder {
    /// The ffmpeg binary, or nil when none was found (`encode` then throws `EncodeError.ffmpegMissing`).
    public let ffmpegURL: URL?

    /// `ffmpegURL` nil means `FFmpegEncoder.locate()`.
    public init(ffmpegURL: URL? = nil) {
        self.ffmpegURL = ffmpegURL ?? Self.locate()
    }

    /// Finds ffmpeg. An app launched from Finder doesn't get the Homebrew PATH, so the Homebrew
    /// locations are checked first, then PATH.
    public static func locate() -> URL? {
        let pathDirectories = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let candidates = ["/opt/homebrew/bin", "/usr/local/bin"] + pathDirectories
        return candidates
            .map { URL(fileURLWithPath: $0, isDirectory: true).appendingPathComponent("ffmpeg") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// The ffmpeg command line, without the executable. `audioStreams` is how many audio tracks the
    /// intermediate has (system audio), muted over `systemAudioOff`; `microphone` are the spans
    /// recorded while the mic was on. No audio drops it; one system track alone is encoded to AAC;
    /// anything more is mixed into one stereo AAC track, each microphone span placed at its offset.
    public static func arguments(
        intermediate: URL,
        output: URL,
        settings: RecordingSettings,
        audioStreams: Int = 0,
        microphone: [MicrophoneSpan] = [],
        systemAudioOff: [MuteSpan] = []
    ) -> [String] {
        ["-hide_banner", "-y", "-i", intermediate.path]
        + microphone.flatMap { ["-i", $0.url.path] }
        + [
            "-c:v", "libx264",
            "-crf", String(settings.crf),
            "-preset", settings.preset,
            "-pix_fmt", "yuv420p",
            // x264 with yuv420p needs even dimensions; a dragged region can be odd.
            "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2",
            // ScreenCaptureKit writes variable frame timing (r_frame_rate 120/1); resample to a constant rate.
            "-fps_mode", "cfr",
            "-r", String(settings.fps),
            "-movflags", "+faststart",
        ]
        + audioArguments(streams: max(audioStreams, 0), microphone: microphone, systemAudioOff: systemAudioOff)
        + [
            "-progress", "pipe:1",
            "-nostats",
            output.path,
        ]
    }

    private static func audioArguments(streams: Int, microphone: [MicrophoneSpan], systemAudioOff: [MuteSpan]) -> [String] {
        let aac = ["-c:a", "aac", "-b:a", "160k"]
        // Off for the whole recording: leave the system tracks out.
        let silent = systemAudioOff.contains { $0.start <= 0 && $0.end == nil }
        let streams = silent ? 0 : streams
        let mutes = silent ? [] : systemAudioOff
        if streams == 0 && microphone.isEmpty { return ["-an"] }
        if streams == 1 && microphone.isEmpty && mutes.isEmpty { return aac }

        // Every source to stereo first: amix otherwise takes the mono microphone's layout and folds
        // the system audio down to mono.
        let stereo = "aformat=channel_layouts=stereo"
        let muting = mutes.map(muteFilter).joined()
        var chains = (0..<streams).map { "[0:a:\($0)]\(muting)\(stereo)" }
        for (index, span) in microphone.enumerated() {
            chains.append("[\(index + 1):a:0]\(placement(of: span))\(stereo)")
        }
        let graph: String
        if chains.count == 1 {
            graph = chains[0] + "[a]"
        } else {
            let labels = chains.indices.map { "[s\($0)]" }
            // normalize=0 keeps each source at its own level instead of dividing by the input count.
            graph = zip(chains, labels).map { $0 + $1 + ";" }.joined()
                + labels.joined() + "amix=inputs=\(chains.count):duration=longest:normalize=0[a]"
        }
        return ["-filter_complex", graph, "-map", "0:v:0", "-map", "[a]"] + aac
    }

    /// Silences system audio over `span`. The quotes keep the expression's commas inside the filter.
    private static func muteFilter(_ span: MuteSpan) -> String {
        let start = seconds(max(span.start, 0))
        let window = span.end.map { "between(t,\(start),\(seconds($0)))" } ?? "gte(t,\(start))"
        return "volume=enable='\(window)':volume=0,"
    }

    private static func seconds(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    /// Delays a span to its offset, or trims the part recorded before the first frame.
    private static func placement(of span: MicrophoneSpan) -> String {
        let milliseconds = Int((span.offset * 1000).rounded())
        if milliseconds > 0 { return "adelay=delays=\(milliseconds):all=1," }
        if milliseconds < 0 { return "atrim=start=\(Double(-milliseconds) / 1000),asetpts=PTS-STARTPTS," }
        return ""
    }

    /// Encodes `media` to `output`, writing to a hidden temporary name in the output folder and
    /// moving it into place only when ffmpeg succeeds. The movie and the spans are left for the caller.
    public func encode(
        _ media: RecordedMedia,
        to output: URL,
        settings: RecordingSettings,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard let ffmpegURL else { throw EncodeError.ffmpegMissing }
        let fileManager = FileManager.default
        let directory = output.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let partial = directory.appendingPathComponent(".\(output.deletingPathExtension().lastPathComponent).encoding")
            .appendingPathExtension(output.pathExtension.isEmpty ? "mp4" : output.pathExtension)

        let run = FFmpegRun(
            ffmpeg: ffmpegURL,
            input: media.movie,
            arguments: { probe in
                // Spans are placed against the first frame; the file may start a little earlier.
                let lead = probe.videoLead
                let placed = media.microphone.map { MicrophoneSpan(url: $0.url, offset: $0.offset + lead) }
                let muted = media.systemAudioOff.map { MuteSpan(start: $0.start + lead, end: $0.end.map { $0 + lead }) }
                return Self.arguments(
                    intermediate: media.movie, output: partial, settings: settings,
                    audioStreams: probe.audioStreams, microphone: placed, systemAudioOff: muted
                )
            }
        )
        do {
            try await withTaskCancellationHandler {
                try await run.start(progress: progress)
            } onCancel: {
                run.cancel()
            }
            if fileManager.fileExists(atPath: output.path) {
                try fileManager.removeItem(at: output)
            }
            try fileManager.moveItem(at: partial, to: output)
        } catch {
            try? fileManager.removeItem(at: partial)
            throw error
        }
        progress(1)
    }

    /// When ffmpeg is missing or fails: moves the intermediate next to `output`, as a .mov with the
    /// same name, so the recording isn't lost. Returns where it went.
    @discardableResult
    public static func fallbackCopy(intermediate: URL, to output: URL) throws -> URL {
        let directory = output.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = OutputNaming.uniqueURL(
            in: directory,
            baseName: output.deletingPathExtension().lastPathComponent,
            ext: "mov"
        )
        try FileManager.default.moveItem(at: intermediate, to: destination)
        return destination
    }
}

/// Turns ffmpeg's `-progress` output (key=value lines) into 0...1 against the input's duration.
struct ProgressParser {
    let durationSeconds: Double?
    private var buffer = Data()

    init(durationSeconds: Double?) {
        self.durationSeconds = durationSeconds
    }

    /// Feeds a chunk of stdout; returns a fraction for each complete `out_time_us` line in it.
    mutating func feed(_ data: Data) -> [Double] {
        buffer.append(data)
        var fractions: [Double] = []
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
            buffer.removeSubrange(buffer.startIndex...newline)
            if let fraction = fraction(for: line) { fractions.append(fraction) }
        }
        return fractions
    }

    func fraction(for line: String) -> Double? {
        let parts = line.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1)
        guard parts.count == 2, parts[0] == "out_time_us",
              let micros = Double(parts[1]), let durationSeconds, durationSeconds > 0
        else { return nil }
        return min(max(micros / 1_000_000 / durationSeconds, 0), 1)
    }
}

/// What ffprobe says about the intermediate: its duration, how many audio tracks it has, and how
/// far the video starts after the earliest track.
struct InputProbe: Equatable {
    var durationSeconds: Double?
    var audioStreams: Int
    /// Seconds from the file's start (its earliest track) to the first video frame. The microphone
    /// spans are placed against the first frame, so they move by this much.
    var videoLead: Double = 0

    /// Without ffprobe the audio tracks are unknown: one keeps the first track, if there is one.
    static let unknown = InputProbe(durationSeconds: nil, audioStreams: 1)

    static let ffprobeArguments = [
        "-v", "error",
        "-show_entries", "format=duration:stream=codec_type,start_time",
        "-of", "compact",
    ]

    /// Parses ffprobe's compact lines: `stream|codec_type=video|start_time=0.033`, `format|duration=2.0`.
    init(ffprobeOutput: String) {
        var duration: Double?
        var audio = 0
        var videoStart: Double?
        var earliestStart: Double?
        for line in ffprobeOutput.split(whereSeparator: \.isNewline) {
            var fields: [Substring: Substring] = [:]
            for field in line.split(separator: "|").dropFirst() {
                let parts = field.split(separator: "=", maxSplits: 1)
                if parts.count == 2 { fields[parts[0]] = parts[1] }
            }
            if line.hasPrefix("format|") {
                duration = fields["duration"].flatMap { Double($0) }
                continue
            }
            let start = fields["start_time"].flatMap { Double($0) }
            if let start { earliestStart = min(earliestStart ?? start, start) }
            switch fields["codec_type"] {
            case "audio": audio += 1
            case "video" where videoStart == nil: videoStart = start
            default: break
            }
        }
        var lead = 0.0
        if let videoStart, let earliestStart { lead = max(videoStart - earliestStart, 0) }
        self.init(durationSeconds: duration, audioStreams: audio, videoLead: lead)
    }

    init(durationSeconds: Double?, audioStreams: Int, videoLead: Double = 0) {
        self.durationSeconds = durationSeconds
        self.audioStreams = audioStreams
        self.videoLead = videoLead
    }
}

/// One ffmpeg process, run on a background thread so the async caller isn't blocked.
private final class FFmpegRun: @unchecked Sendable {
    private let ffmpeg: URL
    private let input: URL
    /// The command line for what ffprobe found in the input.
    private let arguments: @Sendable (InputProbe) -> [String]
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    init(ffmpeg: URL, input: URL, arguments: @escaping @Sendable (InputProbe) -> [String]) {
        self.ffmpeg = ffmpeg
        self.input = input
        self.arguments = arguments
    }

    func start(progress: @escaping @Sendable (Double) -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.runBlocking(progress: progress)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func cancel() {
        lock.withLock {
            cancelled = true
            if let process, process.isRunning { process.terminate() }
        }
    }

    private func runBlocking(progress: @escaping @Sendable (Double) -> Void) throws {
        let probe = probeInput()
        var parser = ProgressParser(durationSeconds: probe.durationSeconds)

        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = arguments(probe)
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try lock.withLock {
            if cancelled { throw CancellationError() }
            try process.run()
            self.process = process
        }

        // Drain stderr on its own thread so a chatty ffmpeg never blocks on a full pipe.
        let errorOutput = DataBox()
        let stderrDone = DispatchGroup()
        stderrDone.enter()
        DispatchQueue.global(qos: .utility).async {
            errorOutput.data = stderr.fileHandleForReading.readDataToEndOfFile()
            stderrDone.leave()
        }

        let reader = stdout.fileHandleForReading
        while true {
            let chunk = reader.availableData
            if chunk.isEmpty { break }
            for fraction in parser.feed(chunk) { progress(fraction) }
        }
        process.waitUntilExit()
        stderrDone.wait()

        if lock.withLock({ cancelled }) { throw CancellationError() }
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            let log = String(decoding: errorOutput.data, as: UTF8.self)
                .split(separator: "\n", omittingEmptySubsequences: true)
                .suffix(15)
                .joined(separator: "\n")
            throw EncodeError.ffmpegFailed(status: process.terminationStatus, log: log)
        }
    }

    /// The input's duration, audio tracks and video lead from the ffprobe next to ffmpeg, or
    /// `InputProbe.unknown` (progress then only reports completion).
    private func probeInput() -> InputProbe {
        let ffprobe = ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe")
        guard FileManager.default.isExecutableFile(atPath: ffprobe.path) else { return .unknown }
        let process = Process()
        process.executableURL = ffprobe
        process.arguments = InputProbe.ffprobeArguments + [input.path]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let stdout = Pipe()
        process.standardOutput = stdout
        do { try process.run() } catch { return .unknown }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return .unknown }
        return InputProbe(ffprobeOutput: String(decoding: data, as: UTF8.self))
    }
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}
