import Foundation
import Testing
@testable import SnipCore

@Test func argumentsForDefaultSettings() {
    let input = URL(fileURLWithPath: "/tmp/in.mov")
    let output = URL(fileURLWithPath: "/Users/me/Downloads/Snip 2026-10-19 at 14.03.22.mp4")
    let args = FFmpegEncoder.arguments(intermediate: input, output: output, settings: RecordingSettings())
    #expect(args == [
        "-hide_banner", "-y", "-i", "/tmp/in.mov",
        "-c:v", "libx264", "-crf", "23", "-preset", "medium", "-pix_fmt", "yuv420p",
        "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2",
        "-fps_mode", "cfr", "-r", "30",
        "-movflags", "+faststart", "-an", "-progress", "pipe:1", "-nostats",
        "/Users/me/Downloads/Snip 2026-10-19 at 14.03.22.mp4",
    ])
}

@Test(arguments: [(18, "slow", 60), (32, "veryfast", 30)])
func argumentsCarryCRFPresetAndFPS(crf: Int, preset: String, fps: Int) {
    var settings = RecordingSettings()
    settings.crf = crf
    settings.preset = preset
    settings.fps = fps
    let args = FFmpegEncoder.arguments(
        intermediate: URL(fileURLWithPath: "/tmp/in.mov"), output: URL(fileURLWithPath: "/tmp/out.mp4"), settings: settings
    )
    #expect(args[args.firstIndex(of: "-crf")! + 1] == String(crf))
    #expect(args[args.firstIndex(of: "-preset")! + 1] == preset)
    #expect(args[args.firstIndex(of: "-r")! + 1] == String(fps))
    #expect(args.last == "/tmp/out.mp4")
}

@Test func oneAudioStreamIsEncodedToAAC() {
    let args = FFmpegEncoder.arguments(
        intermediate: URL(fileURLWithPath: "/tmp/in.mov"), output: URL(fileURLWithPath: "/tmp/out.mp4"),
        settings: RecordingSettings(), audioStreams: 1
    )
    #expect(!args.contains("-an"))
    #expect(!args.contains("-filter_complex"))
    #expect(!args.contains("-map"))
    #expect(args.containsSequence(["-c:a", "aac", "-b:a", "160k"]))
    #expect(args.last == "/tmp/out.mp4")
}

@Test func twoAudioStreamsAreMixedIntoOne() {
    let args = FFmpegEncoder.arguments(
        intermediate: URL(fileURLWithPath: "/tmp/in.mov"), output: URL(fileURLWithPath: "/tmp/out.mp4"),
        settings: RecordingSettings(), audioStreams: 2
    )
    #expect(!args.contains("-an"))
    #expect(args.containsSequence([
        "-filter_complex", "[0:a:0][0:a:1]amix=inputs=2:duration=longest:normalize=0[a]",
        "-map", "0:v:0", "-map", "[a]",
        "-c:a", "aac", "-b:a", "160k",
    ]))
    #expect(args.last == "/tmp/out.mp4")
}

@Test func probeOutputCountsAudioStreams() {
    let both = InputProbe(ffprobeOutput: "codec_type=video\ncodec_type=audio\ncodec_type=audio\nduration=4.250000\n")
    #expect(both == InputProbe(durationSeconds: 4.25, audioStreams: 2))
    let silent = InputProbe(ffprobeOutput: "codec_type=video\nduration=N/A\n")
    #expect(silent == InputProbe(durationSeconds: nil, audioStreams: 0))
}

@Test func progressLinesBecomeFractions() {
    var parser = ProgressParser(durationSeconds: 4)
    #expect(parser.feed(Data("frame=10\nout_time_us=1000000\nout_ti".utf8)) == [0.25])
    #expect(parser.feed(Data("me_us=N/A\nout_time_us=9000000\nprogress=end\n".utf8)) == [1])
    var unknownDuration = ProgressParser(durationSeconds: nil)
    #expect(unknownDuration.feed(Data("out_time_us=1000000\n".utf8)).isEmpty)
}

@Test func fallbackMovesIntermediateAsMov() throws {
    let directory = try temporaryDirectory()
    let intermediate = directory.appendingPathComponent("in.mov")
    try Data("movie".utf8).write(to: intermediate)
    let output = directory.appendingPathComponent("Snip 2026-10-19 at 14.03.22.mp4")
    let result = try FFmpegEncoder.fallbackCopy(intermediate: intermediate, to: output)
    #expect(result.lastPathComponent == "Snip 2026-10-19 at 14.03.22.mov")
    #expect(FileManager.default.fileExists(atPath: result.path))
    #expect(!FileManager.default.fileExists(atPath: intermediate.path))
}

@Test func missingFFmpegThrows() async throws {
    var encoder = FFmpegEncoder(ffmpegURL: nil)
    if encoder.ffmpegURL != nil {
        encoder = FFmpegEncoder(ffmpegURL: URL(fileURLWithPath: "/nonexistent/ffmpeg"))
    }
    let output = try temporaryDirectory().appendingPathComponent("out.mp4")
    await #expect(throws: (any Error).self) {
        try await encoder.encode(
            intermediate: URL(fileURLWithPath: "/tmp/in.mov"), to: output, settings: RecordingSettings(), progress: { _ in }
        )
    }
}

@Test(.enabled(if: FFmpegEncoder.locate() != nil, "ffmpeg is not installed"))
func encodesAGeneratedClip() async throws {
    let ffmpeg = try #require(FFmpegEncoder.locate())
    let directory = try temporaryDirectory()
    let intermediate = directory.appendingPathComponent("clip.mov")
    let generate = Process()
    generate.executableURL = ffmpeg
    // An odd size, to exercise the even-dimension guard.
    generate.arguments = ["-v", "error", "-f", "lavfi", "-i", "testsrc=duration=2:size=321x241:rate=30", intermediate.path]
    try generate.run()
    generate.waitUntilExit()
    try #require(generate.terminationStatus == 0)

    let output = OutputNaming.outputURL(in: directory)
    let seen = Fractions()
    try await FFmpegEncoder(ffmpegURL: ffmpeg).encode(
        intermediate: intermediate, to: output, settings: RecordingSettings(), progress: { seen.append($0) }
    )
    let size = try FileManager.default.attributesOfItem(atPath: output.path)[.size] as? NSNumber
    #expect((size?.intValue ?? 0) > 0)
    #expect(seen.values.last == 1)
    #expect(seen.values == seen.values.sorted())
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix(".") }
    #expect(leftovers.isEmpty)
}

@Test(.enabled(if: FFmpegEncoder.locate() != nil, "ffmpeg is not installed"))
func failedEncodeReportsStderr() async throws {
    let directory = try temporaryDirectory()
    let intermediate = directory.appendingPathComponent("broken.mov")
    try Data("not a movie".utf8).write(to: intermediate)
    let output = directory.appendingPathComponent("out.mp4")
    do {
        try await FFmpegEncoder().encode(intermediate: intermediate, to: output, settings: RecordingSettings(), progress: { _ in })
        Issue.record("expected a failure")
    } catch let EncodeError.ffmpegFailed(status, log) {
        #expect(status != 0)
        #expect(!log.isEmpty)
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["broken.mov"])
}

/// Generates a clip with ffmpeg: a video test pattern plus one sine tone per frequency, each its own track.
func generateClip(_ ffmpeg: URL, to url: URL, tones: [Int]) throws {
    var arguments = ["-v", "error", "-f", "lavfi", "-i", "testsrc=duration=2:size=321x241:rate=30"]
    for (index, frequency) in tones.enumerated() {
        // A mono microphone and a stereo system track, as ScreenCaptureKit may write them.
        let layout = index == 0 ? "mono" : "stereo"
        arguments += ["-f", "lavfi", "-i", "sine=frequency=\(frequency):duration=2,aformat=channel_layouts=\(layout)"]
    }
    arguments += ["-map", "0:v"]
    for index in tones.indices { arguments += ["-map", "\(index + 1):a"] }
    arguments += ["-c:a", "pcm_s16le", url.path]
    let generate = Process()
    generate.executableURL = ffmpeg
    generate.arguments = arguments
    try generate.run()
    generate.waitUntilExit()
    try #require(generate.terminationStatus == 0)
}

/// The output's streams as ffprobe lists them, e.g. ["video h264", "audio aac"].
func streams(of url: URL, ffmpeg: URL) throws -> [String] {
    let probe = Process()
    probe.executableURL = ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe")
    probe.arguments = ["-v", "error", "-show_entries", "stream=codec_type,codec_name", "-of", "csv=p=0", url.path]
    let stdout = Pipe()
    probe.standardOutput = stdout
    try probe.run()
    let data = stdout.fileHandleForReading.readDataToEndOfFile()
    probe.waitUntilExit()
    // csv prints codec_name,codec_type in the order ffprobe holds them; normalise to "type name".
    return String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).map { line in
        let fields = line.split(separator: ",").map(String.init)
        return fields.count == 2 ? "\(fields[1]) \(fields[0])" : String(line)
    }
}

@Test(
    .enabled(if: FFmpegEncoder.locate() != nil, "ffmpeg is not installed"),
    arguments: [[], [440], [440, 660]]
)
func encodesAudioToOneAACTrack(tones: [Int]) async throws {
    let ffmpeg = try #require(FFmpegEncoder.locate())
    let directory = try temporaryDirectory()
    let intermediate = directory.appendingPathComponent("clip.mov")
    try generateClip(ffmpeg, to: intermediate, tones: tones)
    let output = directory.appendingPathComponent("out.mp4")
    try await FFmpegEncoder(ffmpegURL: ffmpeg).encode(
        intermediate: intermediate, to: output, settings: RecordingSettings(), progress: { _ in }
    )
    let expected = tones.isEmpty ? ["video h264"] : ["video h264", "audio aac"]
    #expect(try streams(of: output, ffmpeg: ffmpeg) == expected)
}

extension Array where Element: Equatable {
    func containsSequence(_ sequence: [Element]) -> Bool {
        guard sequence.count <= count else { return false }
        return (0...(count - sequence.count)).contains { Array(self[$0..<($0 + sequence.count)]) == sequence }
    }
}

final class Fractions: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Double] = []
    func append(_ value: Double) { lock.lock(); stored.append(value); lock.unlock() }
    var values: [Double] { lock.lock(); defer { lock.unlock() }; return stored }
}

func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("SnipTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
