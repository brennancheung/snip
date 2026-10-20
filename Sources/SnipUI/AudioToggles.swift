import AppKit
import SnipCore

/// The microphone and system audio icons in the selection bar and the recording pill. Each shows
/// the saved setting and flips it on click; off is the slashed glyph, dimmed.
@MainActor
final class AudioToggles: NSStackView {
    private let microphone = IconToggle(on: "mic.fill", off: "mic.slash.fill", name: "Microphone")
    private let systemAudio = IconToggle(on: "speaker.wave.2.fill", off: "speaker.slash.fill", name: "System audio")
    private let recordingSystemAudio: Bool?

    /// `recordingSystemAudio`: while recording, whether system audio is being recorded. It can't
    /// change mid-recording, so that icon then shows it and isn't clickable. nil before recording.
    init(recordingSystemAudio: Bool? = nil) {
        self.recordingSystemAudio = recordingSystemAudio
        super.init(frame: .zero)
        setViews([microphone, systemAudio], in: .leading)
        spacing = 2

        microphone.target = self
        microphone.action = #selector(microphoneClicked)
        if recordingSystemAudio == nil {
            systemAudio.target = self
            systemAudio.action = #selector(systemAudioClicked)
        } else {
            systemAudio.isClickable = false
            systemAudio.toolTip = "System audio can be changed before recording"
        }

        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: SettingsStore.didChange, object: nil)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func refresh() {
        let settings = SettingsStore.shared.settings
        microphone.show(on: settings.recordMicrophone)
        systemAudio.show(on: recordingSystemAudio ?? settings.recordSystemAudio)
    }

    @objc private func settingsChanged() { refresh() }
    @objc private func microphoneClicked() { Microphone.toggle() }
    @objc private func systemAudioClicked() { SettingsStore.shared.settings.recordSystemAudio.toggle() }
}

/// A borderless symbol button with an on and an off glyph, the same width either way.
private final class IconToggle: NSButton {
    var isClickable = true
    private let onImage: NSImage?
    private let offImage: NSImage?

    init(on: String, off: String, name: String) {
        onImage = NSImage(systemSymbolName: on, accessibilityDescription: name)
        offImage = NSImage(systemSymbolName: off, accessibilityDescription: name)
        super.init(frame: .zero)
        isBordered = false
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        symbolConfiguration = .init(pointSize: 12, weight: .regular)
        toolTip = name
        setAccessibilityLabel(name)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 22).isActive = true
        heightAnchor.constraint(equalToConstant: 20).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(on: Bool) {
        image = on ? onImage : offImage
        contentTintColor = on ? .labelColor : .tertiaryLabelColor
        setAccessibilityValue(on ? "on" : "off")
    }

    // Works on the first click even when its panel isn't key (the bar's overlay, the pill never is).
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Not clickable: clicks go to what is behind, so the pill can still be dragged from it.
    override func hitTest(_ point: NSPoint) -> NSView? { isClickable ? super.hitTest(point) : nil }
}
