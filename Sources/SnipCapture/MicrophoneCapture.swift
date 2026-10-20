import AVFoundation
import CoreMedia
import Foundation
import SnipCore

/// One stretch of microphone audio: an AVCaptureSession on the chosen input, written to an AAC file
/// until `finish()`. The mic is only open (and the menu bar's orange dot only shows) while this runs.
final class MicrophoneCapture: NSObject, @unchecked Sendable {
    let url: URL

    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "snip.capture.microphone", qos: .userInitiated)

    // Only touched on `queue`.
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var firstSampleTime: CMTime?
    private var stopped = false

    /// `deviceID` is an `AVCaptureDevice.uniqueID`; nil, or a device that isn't connected, is the default input.
    init(deviceID: String?, url: URL) throws {
        self.url = url
        super.init()
        let chosen = deviceID.flatMap { AVCaptureDevice(uniqueID: $0) }
        guard let device = chosen ?? AVCaptureDevice.default(for: .audio) else {
            throw SnipCaptureError.microphoneFailed("no microphone is connected")
        }
        let deviceInput: AVCaptureDeviceInput
        do {
            deviceInput = try AVCaptureDeviceInput(device: device)
        } catch {
            throw SnipCaptureError.microphoneFailed(error.localizedDescription)
        }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canAddInput(deviceInput), session.canAddOutput(output) else {
            throw SnipCaptureError.microphoneFailed("\(device.localizedName) can't be recorded")
        }
        session.addInput(deviceInput)
        session.addOutput(output)
        output.setSampleBufferDelegate(self, queue: queue)
    }

    /// Opens the microphone. Blocks until the session runs, so don't call it on the main thread.
    func start() {
        session.startRunning()
    }

    /// Closes the microphone and finishes the file. Returns the host time of the file's first sample,
    /// or nil (and no file) if nothing was recorded.
    func finish() async -> CMTime? {
        session.stopRunning()
        let written: (AVAssetWriter, CMTime)? = queue.sync { () -> (AVAssetWriter, CMTime)? in
            stopped = true
            input?.markAsFinished()
            guard let writer = self.writer, let firstSampleTime else { return nil }
            return (writer, firstSampleTime)
        }
        guard let written else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        let (writer, start) = written
        await writer.finishWriting()
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return start
    }

    /// The writer, made from the first sample's format: AAC at 48 kHz, mono or stereo like the input.
    private func makeWriter(for sampleBuffer: CMSampleBuffer) -> (AVAssetWriter, AVAssetWriterInput)? {
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee
        else { return nil }
        let channels = description.mChannelsPerFrame >= 2 ? 2 : 1
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = channels == 2 ? kAudioChannelLayoutTag_Stereo : kAudioChannelLayoutTag_Mono
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: channels == 2 ? 192_000 : 128_000,
            AVChannelLayoutKey: Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size),
        ]
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .m4a) else { return nil }
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings, sourceFormatHint: format)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { return nil }
        writer.add(input)
        guard writer.startWriting() else { return nil }
        return (writer, input)
    }

    /// `time` on the host clock, the clock ScreenCaptureKit stamps frames with.
    private func hostTime(_ time: CMTime) -> CMTime {
        guard let clock = session.synchronizationClock else { return time }
        return CMSyncConvertTime(time, from: clock, to: CMClockGetHostTimeClock())
    }
}

extension MicrophoneCapture: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !stopped else { return }
        if writer == nil {
            guard let made = makeWriter(for: sampleBuffer) else { return }
            let (writer, input) = made
            let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startSession(atSourceTime: time)
            self.writer = writer
            self.input = input
            firstSampleTime = hostTime(time)
        }
        guard let input, input.isReadyForMoreMediaData else { return }
        input.append(sampleBuffer)
    }
}

/// The microphone spans of one recording. Turning the mic on starts a new span in its own file;
/// turning it off finishes that file.
actor MicrophoneSpans {
    private let baseURL: URL
    private var current: MicrophoneCapture?
    private var finished: [(url: URL, start: CMTime)] = []
    private var count = 0

    /// Span files are named after `movieURL`: recording-<id>-mic-1.m4a, -mic-2.m4a and so on.
    init(movieURL: URL) {
        baseURL = movieURL.deletingPathExtension()
    }

    func turnOn(deviceID: String?) throws {
        guard current == nil else { return }
        count += 1
        let url = URL(fileURLWithPath: baseURL.path + "-mic-\(count)").appendingPathExtension("m4a")
        let capture = try MicrophoneCapture(deviceID: deviceID, url: url)
        capture.start()
        current = capture
    }

    func turnOff() async {
        guard let capture = current else { return }
        // Cleared before waiting, so turning the mic back on meanwhile starts a new span.
        current = nil
        if let start = await capture.finish() {
            finished.append((capture.url, start))
        }
    }

    /// Turns the mic off and returns every span, placed relative to `movieStart` (host time of the
    /// first frame; nil, if no frame time was seen, starts the movie with the first span).
    func finish(movieStart: CMTime?) async -> [MicrophoneSpan] {
        await turnOff()
        guard let movieStart = movieStart ?? finished.first?.start else { return [] }
        return finished.map { span in
            MicrophoneSpan(url: span.url, offset: CMTimeSubtract(span.start, movieStart).seconds)
        }
    }

    /// Turns the mic off and deletes every span.
    func discard() async {
        await turnOff()
        for span in finished {
            try? FileManager.default.removeItem(at: span.url)
        }
        finished = []
    }
}
