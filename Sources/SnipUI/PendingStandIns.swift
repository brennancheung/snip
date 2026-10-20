// TEMPORARY STAND-INS. Delete this whole file at integration.
//
// Minimal versions of APIs other work items are adding, so SnipUI builds on main before they
// merge. Each mirrors the name and shape AppController codes against:
//   #2217 (SnipCore): FFmpegEncoder, EncodeError, OutputNaming, SettingsStore, HotKeySpec, RecentRecordings
//   #2218 (SnipUI):   HotKey, SelectionOverlay
//   #2216 (SnipCapture): SCKRecorder.onUnexpectedStop
// Once a real one lands, delete its stand-in here (a SnipUI declaration shadows the SnipCore one).

import AppKit
import SnipCore

// MARK: - #2217, SnipCore (on branch agent/ahc6q)

enum EncodeError: Error, Equatable {
    case ffmpegMissing
    case ffmpegFailed(status: Int32, log: String)
}

/// Stand-in: always reports ffmpeg missing, so the app takes the fallback path.
struct FFmpegEncoder: RecordingEncoder {
    init(ffmpegURL: URL? = nil) {}

    static func locate() -> URL? { nil }

    /// Moves the intermediate next to `output` as a .mov; returns where it went.
    @discardableResult
    static func fallbackCopy(intermediate: URL, to output: URL) throws -> URL {
        let destination = output.deletingPathExtension().appendingPathExtension("mov")
        try FileManager.default.moveItem(at: intermediate, to: destination)
        return destination
    }

    func encode(
        intermediate: URL,
        to output: URL,
        settings: RecordingSettings,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        throw EncodeError.ffmpegMissing
    }
}

enum OutputNaming {
    /// "Snip 2026-10-19 at 14.03.22.mp4" in `directory`.
    static func outputURL(in directory: URL, date: Date = Date(), ext: String = "mp4") -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return directory.appendingPathComponent("Snip \(formatter.string(from: date)).\(ext)")
    }

    static func intermediateURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("snip-\(UUID().uuidString).mov")
    }
}

struct HotKeySpec: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
}

/// Stand-in: keeps settings in memory only.
final class SettingsStore {
    static let shared = SettingsStore()
    static let didChange = Notification.Name("SnipSettingsDidChange")

    var settings = RecordingSettings()
    /// ⇧⌘6: kVK_ANSI_6 with shiftKey | cmdKey.
    var hotKey = HotKeySpec(keyCode: 0x16, carbonModifiers: 0x0100 | 0x0200)
}

/// Stand-in: keeps nothing.
struct RecentRecordings {
    struct Entry: Equatable, Sendable {
        var url: URL
        var sizeBytes: Int64
        var date: Date
    }

    func add(url: URL, date: Date = Date()) {}

    /// Newest first, files that still exist.
    func list() -> [Entry] { [] }
}

// MARK: - #2218, SnipUI (HotKey is on branch agent/a2qui; SelectionOverlay isn't pushed yet)

/// Stand-in: registers nothing.
@MainActor
final class HotKey {
    init(keyCode: UInt32, carbonModifiers: UInt32, handler: @escaping @MainActor () -> Void) throws {}
    func unregister() {}
}

/// Stand-in: chooses the main display without showing anything.
@MainActor
final class SelectionOverlay {
    init() {}
    func choose() async -> CaptureTarget? { .display(displayID: CGMainDisplayID()) }
}

// MARK: - #2216, SnipCapture (on branch agent/a9gej)

/// Stand-in for `SCKRecorder.onUnexpectedStop`, which main's stub lacks. Delete it as soon as
/// the real recorder merges, or the two declarations are ambiguous.
extension SCKRecorder {
    var onUnexpectedStop: (@Sendable (Error) -> Void)? {
        get { nil }
        set {}
    }
}
