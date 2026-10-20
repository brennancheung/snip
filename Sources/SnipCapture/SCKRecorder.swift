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
    private var microphone: MicrophoneSpans?
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

        // The microphone opens first, so its span covers the first frame.
        let microphone = MicrophoneSpans(movieURL: intermediateURL)
        if settings.recordMicrophone {
            try await microphone.turnOn(deviceID: settings.microphoneDeviceID)
        }
        do {
            let session = try RecordingSession(filter: plan.filter, configuration: plan.configuration, url: intermediateURL)
            session.onUnexpectedStop = { [weak self] error in self?.onUnexpectedStop?(error) }
            try await session.start()
            lock.withLock {
                self.session = session
                self.microphone = microphone
            }
        } catch {
            await microphone.discard()
            throw error
        }
    }

    public func setMicrophone(_ on: Bool, deviceID: String?) async throws {
        guard let microphone = lock.withLock({ self.microphone }) else { throw SnipCaptureError.notRecording }
        if on {
            try await microphone.turnOn(deviceID: deviceID)
        } else {
            await microphone.turnOff()
        }
    }

    public func stop() async throws -> RecordedMedia {
        guard let taken = take() else { throw SnipCaptureError.notRecording }
        let (session, microphone) = taken
        // The mic and the screen stop together; spans are placed against the movie's first frame.
        let movieStart = session.firstFrameTime
        async let spans = microphone.finish(movieStart: movieStart)
        do {
            let movie = try await session.finish()
            return RecordedMedia(movie: movie, microphone: await spans)
        } catch {
            for span in await spans { try? FileManager.default.removeItem(at: span.url) }
            throw error
        }
    }

    public func cancel() async {
        guard let taken = take() else { return }
        let (session, microphone) = taken
        async let discarded: Void = microphone.discard()
        await session.discard()
        await discarded
    }

    private func take() -> (RecordingSession, MicrophoneSpans)? {
        lock.withLock { () -> (RecordingSession, MicrophoneSpans)? in
            defer {
                session = nil
                microphone = nil
            }
            guard let session, let microphone else { return nil }
            return (session, microphone)
        }
    }
}
