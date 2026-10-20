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
        "-filter_complex",
        "[0:a:0]aformat=channel_layouts=stereo[s0];[0:a:1]aformat=channel_layouts=stereo[s1];"
            + "[s0][s1]amix=inputs=2:duration=longest:normalize=0[a]",
        "-map", "0:v:0", "-map", "[a]",
        "-c:a", "aac", "-b:a", "160k",
    ]))
    #expect(args.last == "/tmp/out.mp4")
}

@Test func microphoneAloneIsOneTrack() {
    let span = MicrophoneSpan(url: URL(fileURLWithPath: "/tmp/mic-1.m4a"), offset: 0)
    let args = FFmpegEncoder.arguments(
        intermediate: URL(fileURLWithPath: "/tmp/in.mov"), output: URL(fileURLWithPath: "/tmp/out.mp4"),
        settings: RecordingSettings(), audioStreams: 0, microphone: [span]
    )
    #expect(Array(args.prefix(6)) == ["-hide_banner", "-y", "-i", "/tmp/in.mov", "-i", "/tmp/mic-1.m4a"])
    #expect(!args.contains("-an"))
    #expect(args.containsSequence([
        "-filter_complex", "[1:a:0]aformat=channel_layouts=stereo[a]",
        "-map", "0:v:0", "-map", "[a]",
        "-c:a", "aac", "-b:a", "160k",
    ]))
}

@Test func microphoneSpansArePlacedAndMixedWithSystemAudio() {
    let spans = [
        // Started 40 ms before the first frame: the first 40 ms are cut.
        MicrophoneSpan(url: URL(fileURLWithPath: "/tmp/mic-1.m4a"), offset: -0.04),
        // Turned back on 12.5 s in.
        MicrophoneSpan(url: URL(fileURLWithPath: "/tmp/mic-2.m4a"), offset: 12.5),
    ]
    let args = FFmpegEncoder.arguments(
        intermediate: URL(fileURLWithPath: "/tmp/in.mov"), output: URL(fileURLWithPath: "/tmp/out.mp4"),
        settings: RecordingSettings(), audioStreams: 1, microphone: spans
    )
    #expect(Array(args.prefix(8)) == [
        "-hide_banner", "-y", "-i", "/tmp/in.mov", "-i", "/tmp/mic-1.m4a", "-i", "/tmp/mic-2.m4a",
    ])
    #expect(args.containsSequence([
        "-filter_complex",
        "[0:a:0]aformat=channel_layouts=stereo[s0];"
            + "[1:a:0]atrim=start=0.04,asetpts=PTS-STARTPTS,aformat=channel_layouts=stereo[s1];"
            + "[2:a:0]adelay=delays=12500:all=1,aformat=channel_layouts=stereo[s2];"
            + "[s0][s1][s2]amix=inputs=3:duration=longest:normalize=0[a]",
        "-map", "0:v:0", "-map", "[a]",
    ]))
    #expect(args.last == "/tmp/out.mp4")
}

@Test func probeOutputCountsAudioStreams() {
    let both = InputProbe(ffprobeOutput: """
        stream|codec_type=video|start_time=0.040000
        stream|codec_type=audio|start_time=0.000000
        stream|codec_type=audio|start_time=0.010000
        format|duration=4.250000
        """)
    #expect(both.audioStreams == 2)
    #expect(both.durationSeconds == 4.25)
    #expect(abs(both.videoLead - 0.04) < 1e-9)
    let silent = InputProbe(ffprobeOutput: "stream|codec_type=video|start_time=N/A\nformat|duration=N/A\n")
    #expect(silent == InputProbe(durationSeconds: nil, audioStreams: 0, videoLead: 0))
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

/// The output's streams as ffprobe lists them, e.g. ["video h264", "audio aac 2ch"].
func streams(of url: URL, ffmpeg: URL) throws -> [String] {
    let probe = Process()
    probe.executableURL = ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe")
    probe.arguments = ["-v", "error", "-show_entries", "stream=codec_type,codec_name,channels", "-of", "json", url.path]
    let stdout = Pipe()
    probe.standardOutput = stdout
    try probe.run()
    let data = stdout.fileHandleForReading.readDataToEndOfFile()
    probe.waitUntilExit()
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let streams = try #require(json["streams"] as? [[String: Any]])
    return streams.map { stream in
        let description = "\(stream["codec_type"] ?? "?") \(stream["codec_name"] ?? "?")"
        guard let channels = stream["channels"] else { return description }
        return description + " \(channels)ch"
    }
}

@Test(
    .enabled(if: FFmpegEncoder.locate() != nil, "ffmpeg is not installed"),
    arguments: [([], nil), ([440], "audio aac 1ch"), ([440, 660], "audio aac 2ch")] as [([Int], String?)]
)
func encodesAudioToOneAACTrack(tones: [Int], audio: String?) async throws {
    let ffmpeg = try #require(FFmpegEncoder.locate())
    let directory = try temporaryDirectory()
    let intermediate = directory.appendingPathComponent("clip.mov")
    try generateClip(ffmpeg, to: intermediate, tones: tones)
    let output = directory.appendingPathComponent("out.mp4")
    try await FFmpegEncoder(ffmpegURL: ffmpeg).encode(
        intermediate: intermediate, to: output, settings: RecordingSettings(), progress: { _ in }
    )
    // A mono microphone alone stays mono; mixed with stereo system audio it is stereo.
    #expect(try streams(of: output, ffmpeg: ffmpeg) == ["video h264"] + (audio.map { [$0] } ?? []))
}

/// Mean volume in dB of `frequency` between `start` and `end` seconds of `url`'s audio.
func toneVolume(_ url: URL, ffmpeg: URL, frequency: Int, from start: Double, to end: Double) throws -> Double {
    let measure = Process()
    measure.executableURL = ffmpeg
    measure.arguments = [
        "-hide_banner", "-nostats", "-i", url.path, "-map", "0:a",
        "-af", "atrim=\(start):\(end),bandpass=f=\(frequency):w=20,volumedetect", "-f", "null", "-",
    ]
    let stderr = Pipe()
    measure.standardError = stderr
    measure.standardOutput = FileHandle.nullDevice
    try measure.run()
    let log = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    measure.waitUntilExit()
    let line = try #require(log.split(separator: "\n").first { $0.contains("mean_volume:") })
    let value = line.split(separator: ":").last!.replacingOccurrences(of: "dB", with: "")
    return try #require(Double(value.trimmingCharacters(in: .whitespaces)))
}

/// `videoDelay`: the first frame comes that long after the system audio starts, as when
/// ScreenCaptureKit writes audio before the first frame. `offset`: the span's offset from that frame.
@Test(
    .enabled(if: FFmpegEncoder.locate() != nil, "ffmpeg is not installed"),
    arguments: [(0.0, 1.0), (0.5, 0.0)]
)
func microphoneSpanIsHeardOnlyWhereItWasOn(videoDelay: Double, offset: Double) async throws {
    let ffmpeg = try #require(FFmpegEncoder.locate())
    let directory = try temporaryDirectory()
    // Three seconds of 660 Hz system audio with the video, and a one-second 440 Hz microphone span.
    let intermediate = directory.appendingPathComponent("clip.mov")
    let generate = Process()
    generate.executableURL = ffmpeg
    generate.arguments = [
        "-v", "error", "-itsoffset", String(videoDelay),
        "-f", "lavfi", "-i", "testsrc=duration=\(3 - videoDelay):size=320x240:rate=30",
        "-f", "lavfi", "-i", "sine=frequency=660:duration=3:sample_rate=48000,aformat=channel_layouts=stereo",
        "-c:a", "pcm_s16le", intermediate.path,
    ]
    try generate.run()
    generate.waitUntilExit()
    let span = directory.appendingPathComponent("mic-1.m4a")
    let tone = Process()
    tone.executableURL = ffmpeg
    tone.arguments = ["-v", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=1:sample_rate=48000", span.path]
    try tone.run()
    tone.waitUntilExit()
    try #require(generate.terminationStatus == 0 && tone.terminationStatus == 0)

    let output = directory.appendingPathComponent("out.mp4")
    try await FFmpegEncoder(ffmpegURL: ffmpeg).encode(
        intermediate: intermediate, microphone: [MicrophoneSpan(url: span, offset: offset)],
        to: output, settings: RecordingSettings(), progress: { _ in }
    )
    #expect(try streams(of: output, ffmpeg: ffmpeg) == ["video h264", "audio aac 2ch"])
    let heard = videoDelay + offset
    let during = try toneVolume(output, ffmpeg: ffmpeg, frequency: 440, from: heard + 0.1, to: heard + 0.9)
    let after = try toneVolume(output, ffmpeg: ffmpeg, frequency: 440, from: heard + 1.1, to: heard + 1.9)
    #expect(during > after + 20)
    if heard >= 0.5 {
        let before = try toneVolume(output, ffmpeg: ffmpeg, frequency: 440, from: 0.1, to: heard - 0.1)
        #expect(during > before + 20)
    }
    let system = try toneVolume(output, ffmpeg: ffmpeg, frequency: 660, from: 0.1, to: 2.9)
    #expect(system > -40)
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
