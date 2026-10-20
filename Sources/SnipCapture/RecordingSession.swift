import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

/// One SCStream with an SCRecordingOutput writing to `url`. Lives from start until the file is finished.
/// It is the stream's and the recording output's delegate; their callbacks arrive on arbitrary queues.
final class RecordingSession: NSObject, @unchecked Sendable {
    let url: URL
    /// Called once if the stream stops on its own (window closed, display gone, user stopped sharing).
    var onUnexpectedStop: (@Sendable (SnipCaptureError) -> Void)?

    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private let frameQueue = DispatchQueue(label: "snip.capture.frames", qos: .userInitiated)

    private let lock = NSLock()
    /// How the recording output ended: finished, or failed with an error.
    private var outcome: Result<Void, Error>?
    private var waiter: CheckedContinuation<Void, Error>?
    private var stopping = false

    init(filter: SCContentFilter, configuration: SCStreamConfiguration, url: URL) throws {
        self.url = url
        super.init()

        let outputConfiguration = SCRecordingOutputConfiguration()
        outputConfiguration.outputURL = url
        outputConfiguration.outputFileType = .mov
        // H.264 so the intermediate is playable anywhere if it ends up kept as the result (no ffmpeg).
        let codecs = outputConfiguration.availableVideoCodecTypes
        if codecs.contains(.h264) {
            outputConfiguration.videoCodecType = .h264
        } else if let first = codecs.first {
            outputConfiguration.videoCodecType = first
        }
        let recordingOutput = SCRecordingOutput(configuration: outputConfiguration, delegate: self)

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        do {
            // The frames themselves are dropped; a screen output stops ScreenCaptureKit from logging
            // "stream output NOT found" for every frame.
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: frameQueue)
            try stream.addRecordingOutput(recordingOutput)
        } catch {
            throw SnipCaptureError.from(error)
        }
        self.stream = stream
        self.recordingOutput = recordingOutput
    }

    func start() async throws {
        guard let stream else { throw SnipCaptureError.notRecording }
        do {
            try await stream.startCapture()
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw SnipCaptureError.from(error)
        }
    }

    /// Stops the stream and waits for the recording output to finish the file.
    func finish() async throws -> URL {
        await stopStream()
        defer { release() }
        do {
            try await waitForOutcome(timeout: 15)
        } catch {
            throw SnipCaptureError.from(error, otherwise: SnipCaptureError.recordingFailed)
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SnipCaptureError.recordingFailed("no frames were recorded")
        }
        return url
    }

    /// Stops the stream and deletes whatever was written.
    func discard() async {
        await stopStream()
        try? await waitForOutcome(timeout: 5)
        release()
        try? FileManager.default.removeItem(at: url)
    }

    private func stopStream() async {
        lock.withLock { stopping = true }
        // Throws when the stream already stopped on its own; the recording output still reports how it ended.
        try? await stream?.stopCapture()
    }

    /// Drops the stream and recording output, only once the file is finished: releasing the output
    /// earlier could cut its finalization short. Removing the screen output breaks the stream → self cycle.
    private func release() {
        if let stream {
            try? stream.removeStreamOutput(self, type: .screen)
        }
        stream = nil
        recordingOutput = nil
    }

    private func waitForOutcome(timeout: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let finished: Result<Void, Error>? = lock.withLock {
                if let outcome { return outcome }
                waiter = continuation
                return nil
            }
            if let finished {
                continuation.resume(with: finished)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.complete(.failure(SnipCaptureError.finishTimedOut))
            }
        }
    }

    /// Records the first outcome and wakes the waiter, if any. Later outcomes are ignored.
    private func complete(_ result: Result<Void, Error>) {
        let waiter: CheckedContinuation<Void, Error>? = lock.withLock {
            guard outcome == nil else { return nil }
            outcome = result
            defer { self.waiter = nil }
            return self.waiter
        }
        waiter?.resume(with: result)
    }
}

extension RecordingSession: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let wasStopping = lock.withLock { stopping }
        guard !wasStopping else { return }
        let reason: SnipCaptureError
        if SnipCaptureError.isUserStopped(error) {
            reason = .streamStopped("sharing was stopped from the menu bar")
        } else {
            reason = SnipCaptureError.from(error, otherwise: SnipCaptureError.streamStopped)
        }
        onUnexpectedStop?(reason)
    }
}

extension RecordingSession: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {}
}

extension RecordingSession: SCRecordingOutputDelegate {
    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        complete(.failure(error))
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        complete(.success(()))
    }
}
