import AppKit
import CoreGraphics
import Foundation
import SnipCapture
import SnipCore

// snip-cli: drive capture and encode without the UI.

enum Help {
    static let usage = """
    usage:
      snip-cli windows
      snip-cli displays
      snip-cli record (--window <id> | --rect x,y,w,h [--display <id>] | --display <id>)
                      [--seconds 5] [--fps 30] [--crf 23] [--scale full|half] [--no-cursor] [--out <path>]

      windows   lists recordable windows, front to back: id, app, title, size in points.
      displays  lists displays: id, size in points, pixel scale.
      record    records for --seconds (0 means until Ctrl-C; Ctrl-C always stops early),
                compresses with ffmpeg (x264 at --crf) and prints the final path. --out is a
                file or a folder; the default is "Snip <date>.mp4" in ~/Downloads. Without
                ffmpeg the uncompressed .mov is kept instead.
                --rect is in points, top-left origin, relative to the display (the main display
                unless --display is given).
    """
}

func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func fail(_ message: String, code: Int32 = 1) -> Never {
    printError(message)
    exit(code)
}

func failPermission() -> Never {
    printError("""
        Screen Recording permission is missing for the app running snip-cli (your terminal).

          1. Open System Settings › Privacy & Security › Screen & System Audio Recording
             (open "\(ScreenCapturePermission.settingsURL.absoluteString)")
          2. Turn on Terminal (or iTerm, Ghostty, whichever runs this). If it isn't listed, it is
             now: this run asked for it.
          3. Quit and reopen the terminal, then run snip-cli again.
        """)
    ScreenCapturePermission.request()
    exit(2)
}

func report(_ error: Error) -> Never {
    if let error = error as? SnipCaptureError, error == .permissionDenied { failPermission() }
    fail("error: \(error.localizedDescription)")
}

func formatSize(_ size: CGSize) -> String {
    "\(Int(size.width))×\(Int(size.height))"
}

func formatBytes(_ url: URL) -> String {
    let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
    return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

func padded(_ text: String, _ width: Int) -> String {
    let clipped = text.count > width ? String(text.prefix(width - 1)) + "…" : text
    return clipped.padding(toLength: width, withPad: " ", startingAt: 0)
}

// MARK: - windows, displays

func listWindows() async {
    do {
        let windows = try await ShareableWindows.list()
        print(padded("ID", 8) + padded("APP", 24) + padded("TITLE", 48) + "SIZE")
        for window in windows {
            print(padded(String(window.id), 8) + padded(window.appName, 24) + padded(window.title, 48) + formatSize(window.frame.size))
        }
    } catch {
        report(error)
    }
}

func listDisplays() {
    var count: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &count)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetActiveDisplayList(count, &ids, &count)
    print(padded("ID", 12) + padded("SIZE (pt)", 14) + padded("SCALE", 7) + "ORIGIN")
    for id in ids.prefix(Int(count)) {
        let bounds = CGDisplayBounds(id)
        let mode = CGDisplayCopyDisplayMode(id)
        let scale = mode.map { $0.width > 0 ? Double($0.pixelWidth) / Double($0.width) : 1 } ?? 1
        let main = CGDisplayIsMain(id) != 0 ? "  (main)" : ""
        print(padded(String(id), 12) + padded(formatSize(bounds.size), 14) + padded("\(scale)x", 7)
            + "\(Int(bounds.minX)),\(Int(bounds.minY))\(main)")
    }
}

// MARK: - record

struct RecordOptions {
    var windowID: CGWindowID?
    var rect: CGRect?
    var displayID: CGDirectDisplayID?
    var seconds: Double = 5
    var settings = RecordingSettings()
    var out: String?

    var target: CaptureTarget {
        if let windowID {
            if rect != nil || displayID != nil { fail("--window can't be combined with --rect or --display\n\n\(Help.usage)") }
            return .window(windowID: windowID)
        }
        if let rect { return .region(displayID: displayID ?? CGMainDisplayID(), rect: rect) }
        if let displayID { return .display(displayID: displayID) }
        fail("record needs --window, --rect or --display\n\n\(Help.usage)")
    }
}

func parseRecordOptions(_ arguments: [String]) -> RecordOptions {
    var options = RecordOptions()
    var index = 0
    func value(_ flag: String) -> String {
        index += 1
        guard index < arguments.count else { fail("\(flag) needs a value\n\n\(Help.usage)") }
        return arguments[index]
    }
    func number<T: LosslessStringConvertible>(_ flag: String, as type: T.Type) -> T {
        let text = value(flag)
        guard let parsed = T(text) else { fail("\(flag): '\(text)' is not a valid number") }
        return parsed
    }

    while index < arguments.count {
        let flag = arguments[index]
        switch flag {
        case "--window": options.windowID = number(flag, as: CGWindowID.self)
        case "--display": options.displayID = number(flag, as: CGDirectDisplayID.self)
        case "--rect":
            let text = value(flag)
            let parts = text.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 4, parts[2] > 0, parts[3] > 0 else { fail("--rect wants x,y,w,h in points, e.g. 100,100,1280,720") }
            options.rect = CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
        case "--seconds":
            options.seconds = number(flag, as: Double.self)
            if options.seconds < 0 { fail("--seconds can't be negative") }
        case "--fps": options.settings.fps = number(flag, as: Int.self)
        case "--crf": options.settings.crf = number(flag, as: Int.self)
        case "--scale":
            let text = value(flag)
            guard let scale = RecordingSettings.Scale(rawValue: text) else { fail("--scale is full or half") }
            options.settings.scale = scale
        case "--no-cursor": options.settings.showCursor = false
        case "--out": options.out = value(flag)
        case "-h", "--help": print(Help.usage); exit(0)
        default: fail("unknown option \(flag)\n\n\(Help.usage)")
        }
        index += 1
    }
    return options
}

/// Resolves once, with the first reason given: the timer, Ctrl-C, or the stream stopping on its own.
final class StopSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var reason: String?
    private var continuation: CheckedContinuation<String, Never>?

    func fire(_ reason: String) {
        let continuation: CheckedContinuation<String, Never>? = lock.withLock {
            guard self.reason == nil else { return nil }
            self.reason = reason
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume(returning: reason)
    }

    func wait() async -> String {
        await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            let fired: String? = lock.withLock {
                if let reason { return reason }
                self.continuation = continuation
                return nil
            }
            if let fired { continuation.resume(returning: fired) }
        }
    }
}

func describe(_ target: CaptureTarget) async -> String {
    switch target {
    case .window(let id):
        let window = try? await ShareableWindows.list().first(where: { $0.id == id })
        guard let window else { return "window \(id)" }
        let title = window.title.isEmpty ? "" : " “\(window.title)”"
        return "window \(id) (\(window.appName)\(title), \(formatSize(window.frame.size)) pt)"
    case .region(let displayID, let rect):
        return "region \(Int(rect.minX)),\(Int(rect.minY)) \(formatSize(rect.size)) pt on display \(displayID)"
    case .display(let displayID):
        return "display \(displayID)"
    }
}

func record(_ arguments: [String]) async {
    let options = parseRecordOptions(arguments)
    let target = options.target
    let settings = options.settings
    let intermediate = OutputNaming.intermediateURL()

    let recorder = SCKRecorder()
    let stop = StopSignal()
    recorder.onUnexpectedStop = { error in stop.fire(error.localizedDescription) }

    signal(SIGINT, SIG_IGN)
    let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
    interrupt.setEventHandler { stop.fire("Ctrl-C") }
    interrupt.resume()

    do {
        try await recorder.start(target: target, settings: settings, intermediateURL: intermediate)
    } catch {
        report(error)
    }

    let length = options.seconds > 0 ? "for \(options.seconds)s (Ctrl-C stops early)" : "until Ctrl-C"
    let description = await describe(target)
    printError("Recording \(description) at \(settings.fps) fps \(length)…")
    if options.seconds > 0 {
        DispatchQueue.global().asyncAfter(deadline: .now() + options.seconds) { stop.fire("time") }
    }

    let reason = await stop.wait()
    if reason != "time" { printError("Stopping: \(reason)") }
    interrupt.cancel()
    signal(SIGINT, SIG_DFL)

    let url: URL
    do {
        url = try await recorder.stop()
    } catch {
        report(error)
    }
    printError("Intermediate: \(url.path) (\(formatBytes(url)))")
    await compress(url, out: options.out, settings: settings)
}

/// Encodes the intermediate to `--out` (a file, or a folder to name it in), or to a new
/// "Snip <date>.mp4" in the output folder. Prints the final path on stdout.
func compress(_ intermediate: URL, out: String?, settings: RecordingSettings) async {
    let output: URL
    if let out {
        var isDirectory: ObjCBool = false
        let url = URL(fileURLWithPath: (out as NSString).expandingTildeInPath)
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        output = exists && isDirectory.boolValue ? OutputNaming.outputURL(in: url) : url
    } else {
        output = OutputNaming.outputURL(in: settings.resolvedOutputDirectory)
    }

    let started = Date()
    do {
        try await FFmpegEncoder().encode(intermediate: intermediate, to: output, settings: settings) { progress in
            FileHandle.standardError.write(Data(String(format: "\rCompressing… %3d%%", Int(progress * 100)).utf8))
        }
        let seconds = String(format: "%.1f", Date().timeIntervalSince(started))
        printError("\rCompressed in \(seconds)s: \(formatBytes(output))")
        try? FileManager.default.removeItem(at: intermediate)
        print(output.path)
    } catch EncodeError.ffmpegMissing {
        printError("ffmpeg wasn't found (brew install ffmpeg); keeping the uncompressed recording.")
        do {
            let kept = try FFmpegEncoder.fallbackCopy(intermediate: intermediate, to: output)
            printError("Saved: \(formatBytes(kept))")
            print(kept.path)
        } catch {
            fail("error: couldn't move \(intermediate.path) to \(output.path): \(error.localizedDescription)")
        }
    } catch let EncodeError.ffmpegFailed(status, log) {
        fail("\nffmpeg failed (exit \(status)):\n\(log)\nThe intermediate is kept at \(intermediate.path)")
    } catch {
        fail("\nerror: \(error.localizedDescription)\nThe intermediate is kept at \(intermediate.path)")
    }
}

// MARK: - main

// The commands run in a Task while the main run loop spins, so ScreenCaptureKit and dispatch
// callbacks that expect a live main thread get one.
let arguments = Array(CommandLine.arguments.dropFirst())
// Opens the window server connection that window capture needs; without it a desktop-independent
// window filter crashes in CGS_REQUIRE_INIT.
_ = NSApplication.shared
Task {
    switch arguments.first {
    case "windows": await listWindows()
    case "displays": listDisplays()
    case "record": await record(Array(arguments.dropFirst()))
    case "-h", "--help", "help": print(Help.usage)
    default: fail(Help.usage)
    }
    exit(0)
}
RunLoop.main.run()
