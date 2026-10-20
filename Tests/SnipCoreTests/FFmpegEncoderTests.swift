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
        "-movflags", "+faststart", "-an", "-progress", "pipe:1", "-nostats",
        "/Users/me/Downloads/Snip 2026-10-19 at 14.03.22.mp4",
    ])
}

@Test(arguments: [(18, "slow"), (32, "veryfast")])
func argumentsCarryCRFAndPreset(crf: Int, preset: String) {
    var settings = RecordingSettings()
    settings.crf = crf
    settings.preset = preset
    let args = FFmpegEncoder.arguments(
        intermediate: URL(fileURLWithPath: "/tmp/in.mov"), output: URL(fileURLWithPath: "/tmp/out.mp4"), settings: settings
    )
    #expect(args[args.firstIndex(of: "-crf")! + 1] == String(crf))
    #expect(args[args.firstIndex(of: "-preset")! + 1] == preset)
    #expect(args.last == "/tmp/out.mp4")
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

private final class Fractions: @unchecked Sendable {
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
