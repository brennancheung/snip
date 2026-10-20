import Foundation
import ScreenCaptureKit
import SnipCore

/// ScreenCaptureKit implementation of `ScreenRecorder`: records a window, a region or a display
/// to a hardware-encoded H.264 .mov with `SCRecordingOutput`. One recording at a time.
public final class SCKRecorder: ScreenRecorder, @unchecked Sendable {
    /// Called (on an arbitrary queue) if the capture stops on its own: the window closed, the display
    /// went away, or the user stopped sharing from the menu bar. Call `stop()` to finish the file.
    public var onUnexpectedStop: (@Sendable (SnipCaptureError) -> Void)?

    private let lock = NSLock()
    private var session: RecordingSession?
    private var starting = false

    public init() {}

    public func start(target: CaptureTarget, settings: RecordingSettings, intermediateURL: URL) async throws {
        try lock.withLock {
            guard self.session == nil, !starting else { throw SnipCaptureError.alreadyRecording }
            starting = true
        }
        defer { lock.withLock { starting = false } }

        // All windows, not only on-screen ones, so a window on another Space is still found.
        let content = try await ShareableContent.fetch(onScreenWindowsOnly: false)
        let plan = try CapturePlan.make(target: target, settings: settings, content: content)

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: intermediateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: intermediateURL.path) {
            try fileManager.removeItem(at: intermediateURL)
        }

        let session = try RecordingSession(filter: plan.filter, configuration: plan.configuration, url: intermediateURL)
        session.onUnexpectedStop = { [weak self] error in self?.onUnexpectedStop?(error) }
        try await session.start()
        lock.withLock { self.session = session }
    }

    public func stop() async throws -> URL {
        guard let session = takeSession() else { throw SnipCaptureError.notRecording }
        return try await session.finish()
    }

    public func cancel() async {
        guard let session = takeSession() else { return }
        await session.discard()
    }

    private func takeSession() -> RecordingSession? {
        lock.withLock { () -> RecordingSession? in
            defer { session = nil }
            return session
        }
    }
}
