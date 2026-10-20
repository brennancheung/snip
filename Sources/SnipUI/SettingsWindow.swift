import AppKit
import ServiceManagement
import SnipCore
import SwiftUI

/// The Settings window: one pane, saved through SettingsStore as each control changes.
@MainActor
final class SettingsWindowController {
    private let model: SettingsModel
    private var window: NSWindow?

    /// `applyHotKey` registers the new shortcut and returns why if it can't be used.
    /// `pauseHotKey` is called with true while the shortcut field waits for keys.
    init(applyHotKey: @escaping (HotKeySpec) -> String?, pauseHotKey: @escaping (Bool) -> Void) {
        model = SettingsModel(applyHotKey: applyHotKey, pauseHotKey: pauseHotKey)
    }

    func show() {
        model.reload()
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(model: model))
            hosting.sizingOptions = .preferredContentSize
            let window = NSWindow(contentViewController: hosting)
            window.title = "Snip Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class SettingsModel: ObservableObject {
    @Published var settings: RecordingSettings {
        didSet { if settings != oldValue { SettingsStore.shared.settings = settings } }
    }
    @Published private(set) var hotKey: HotKeySpec
    @Published var launchAtLogin: Bool
    @Published private(set) var microphones: [Microphone.Input] = []

    private let applyHotKey: (HotKeySpec) -> String?
    let pauseHotKey: (Bool) -> Void
    private var settingsObserver: NSObjectProtocol?

    init(applyHotKey: @escaping (HotKeySpec) -> String?, pauseHotKey: @escaping (Bool) -> Void) {
        self.applyHotKey = applyHotKey
        self.pauseHotKey = pauseHotKey
        settings = SettingsStore.shared.settings
        hotKey = SettingsStore.shared.hotKey
        launchAtLogin = SMAppService.mainApp.status == .enabled
        // The menu's Microphone and System Audio items change settings while this window is open.
        settingsObserver = NotificationCenter.default.addObserver(forName: SettingsStore.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.settings != SettingsStore.shared.settings else { return }
                self.settings = SettingsStore.shared.settings
            }
        }
    }

    func reload() {
        settings = SettingsStore.shared.settings
        hotKey = SettingsStore.shared.hotKey
        launchAtLogin = SMAppService.mainApp.status == .enabled
        microphones = Microphone.inputs()
    }

    /// The chosen input's id, or nil for Off. On with no choice shows the default input.
    var microphone: String? {
        get {
            guard settings.recordMicrophone else { return nil }
            let chosen = microphones.first { $0.id == settings.microphoneDeviceID }
            return (chosen ?? microphones.first)?.id
        }
        set {
            if let newValue { Microphone.turnOn(deviceID: newValue) } else { Microphone.turnOff() }
        }
    }

    func setHotKey(_ spec: HotKeySpec) {
        if let problem = applyHotKey(spec) {
            let alert = NSAlert()
            alert.messageText = "Snip can’t use \(KeyCombo.display(keyCode: spec.keyCode, carbonModifiers: spec.carbonModifiers))"
            alert.informativeText = problem
            alert.runModal()
            return
        }
        hotKey = spec
        SettingsStore.shared.hotKey = spec
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSSound.beep()
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// The output folder's path with ~ for the home folder, e.g. ~/Movies/snip.
    var folderPath: String {
        (settings.resolvedOutputDirectory.path as NSString).abbreviatingWithTildeInPath
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.resolvedOutputDirectory
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.setOutputDirectory(url)
    }

    /// Selects the output folder in Finder, creating it first if it is missing.
    func showFolder() {
        do {
            let folder = try settings.createOutputDirectory()
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        } catch {
            let alert = NSAlert()
            alert.messageText = "Snip can’t create \(folderPath)"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    /// Large on purpose: the default 13 pt is hard to read on a very high-resolution monitor.
    private static let bodySize: CGFloat = 17
    private static let secondarySize: CGFloat = 14

    var body: some View {
        Form {
            // Group applies the row padding to each row.
            Group {
                Slider(value: crf, in: 18...32, step: 1) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Quality")
                        Text("CRF \(model.settings.crf)")
                            .font(.system(size: Self.secondarySize))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                } minimumValueLabel: {
                    Text("Sharper")
                } maximumValueLabel: {
                    Text("Smaller")
                }

                Picker("Frame rate", selection: $model.settings.fps) {
                    Text("30").tag(30)
                    Text("60").tag(60)
                }
                .pickerStyle(.segmented)

                Picker("Resolution", selection: $model.settings.scale) {
                    Text("Full").tag(RecordingSettings.Scale.full)
                    Text("Half").tag(RecordingSettings.Scale.half)
                }
                .pickerStyle(.segmented)

                Toggle("Show cursor", isOn: $model.settings.showCursor)

                Picker("Microphone", selection: $model.microphone) {
                    Text("Off").tag(String?.none)
                    ForEach(model.microphones) { input in
                        Text(input.name).tag(String?.some(input.id))
                    }
                }

                Toggle("System audio", isOn: $model.settings.recordSystemAudio)

                Picker("Countdown", selection: $model.settings.countdownSeconds) {
                    Text("Off").tag(0)
                    Text("3 s").tag(3)
                    Text("5 s").tag(5)
                }
                .pickerStyle(.segmented)

                LabeledContent("Save to") {
                    HStack(spacing: 8) {
                        Text(model.folderPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .help(model.settings.resolvedOutputDirectory.path)
                        Button("Change…") { model.chooseFolder() }
                            .fixedSize()
                        Button("Show") { model.showFolder() }
                            .fixedSize()
                            .help("Show the folder in Finder")
                    }
                }

                Toggle("Copy to clipboard when done", isOn: $model.settings.copyToClipboard)

                LabeledContent("Shortcut") {
                    ShortcutField(
                        hotKey: model.hotKey,
                        fontSize: Self.bodySize,
                        onRecordingChange: { model.pauseHotKey($0) },
                        onChange: { model.setHotKey($0) }
                    )
                    .fixedSize()
                }

                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
            }
            .padding(.vertical, 5)
        }
        .formStyle(.grouped)
        .font(.system(size: Self.bodySize))
        .controlSize(.large)
        .contentMargins(.horizontal, 28, for: .scrollContent)
        .contentMargins(.vertical, 24, for: .scrollContent)
        .frame(width: 620)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var crf: Binding<Double> {
        Binding(
            get: { Double(model.settings.crf) },
            set: { model.settings.crf = Int($0.rounded()) }
        )
    }
}
