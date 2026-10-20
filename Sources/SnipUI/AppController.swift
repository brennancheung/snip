import AppKit
import SnipCapture
import SnipCore

/// Owns the app's state machine: idle → selecting → countingDown → recording → encoding → finished.
@MainActor
public final class AppController: NSObject, NSApplicationDelegate {
    private var state: RecorderState = .idle {
        didSet { statusItem?.update(state) }
    }

    private var statusItem: StatusItemController?
    private var settingsWindow: SettingsWindowController?
    private let notification = SavedNotification()
    private var hotKey: HotKey?

    /// The last area recorded, for Record Last Area.
    private var lastTarget: CaptureTarget?

    // The current recording.
    private var recorder: ScreenRecorder?
    private var countdown: CountdownPanel?
    private var border: RecordingBorder?
    private var pill: RecordingPill?
    private var ticker: Timer?
    /// Whether the current recording has the microphone on; it follows the setting.
    private var microphoneOn = false

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let statusItem = StatusItemController()
        statusItem.onNewRecording = { [weak self] in self?.newRecording() }
        statusItem.onRecordLastArea = { [weak self] in self?.recordLastArea() }
        statusItem.onSettings = { [weak self] in self?.showSettings() }
        statusItem.onStop = { [weak self] in self?.stop() }
        statusItem.hasLastArea = { [weak self] in self?.lastTarget != nil }
        self.statusItem = statusItem

        self.notification.setUp()
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: SettingsStore.didChange, object: nil)
        applyHotKey(SettingsStore.shared.hotKey)
        // Older builds asked only once and remembered it here.
        UserDefaults.standard.removeObject(forKey: "askedForScreenRecording")
        requestScreenRecordingIfMissing()
    }

    // MARK: Hotkey

    /// Registers `spec` as the global shortcut. If it can't, keeps the old one and returns why.
    @discardableResult
    private func applyHotKey(_ spec: HotKeySpec) -> String? {
        hotKey?.unregister()
        do {
            hotKey = try HotKey(keyCode: spec.keyCode, carbonModifiers: spec.carbonModifiers) { [weak self] in
                self?.hotKeyPressed()
            }
            return nil
        } catch {
            let current = SettingsStore.shared.hotKey
            hotKey = try? HotKey(keyCode: current.keyCode, carbonModifiers: current.carbonModifiers) { [weak self] in
                self?.hotKeyPressed()
            }
            return (error as? HotKey.RegistrationError)?.description ?? error.localizedDescription
        }
    }

    /// While the Settings shortcut field waits for keys, the old shortcut must not fire.
    private func pauseHotKey(_ paused: Bool) {
        if paused {
            hotKey?.unregister()
            hotKey = nil
        } else if hotKey == nil {
            applyHotKey(SettingsStore.shared.hotKey)
        }
    }

    private func hotKeyPressed() {
        switch state {
        case .idle: newRecording()
        case .countingDown: countdown?.cancel()
        case .recording: stop()
        default: break  // selecting, encoding: nothing
        }
    }

    // MARK: Flow

    private func newRecording() {
        guard state == .idle else { return }
        guard hasScreenRecordingPermission() else { return }
        state = .selecting
        Task {
            let overlay = SelectionOverlay()
            guard let target = await overlay.choose() else {
                state = .idle
                return
            }
            await record(target)
        }
    }

    private func recordLastArea() {
        guard state == .idle, let target = lastTarget else { return }
        guard hasScreenRecordingPermission() else { return }
        Task { await record(target) }
    }

    private func record(_ target: CaptureTarget) async {
        lastTarget = target
        guard let area = ScreenGeometry.appKitRect(for: target) else {
            fail("That window is no longer open.")
            return
        }
        let countdownSeconds = SettingsStore.shared.settings.countdownSeconds
        // Out of idle at once, so the menu can't start a second recording while this one starts.
        state = .countingDown(remaining: countdownSeconds)

        if countdownSeconds > 0 {
            let panel = CountdownPanel(centredOn: area)
            countdown = panel
            let finished = await panel.run(seconds: countdownSeconds) { remaining in
                state = .countingDown(remaining: remaining)
            }
            countdown = nil
            guard finished else {
                state = .idle
                return
            }
        }

        // Read after the countdown: the audio may have been switched meanwhile.
        var settings = SettingsStore.shared.settings
        // A chosen microphone that was unplugged records the default input instead.
        settings.microphoneDeviceID = Microphone.available(settings.microphoneDeviceID)

        let recorder = SCKRecorder()
        // The window closed or sharing was stopped from the system menu: keep what was recorded.
        recorder.onUnexpectedStop = { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
        self.recorder = recorder
        do {
            try await recorder.start(target: target, settings: settings, intermediateURL: OutputNaming.intermediateURL())
        } catch {
            self.recorder = nil
            fail(error.localizedDescription)
            return
        }

        let startedAt = Date()
        microphoneOn = settings.recordMicrophone
        state = .recording(startedAt: startedAt)
        // In case the microphone was switched while the capture started.
        settingsChanged()

        let border = RecordingBorder(target: target, area: area)
        let pill = RecordingPill(systemAudio: settings.recordSystemAudio)
        pill.onStop = { [weak self] in self?.stop() }
        pill.onDiscard = { [weak self] in self?.discard() }
        border.onAreaChange = { [weak pill] area in pill?.follow(area, target: target) }
        border.show()
        pill.show(near: area, target: target)
        self.border = border
        self.pill = pill

        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    /// While recording, the microphone follows its setting: the pill's icon, the menu or Settings.
    @objc private func settingsChanged() {
        guard case .recording = state, let recorder else { return }
        let settings = SettingsStore.shared.settings
        guard settings.recordMicrophone != microphoneOn else { return }
        let on = settings.recordMicrophone
        microphoneOn = on
        let deviceID = Microphone.available(settings.microphoneDeviceID)
        Task {
            do {
                try await recorder.setMicrophone(on, deviceID: deviceID)
            } catch {
                guard case .recording = state, on else { return }
                // The mic couldn't open: show it as off again.
                NSSound.beep()
                microphoneOn = false
                SettingsStore.shared.settings.recordMicrophone = false
            }
        }
    }

    private func tick() {
        guard case .recording(let startedAt) = state else { return }
        let elapsed = Int(Date().timeIntervalSince(startedAt))
        pill?.setElapsed(elapsed)
    }

    private func stop() {
        guard case .recording(let startedAt) = state, let recorder else { return }
        endRecordingChrome(keepPill: true)
        pill?.showCompressing()
        state = .encoding(progress: 0)

        Task {
            do {
                let media = try await recorder.stop()
                self.recorder = nil
                let (output, note) = try await encode(media, startedAt: startedAt)
                finish(output, note: note)
            } catch {
                self.recorder = nil
                fail(error.localizedDescription)
            }
        }
    }

    private func discard() {
        guard case .recording = state, let recorder else { return }
        endRecordingChrome(keepPill: false)
        self.recorder = nil
        state = .idle
        Task { await recorder.cancel() }
    }

    /// Encodes to the output folder, creating it if it is missing. Without ffmpeg, or if it
    /// fails, keeps the uncompressed recording (without the microphone) instead and returns a note saying so.
    private func encode(_ media: RecordedMedia, startedAt: Date) async throws -> (URL, String?) {
        let intermediate = media.movie
        let settings = SettingsStore.shared.settings
        let output = OutputNaming.outputURL(in: try settings.createOutputDirectory(), date: startedAt, ext: "mp4")
        let note: String
        do {
            try await FFmpegEncoder().encode(
                intermediate: intermediate, microphone: media.microphone, to: output, settings: settings
            ) { [weak self] progress in
                Task { @MainActor in self?.encodingProgress(progress) }
            }
            media.remove()
            return (output, nil)
        } catch EncodeError.ffmpegMissing {
            note = "Not compressed: ffmpeg not found (brew install ffmpeg)."
        } catch {
            note = "Not compressed: ffmpeg failed."
        }
        // Moves the intermediate into the output folder as a .mov.
        let fallback = try FFmpegEncoder.fallbackCopy(intermediate: intermediate, to: output)
        for span in media.microphone { try? FileManager.default.removeItem(at: span.url) }
        return (fallback, note)
    }

    private func encodingProgress(_ progress: Double) {
        guard case .encoding = state else { return }
        state = .encoding(progress: progress)
        pill?.setProgress(progress)
    }

    private func finish(_ output: URL, note: String?) {
        pill?.close()
        pill = nil
        state = .finished(output: output)

        if SettingsStore.shared.settings.copyToClipboard {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([output as NSURL])
        }
        RecentRecordings().add(url: output)
        notification.post(file: output, note: note)
        state = .idle
    }

    private func fail(_ message: String) {
        endRecordingChrome(keepPill: false)
        countdown?.cancel()
        countdown = nil
        state = .failed(message: message)

        let alert = NSAlert()
        alert.messageText = "Snip couldn’t record"
        alert.informativeText = message
        NSApp.activate()
        alert.runModal()
        state = .idle
    }

    /// Takes down the border and timer (and the pill unless it is about to show progress).
    private func endRecordingChrome(keepPill: Bool) {
        ticker?.invalidate()
        ticker = nil
        border?.close()
        border = nil
        if !keepPill {
            pill?.close()
            pill = nil
        }
    }

    // MARK: Settings

    private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(
                applyHotKey: { [weak self] spec in self?.applyHotKey(spec) },
                pauseHotKey: { [weak self] paused in self?.pauseHotKey(paused) }
            )
        }
        settingsWindow?.show()
    }

    // MARK: Screen Recording permission

    /// Without permission, asks for it. That adds Snip to the Screen Recording list in System
    /// Settings (again, after a permission reset); macOS itself limits how often its prompt shows.
    private func requestScreenRecordingIfMissing() {
        guard !CGPreflightScreenCaptureAccess() else { return }
        CGRequestScreenCaptureAccess()
    }

    /// Without permission, asks for it, explains in one line where to turn it on and returns false.
    private func hasScreenRecordingPermission() -> Bool {
        guard !CGPreflightScreenCaptureAccess() else { return true }
        requestScreenRecordingIfMissing()
        let alert = NSAlert()
        alert.messageText = "Snip needs Screen Recording permission"
        alert.informativeText = "Turn on Snip in System Settings › Privacy & Security › Screen & System Audio Recording, then reopen Snip."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        return false
    }
}
