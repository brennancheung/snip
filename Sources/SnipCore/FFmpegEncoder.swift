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
    /// intermediate has: none drops audio, one is encoded to AAC, more (system audio and microphone)
    /// are mixed into one AAC track.
    public static func arguments(intermediate: URL, output: URL, settings: RecordingSettings, audioStreams: Int = 0) -> [String] {
        [
            "-hide_banner",
            "-y",
            "-i", intermediate.path,
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
        + audioArguments(streams: audioStreams)
        + [
            "-progress", "pipe:1",
            "-nostats",
            output.path,
        ]
    }

    private static func audioArguments(streams: Int) -> [String] {
        let aac = ["-c:a", "aac", "-b:a", "160k"]
        switch streams {
        case ..<1:
            return ["-an"]
        case 1:
            return aac
        default:
            let inputs = (0..<streams).map { "[0:a:\($0)]" }.joined()
            return [
                // normalize=0 keeps each source at its own level instead of dividing by the input count.
                "-filter_complex", "\(inputs)amix=inputs=\(streams):duration=longest:normalize=0[a]",
                "-map", "0:v:0",
                "-map", "[a]",
            ] + aac
        }
    }

    /// Encodes `intermediate` to `output`, writing to a hidden temporary name in the output folder
    /// and moving it into place only when ffmpeg succeeds. The intermediate is left for the caller.
    public func encode(
        intermediate: URL,
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
            input: intermediate,
            arguments: { audioStreams in
                Self.arguments(intermediate: intermediate, output: partial, settings: settings, audioStreams: audioStreams)
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

/// What ffprobe says about the intermediate: its duration and how many audio tracks it has.
struct InputProbe: Equatable {
    var durationSeconds: Double?
    var audioStreams: Int

    /// Without ffprobe the audio tracks are unknown: one keeps the first track, if there is one.
    static let unknown = InputProbe(durationSeconds: nil, audioStreams: 1)

    static let ffprobeArguments = [
        "-v", "error",
        "-show_entries", "format=duration:stream=codec_type",
        "-of", "default=noprint_wrappers=1",
    ]

    /// Parses ffprobe's `key=value` lines (`codec_type=video`, `codec_type=audio`, `duration=2.0`).
    init(ffprobeOutput: String) {
        var duration: Double?
        var audio = 0
        for line in ffprobeOutput.split(whereSeparator: \.isNewline) {
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "codec_type" where parts[1] == "audio": audio += 1
            case "duration": duration = Double(parts[1])
            default: break
            }
        }
        self.init(durationSeconds: duration, audioStreams: audio)
    }

    init(durationSeconds: Double?, audioStreams: Int) {
        self.durationSeconds = durationSeconds
        self.audioStreams = audioStreams
    }
}

/// One ffmpeg process, run on a background thread so the async caller isn't blocked.
private final class FFmpegRun: @unchecked Sendable {
    private let ffmpeg: URL
    private let input: URL
    /// The command line for the number of audio tracks the input has.
    private let arguments: @Sendable (Int) -> [String]
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    init(ffmpeg: URL, input: URL, arguments: @escaping @Sendable (Int) -> [String]) {
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
        process.arguments = arguments(probe.audioStreams)
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

    /// The input's duration and audio track count from the ffprobe next to ffmpeg, or
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
