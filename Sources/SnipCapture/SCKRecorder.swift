import Foundation
import ScreenCaptureKit
import SnipCore

/// ScreenCaptureKit implementation of `ScreenRecorder`. Stub: the capture worker fills it in.
public final class SCKRecorder: ScreenRecorder {
    public init() {}

    public func start(target: CaptureTarget, settings: RecordingSettings, intermediateURL: URL) async throws {
        fatalError("SCKRecorder.start not implemented")
    }

    public func stop() async throws -> URL {
        fatalError("SCKRecorder.stop not implemented")
    }

    public func cancel() async {}
}
