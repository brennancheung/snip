import AppKit
import SnipCapture
import SnipCore

/// Owns the app's state machine: idle → selecting → countingDown → recording → encoding → finished.
/// A screenshot goes idle → selecting → idle.
@MainActor
public final class AppController: NSObject, NSApplicationDelegate {
    private var state: RecorderState = .idle {
        didSet { statusItem?.update(state) }
    }

    private var statusItem: StatusItemController?
    private var settingsWindow: SettingsWindowController?
    private var hotKeys: [Shortcut: HotKey] = [:]
    /// Why a saved shortcut couldn't be registered (another app holds it), for Settings to show.
    private(set) var hotKeyProblems: [Shortcut: String] = [:]

    /// The last area recorded, for Record Last Area.
    private var lastTarget: CaptureTarget?

    // The current recording.
    private var recorder: ScreenRecorder?
    private var countdown: CountdownPanel?
    private var border: RecordingBorder?
    private var pill: RecordingPill?
    private var ticker: Timer?
    /// The finished recording's panel, until it is closed or the next recording starts.
    private var donePanel: DonePanel?
    /// Whether the current recording has the microphone on; it follows the setting.
    private var microphoneOn = false

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let statusItem = StatusItemController()
        statusItem.onNewRecording = { [weak self] in self?.newRecording() }
        statusItem.onRecordLastArea = { [weak self] in self?.recordLastArea() }
        statusItem.onAreaImage = { [weak self] in self?.newScreenshot(.areaImage) }
        statusItem.onWindowImage = { [weak self] in self?.newScreenshot(.windowImage) }
        statusItem.onSettings = { [weak self] in self?.showSettings() }
        statusItem.onStop = { [weak self] in self?.stop() }
        statusItem.hasLastArea = { [weak self] in self?.lastTarget != nil }
        self.statusItem = statusItem

        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: SettingsStore.didChange, object: nil)
        registerSavedHotKeys()
        // Older builds asked only once and remembered it here.
        UserDefaults.standard.removeObject(forKey: "askedForScreenRecording")
        requestScreenRecordingIfMissing()
    }

    // MARK: Hotkeys

    /// Registers every saved shortcut. One another app holds is left off, noted in `hotKeyProblems`.
    private func registerSavedHotKeys() {
        for shortcut in Shortcut.allCases {
            hotKeys[shortcut]?.unregister()
            hotKeys[shortcut] = nil
            hotKeyProblems[shortcut] = nil
            guard let spec = SettingsStore.shared.hotKey(for: shortcut) else { continue }
            do {
                hotKeys[shortcut] = try register(spec, for: shortcut)
            } catch {
                hotKeyProblems[shortcut] = Self.describe(error)
                NSLog("Snip: \(shortcut.title) shortcut not registered: \(Self.describe(error))")
            }
        }
    }

    /// Registers `spec` for `shortcut` (nil removes it) and saves it. If it can't, keeps the old
    /// one and returns why.
    @discardableResult
    private func applyHotKey(_ spec: HotKeySpec?, for shortcut: Shortcut) -> String? {
        if let spec, let other = Shortcut.allCases.first(where: { $0 != shortcut && SettingsStore.shared.hotKey(for: $0) == spec }) {
            return "Snip already uses it for \(other.title)."
        }
        hotKeys[shortcut]?.unregister()
        hotKeys[shortcut] = nil
        if let spec {
            do {
                hotKeys[shortcut] = try register(spec, for: shortcut)
            } catch {
                if let current = SettingsStore.shared.hotKey(for: shortcut) {
                    hotKeys[shortcut] = try? register(current, for: shortcut)
                }
                return Self.describe(error)
            }
        }
        hotKeyProblems[shortcut] = nil
        SettingsStore.shared.setHotKey(spec, for: shortcut)
        return nil
    }

    private func register(_ spec: HotKeySpec, for shortcut: Shortcut) throws -> HotKey {
        try HotKey(keyCode: spec.keyCode, carbonModifiers: spec.carbonModifiers) { [weak self] in
            self?.hotKeyPressed(shortcut)
        }
    }

    private static func describe(_ error: Error) -> String {
        (error as? HotKey.RegistrationError)?.description ?? error.localizedDescription
    }

    /// While a Settings shortcut field waits for keys, none of Snip's shortcuts may fire.
    private func pauseHotKeys(_ paused: Bool) {
        if paused {
            for hotKey in hotKeys.values { hotKey.unregister() }
            hotKeys = [:]
        } else if hotKeys.isEmpty {
            registerSavedHotKeys()
        }
    }

    private func hotKeyPressed(_ shortcut: Shortcut) {
        switch shortcut {
        case .record:
            switch state {
            case .idle: newRecording()
            case .countingDown: countdown?.cancel()
            case .recording: stop()
            default: break  // selecting, encoding: nothing
            }
        case .areaImage: newScreenshot(.areaImage)
        case .windowImage: newScreenshot(.windowImage)
        }
    }

    // MARK: Flow

    private func newRecording() {
        guard state == .idle else { return }
        guard hasScreenRecordingPermission() else { return }
        donePanel?.close()
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

    /// Picks a box or a window, saves a PNG of it to the output folder, and shows it in the panel.
    private func newScreenshot(_ purpose: SelectionOverlay.Purpose) {
        guard state == .idle else { return }
        guard hasScreenRecordingPermission() else { return }
        donePanel?.close()
        state = .selecting
        Task {
            guard let target = await SelectionOverlay(purpose: purpose).choose() else {
                state = .idle
                return
            }
            let area = ScreenGeometry.appKitRect(for: target)
            do {
                let picture = try await Screenshot.capture(target)
                let folder = try SettingsStore.shared.settings.createOutputDirectory()
                let output = OutputNaming.outputURL(in: folder, ext: "png")
                try Screenshot.writePNG(picture, to: output)
                state = .idle
                if SettingsStore.shared.settings.copyToClipboard { Pasteboard.copy(file: output) }
                RecentRecordings().add(url: output)
                showDonePanel(output, note: nil, near: area, target: target)
            } catch {
                fail(error.localizedDescription, title: "Snip couldn’t take the screenshot")
            }
        }
    }

    private func recordLastArea() {
        guard state == .idle, let target = lastTarget else { return }
        guard hasScreenRecordingPermission() else { return }
        donePanel?.close()
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
        let pill = RecordingPill()
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

    /// While recording, the microphone and system audio follow their settings: the pill's icons,
    /// the menu or Settings.
    @objc private func settingsChanged() {
        guard case .recording = state, let recorder else { return }
        let settings = SettingsStore.shared.settings
        recorder.setSystemAudio(settings.recordSystemAudio)
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
    /// fails, keeps the uncompressed recording (without the microphone, and without system audio if
    /// it was off for any of it) instead and returns a note saying so.
    private func encode(_ media: RecordedMedia, startedAt: Date) async throws -> (URL, String?) {
        let intermediate = media.movie
        let settings = SettingsStore.shared.settings
        let output = OutputNaming.outputURL(in: try settings.createOutputDirectory(), date: startedAt, ext: "mp4")
        let note: String
        do {
            try await FFmpegEncoder().encode(media, to: output, settings: settings) { [weak self] progress in
                Task { @MainActor in self?.encodingProgress(progress) }
            }
            media.remove()
            return (output, nil)
        } catch EncodeError.ffmpegMissing {
            note = "Not compressed: ffmpeg not found (brew install ffmpeg)."
        } catch {
            note = "Not compressed: ffmpeg failed."
        }
        if !media.systemAudioOff.isEmpty {
            try await MovieAudio.removeAudio(from: intermediate)
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

        if SettingsStore.shared.settings.copyToClipboard { Pasteboard.copy(file: output) }
        RecentRecordings().add(url: output)
        showDonePanel(output, note: note, near: lastTarget.flatMap(ScreenGeometry.appKitRect(for:)), target: lastTarget)
        state = .idle
    }

    /// Beside the captured area (where the pill was, for a recording).
    private func showDonePanel(_ output: URL, note: String?, near area: CGRect?, target: CaptureTarget?) {
        let panel = DonePanel(file: output, note: note)
        panel.onClose = { [weak self, weak panel] in
            if self?.donePanel === panel { self?.donePanel = nil }
        }
        donePanel = panel
        panel.show(near: area, target: target)
    }

    private func fail(_ message: String, title: String = "Snip couldn’t record") {
        endRecordingChrome(keepPill: false)
        countdown?.cancel()
        countdown = nil
        state = .failed(message: message)

        let alert = NSAlert()
        alert.messageText = title
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
                applyHotKey: { [weak self] spec, shortcut in self?.applyHotKey(spec, for: shortcut) },
                pauseHotKeys: { [weak self] paused in self?.pauseHotKeys(paused) },
                hotKeyProblem: { [weak self] shortcut in self?.hotKeyProblems[shortcut] }
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
