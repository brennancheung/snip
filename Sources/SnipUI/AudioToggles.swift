import AppKit
import SnipCore

/// The microphone and system audio icons in the selection bar and the recording pill. Each shows
/// the saved setting and flips it on click, also mid-recording (AppController passes it on to the
/// recorder); off is the slashed glyph, dimmed.
@MainActor
final class AudioToggles: NSStackView {
    private let microphone: IconToggle
    private let systemAudio: IconToggle

    /// `scale`: the interface size of the bar or pill they sit in.
    init(scale: UIScale) {
        microphone = IconToggle(on: "mic.fill", off: "mic.slash.fill", name: "Microphone", scale: scale)
        systemAudio = IconToggle(on: "speaker.wave.2.fill", off: "speaker.slash.fill", name: "System audio", scale: scale)
        super.init(frame: .zero)
        setViews([microphone, systemAudio], in: .leading)
        spacing = scale.metric(2)

        microphone.target = self
        microphone.action = #selector(microphoneClicked)
        systemAudio.target = self
        systemAudio.action = #selector(systemAudioClicked)

        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: SettingsStore.didChange, object: nil)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func refresh() {
        let settings = SettingsStore.shared.settings
        microphone.show(on: settings.recordMicrophone)
        systemAudio.show(on: settings.recordSystemAudio)
    }

    @objc private func settingsChanged() { refresh() }
    @objc private func microphoneClicked() { Microphone.toggle() }
    @objc private func systemAudioClicked() { SettingsStore.shared.settings.recordSystemAudio.toggle() }
}

/// A borderless symbol button with an on and an off glyph, the same width either way.
private final class IconToggle: NSButton {
    private let onImage: NSImage?
    private let offImage: NSImage?

    init(on: String, off: String, name: String, scale: UIScale) {
        onImage = NSImage(systemSymbolName: on, accessibilityDescription: name)
        offImage = NSImage(systemSymbolName: off, accessibilityDescription: name)
        super.init(frame: .zero)
        isBordered = false
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        symbolConfiguration = .init(pointSize: scale.metric(12), weight: .regular)
        toolTip = name
        setAccessibilityLabel(name)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: scale.metric(22)).isActive = true
        heightAnchor.constraint(equalToConstant: scale.metric(20)).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(on: Bool) {
        image = on ? onImage : offImage
        contentTintColor = on ? .labelColor : .tertiaryLabelColor
        setAccessibilityValue(on ? "on" : "off")
    }

    // Works on the first click even when its panel isn't key (the bar's overlay, the pill never is).
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
