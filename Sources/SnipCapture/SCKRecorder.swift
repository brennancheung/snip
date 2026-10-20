import CoreMedia
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
    /// Host times where system audio was off; the last stretch has no end while it is still off.
    private var systemAudioOff: [(start: CMTime, end: CMTime?)] = []
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

        // System audio is always captured; off from the start is one stretch from before the first frame.
        lock.withLock {
            systemAudioOff = settings.recordSystemAudio ? [] : [(Self.now(), nil)]
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

    public func setSystemAudio(_ on: Bool) {
        lock.withLock {
            let isOff = systemAudioOff.last.map { $0.end == nil } ?? false
            if on, isOff {
                systemAudioOff[systemAudioOff.count - 1].end = Self.now()
            } else if !on, !isOff {
                systemAudioOff.append((Self.now(), nil))
            }
        }
    }

    public func stop() async throws -> RecordedMedia {
        guard let taken = take() else { throw SnipCaptureError.notRecording }
        let (session, microphone) = taken
        // The mic and the screen stop together; spans are placed against the movie's first frame.
        let movieStart = session.firstFrameTime
        let muted = mutedStretches(from: movieStart ?? Self.now())
        async let spans = microphone.finish(movieStart: movieStart)
        do {
            let movie = try await session.finish()
            return RecordedMedia(movie: movie, microphone: await spans, systemAudioOff: muted)
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

    /// The stretches where system audio was off, in seconds from `movieStart`.
    private func mutedStretches(from movieStart: CMTime) -> [MuteSpan] {
        lock.withLock {
            systemAudioOff.map { stretch in
                MuteSpan(
                    start: CMTimeSubtract(stretch.start, movieStart).seconds,
                    end: stretch.end.map { CMTimeSubtract($0, movieStart).seconds }
                )
            }
        }
    }

    private static func now() -> CMTime {
        CMClockGetTime(CMClockGetHostTimeClock())
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
