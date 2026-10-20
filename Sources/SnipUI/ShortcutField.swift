import AppKit
import SnipCore
import SwiftUI

/// Click, then press the new key combination. Escape or clicking elsewhere keeps the old one.
struct ShortcutField: NSViewRepresentable {
    var hotKey: HotKeySpec
    /// True while waiting for keys, so the app can pause its own hotkey.
    var onRecordingChange: (Bool) -> Void
    var onChange: (HotKeySpec) -> Void

    func makeNSView(context: Context) -> ShortcutButton {
        let button = ShortcutButton(frame: .zero)
        button.onRecordingChange = onRecordingChange
        button.onChange = onChange
        button.hotKey = hotKey
        return button
    }

    func updateNSView(_ button: ShortcutButton, context: Context) {
        button.onRecordingChange = onRecordingChange
        button.onChange = onChange
        button.hotKey = hotKey
    }
}

final class ShortcutButton: NSButton {
    var onRecordingChange: ((Bool) -> Void)?
    var onChange: ((HotKeySpec) -> Void)?
    var hotKey = HotKeySpec(keyCode: 0, carbonModifiers: 0) {
        didSet { refreshTitle() }
    }

    private var isRecording = false {
        didSet {
            guard isRecording != oldValue else { return }
            refreshTitle()
            onRecordingChange?(isRecording)
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        bezelStyle = .push
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(clicked)
        widthAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { true }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        capture(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }
        capture(event)
    }

    @objc private func clicked() {
        isRecording.toggle()
        if isRecording { window?.makeFirstResponder(self) }
    }

    private func capture(_ event: NSEvent) {
        let modifiers = KeyCombo.carbonModifiers(event.modifierFlags.intersection(.deviceIndependentFlagsMask))
        let keyCode = UInt32(event.keyCode)
        if keyCode == 53, modifiers == 0 {  // Escape
            isRecording = false
            return
        }
        guard KeyCombo.isUsable(keyCode: keyCode, carbonModifiers: modifiers) else {
            NSSound.beep()
            return
        }
        isRecording = false
        onChange?(HotKeySpec(keyCode: keyCode, carbonModifiers: modifiers))
    }

    private func refreshTitle() {
        title = isRecording ? "Type shortcut…" : KeyCombo.display(keyCode: hotKey.keyCode, carbonModifiers: hotKey.carbonModifiers)
    }
}
