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
            // Redrawn either way: turning on waits for microphone access and may not happen.
            objectWillChange.send()
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
    /// Draws at this interface size instead of the saved one (UIPreviews).
    var scaleOverride: UIScale? = nil

    var body: some View {
        // Every size here is a macOS default (13 pt body, 11 pt small) times the interface size.
        let ui = scaleOverride ?? UIScale(settings: model.settings)
        Form {
            // Group applies the row padding to each row.
            Group {
                row("Interface size", ui) {
                    PopUpControl(selection: $model.settings.interfaceScale, options: interfaceSizeOptions, scale: ui)
                }

                row(ui) {
                    HStack(spacing: ui.metric(8)) {
                        Text("Sharper").font(ui.text(11)).foregroundStyle(.secondary)
                        ScaledSlider(value: crf, range: 18...32, step: 1, scale: ui)
                        Text("Smaller").font(ui.text(11)).foregroundStyle(.secondary)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: ui.metric(2)) {
                        Text("Quality")
                        Text("CRF \(model.settings.crf)")
                            .font(ui.text(11))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                row("Frame rate", ui) {
                    SegmentedControl(selection: $model.settings.fps, options: [("30", 30), ("60", 60)], scale: ui)
                }

                row("Resolution", ui) {
                    SegmentedControl(
                        selection: $model.settings.scale,
                        options: [("Full", RecordingSettings.Scale.full), ("Half", RecordingSettings.Scale.half)],
                        scale: ui
                    )
                }

                Toggle("Show cursor", isOn: $model.settings.showCursor)
                    .toggleStyle(CentredSwitchStyle(scale: ui))

                row("Microphone", ui) {
                    PopUpControl(selection: $model.microphone, options: microphoneOptions, scale: ui)
                }

                Toggle("System audio", isOn: $model.settings.recordSystemAudio)
                    .toggleStyle(CentredSwitchStyle(scale: ui))

                row("Countdown", ui) {
                    SegmentedControl(
                        selection: $model.settings.countdownSeconds,
                        options: [("Off", 0), ("3 s", 3), ("5 s", 5)],
                        scale: ui
                    )
                }

                row("Save to", ui) {
                    HStack(spacing: ui.metric(8)) {
                        Text(model.folderPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .help(model.settings.resolvedOutputDirectory.path)
                        PushButton(title: "Change…", scale: ui) { model.chooseFolder() }
                        PushButton(title: "Show", scale: ui) { model.showFolder() }
                            .help("Show the folder in Finder")
                    }
                }

                Toggle("Copy to clipboard when done", isOn: $model.settings.copyToClipboard)
                    .toggleStyle(CentredSwitchStyle(scale: ui))

                row("Shortcut", ui) {
                    ShortcutField(
                        hotKey: model.hotKey,
                        scale: ui,
                        onRecordingChange: { model.pauseHotKey($0) },
                        onChange: { model.setHotKey($0) }
                    )
                    .fixedSize()
                }

                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                .toggleStyle(CentredSwitchStyle(scale: ui))
            }
            .padding(.vertical, ui.metric(4))
        }
        .formStyle(.grouped)
        .font(ui.text(13))
        .contentMargins(.horizontal, ui.metric(20), for: .scrollContent)
        .contentMargins(.vertical, ui.metric(16), for: .scrollContent)
        // The window follows this size, so changing Interface size resizes it at once.
        .frame(width: ui.metric(460))
        .fixedSize(horizontal: false, vertical: true)
    }

    /// A labelled row with the label vertically centred on its control.
    private func row<Content: View>(_ title: String, _ ui: UIScale, @ViewBuilder content: () -> Content) -> some View {
        LabeledContent(title, content: content)
            .labeledContentStyle(CentredRowStyle(scale: ui))
    }

    private func row<Content: View, Label: View>(
        _ ui: UIScale,
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) -> some View {
        LabeledContent(content: content, label: label)
            .labeledContentStyle(CentredRowStyle(scale: ui))
    }

    /// Automatic, showing what it is on this display, then each size.
    private var interfaceSizeOptions: [(label: String, value: Double?)] {
        let automatic = (label: "Automatic (\(UIScale.percent(UIScale.automaticFactor)))", value: Double?.none)
        return [automatic] + RecordingSettings.interfaceScaleChoices.map { (label: UIScale.percent($0), value: Optional($0)) }
    }

    /// Off, then each input by its id.
    private var microphoneOptions: [(label: String, value: String?)] {
        [(label: "Off", value: nil)] + model.microphones.map { (label: $0.name, value: Optional($0.id)) }
    }

    private var crf: Binding<Double> {
        Binding(
            get: { Double(model.settings.crf) },
            set: { model.settings.crf = Int($0.rounded()) }
        )
    }
}
