import AppKit
import SnipCore

/// The menu bar icon and its menu. While recording there is no menu: a click stops.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    var onNewRecording: (() -> Void)?
    var onRecordLastArea: (() -> Void)?
    var onSettings: (() -> Void)?
    var onStop: (() -> Void)?
    /// Read each time the menu opens.
    var hotKey: () -> HotKeySpec = { SettingsStore.shared.hotKey }
    var hasLastArea: () -> Bool = { false }

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var state: RecorderState = .idle

    override init() {
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        item.button?.imagePosition = .imageLeading
        item.button?.target = self
        item.button?.action = #selector(buttonClicked)
        update(.idle)
    }

    func update(_ state: RecorderState) {
        self.state = state
        guard let button = item.button else { return }
        switch state {
        case .recording(let startedAt):
            item.menu = nil
            button.image = Self.symbol("record.circle.fill")
            button.contentTintColor = .systemRed
            setTitle(RecordingPill.formatElapsed(Int(Date().timeIntervalSince(startedAt))))
        case .encoding(let progress):
            item.menu = menu
            button.image = Self.symbol("record.circle")
            button.contentTintColor = nil
            setTitle("\(Int((progress * 100).rounded()))%")
        default:
            item.menu = menu
            button.image = Self.symbol("record.circle")
            button.contentTintColor = nil
            setTitle("")
        }
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let idle = state == .idle

        let spec = hotKey()
        let newRecording = NSMenuItem(title: "New Recording", action: #selector(newRecording), keyEquivalent: "")
        if let key = KeyCombo.keyEquivalent(keyCode: spec.keyCode) {
            newRecording.keyEquivalent = key
            newRecording.keyEquivalentModifierMask = KeyCombo.modifierFlags(carbon: spec.carbonModifiers)
        }
        newRecording.isEnabled = idle
        add(newRecording)

        let last = NSMenuItem(title: "Record Last Area", action: #selector(recordLastArea), keyEquivalent: "")
        last.isEnabled = idle && hasLastArea()
        add(last)

        let recents = RecentRecordings().list().prefix(5)
        if !recents.isEmpty {
            menu.addItem(.separator())
            for recent in recents {
                let entry = NSMenuItem(title: recent.url.lastPathComponent, action: #selector(revealRecent(_:)), keyEquivalent: "")
                entry.subtitle = ByteCountFormatter.string(fromByteCount: recent.sizeBytes, countStyle: .file)
                entry.representedObject = recent.url
                add(entry)
            }
        }

        menu.addItem(.separator())
        add(NSMenuItem(title: "Settings…", action: #selector(settings), keyEquivalent: ","))
        let quit = NSMenuItem(title: "Quit Snip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    private func add(_ entry: NSMenuItem) {
        entry.target = self
        menu.addItem(entry)
    }

    private func setTitle(_ title: String) {
        item.button?.attributedTitle = NSAttributedString(
            string: title.isEmpty ? "" : " \(title)",
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)]
        )
    }

    private static func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Snip")
        image?.isTemplate = true
        return image
    }

    @objc private func buttonClicked() {
        // Only reached while there is no menu, that is while recording.
        if case .recording = state { onStop?() }
    }

    @objc private func newRecording() { onNewRecording?() }
    @objc private func recordLastArea() { onRecordLastArea?() }
    @objc private func settings() { onSettings?() }

    @objc private func revealRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
