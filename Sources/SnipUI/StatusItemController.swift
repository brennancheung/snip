import AppKit
import SnipCore

/// The menu bar icon and its menu. While recording there is no menu: a click stops.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    var onNewRecording: (() -> Void)?
    var onRecordLastArea: (() -> Void)?
    var onAreaImage: (() -> Void)?
    var onWindowImage: (() -> Void)?
    var onSettings: (() -> Void)?
    var onStop: (() -> Void)?
    /// Read each time the menu opens.
    var hotKey: (Shortcut) -> HotKeySpec? = { SettingsStore.shared.hotKey(for: $0) }
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
        case .recording:
            // A red stop square only; the pill shows the time.
            item.menu = nil
            button.image = Self.symbol("stop.fill")
            button.contentTintColor = .systemRed
            setTitle("")
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

        let newItem = NSMenuItem(title: "New Recording", action: #selector(newRecording), keyEquivalent: "")
        showShortcut(.record, on: newItem)
        newItem.isEnabled = idle
        add(newItem)

        let last = NSMenuItem(title: "Record Last Area", action: #selector(recordLastArea), keyEquivalent: "")
        last.isEnabled = idle && hasLastArea()
        add(last)

        menu.addItem(.separator())
        let area = NSMenuItem(title: "Screenshot of Area", action: #selector(areaImage), keyEquivalent: "")
        showShortcut(.areaImage, on: area)
        area.isEnabled = idle
        add(area)
        let window = NSMenuItem(title: "Screenshot of Window", action: #selector(windowImage), keyEquivalent: "")
        showShortcut(.windowImage, on: window)
        window.isEnabled = idle
        add(window)

        menu.addItem(.separator())

        let audio = SettingsStore.shared.settings
        let microphone = NSMenuItem(title: "Microphone", action: #selector(toggleMicrophone), keyEquivalent: "")
        microphone.state = audio.recordMicrophone ? .on : .off
        add(microphone)
        let systemAudio = NSMenuItem(title: "System Audio", action: #selector(toggleSystemAudio), keyEquivalent: "")
        systemAudio.state = audio.recordSystemAudio ? .on : .off
        add(systemAudio)

        let recents = RecentRecordings().list().prefix(5)
        if !recents.isEmpty {
            menu.addItem(.separator())
            for recent in recents {
                let size = ByteCountFormatter.string(fromByteCount: recent.sizeBytes, countStyle: .file)
                let title = "\(Self.recentDate(recent.date)) · \(size)"
                let entry = NSMenuItem(title: title, action: #selector(revealRecent(_:)), keyEquivalent: "")
                entry.toolTip = recent.url.lastPathComponent
                entry.representedObject = recent.url
                let kind = DonePanelView.isImage(recent.url) ? "photo" : "video"
                entry.image = NSImage(systemSymbolName: kind, accessibilityDescription: DonePanelView.isImage(recent.url) ? "Screenshot" : "Recording")
                add(entry)
            }
        }

        menu.addItem(.separator())
        add(NSMenuItem(title: "Settings…", action: #selector(settings), keyEquivalent: ","))
        let quit = NSMenuItem(title: "Quit Snip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    /// Shows the shortcut's keys beside the item, if it has a shortcut.
    private func showShortcut(_ shortcut: Shortcut, on entry: NSMenuItem) {
        guard let spec = hotKey(shortcut), let key = KeyCombo.keyEquivalent(keyCode: spec.keyCode) else { return }
        entry.keyEquivalent = key
        entry.keyEquivalentModifierMask = KeyCombo.modifierFlags(carbon: spec.carbonModifiers)
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

    /// "Today 13.48", "Yesterday 16.30", "Oct 17 09.12", or "Oct 17 2025 09.12" before this year.
    static func recentDate(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH.mm"
        let time = formatter.string(from: date)
        if calendar.isDate(date, inSameDayAs: now) { return "Today \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday \(time)"
        }
        let sameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
        formatter.dateFormat = sameYear ? "MMM d" : "MMM d yyyy"
        return "\(formatter.string(from: date)) \(time)"
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
    @objc private func areaImage() { onAreaImage?() }
    @objc private func windowImage() { onWindowImage?() }
    @objc private func settings() { onSettings?() }

    @objc private func toggleMicrophone() {
        Microphone.toggle()
    }

    @objc private func toggleSystemAudio() {
        SettingsStore.shared.settings.recordSystemAudio.toggle()
    }

    @objc private func revealRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
