import AppKit
import AVKit
import SnipCore

/// After a recording: the video ready to play, the file to drag out, and Copy File, Copy Path, Show
/// in Finder, Open, Move to Trash. Floats beside the recorded area until ×, Escape or the next recording.
@MainActor
final class DonePanel: NSObject {
    /// Becomes key when clicked, without activating Snip, so Escape reaches it.
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
        var onEscape: (() -> Void)?

        // Ahead of the first responder, which may be the player view.
        override func sendEvent(_ event: NSEvent) {
            if event.type == .keyDown, event.keyCode == 53 {  // kVK_Escape
                onEscape?()
                return
            }
            super.sendEvent(event)
        }
    }

    /// After ×, Escape, Move to Trash or `close()`.
    var onClose: (() -> Void)?

    private let file: URL
    private let note: String?
    /// Kept across rebuilds for a new interface size, so playback carries on.
    private let player: AVPlayer
    private let panel = Panel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
    private var videoSize: CGSize?
    /// The interface size the content was built at.
    private var ui = UIScale.current
    private var closed = false

    /// `note`: why the file wasn't compressed, when the encode fell back to the .mov.
    init(file: URL, note: String?) {
        self.file = file
        self.note = note
        player = AVPlayer(url: file)
        super.init()
        panel.configureAsSnipOverlay(level: .floating)
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.onEscape = { [weak self] in self?.close() }
    }

    /// Where the pill was: below `area`, above it if there is no room, or inside its bottom edge
    /// for a whole display. Without an area (the window closed), at the bottom of the mouse's screen.
    func show(near area: CGRect?, target: CaptureTarget?) {
        Task {
            let size = await DonePanelView.videoSize(of: file)
            guard !closed else { return }
            videoSize = size
            let mouse = NSEvent.mouseLocation
            let screen = area.flatMap(ScreenGeometry.screen(for:))
                ?? NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
            build(on: screen)
            place(near: area, target: target, on: screen)
            panel.orderFrontRegardless()
            NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged),
                                                   name: SettingsStore.didChange, object: nil)
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        NotificationCenter.default.removeObserver(self)
        player.pause()
        player.replaceCurrentItem(with: nil)
        panel.orderOut(nil)
        onClose?()
    }

    /// Builds the content for the current interface size, with the preview made smaller if the
    /// whole panel wouldn't fit on `screen`.
    private func build(on screen: NSScreen?) {
        guard let videoSize else { return }
        ui = .current
        var view = DonePanelView(file: file, videoSize: videoSize, note: note, player: player, scale: ui)
        if let visible = screen?.visibleFrame {
            let margin = ui.metric(8)
            let overflow = CGSize(width: view.fittingSize.width - (visible.width - 2 * margin),
                                  height: view.fittingSize.height - (visible.height - 2 * margin))
            if overflow.width > 0 || overflow.height > 0 {
                let limit = CGSize(width: max(view.previewSize.width - max(overflow.width, 0), 1),
                                   height: max(view.previewSize.height - max(overflow.height, 0), 1))
                view = DonePanelView(file: file, videoSize: videoSize, note: note, player: player,
                                     previewLimit: limit, scale: ui)
            }
        }
        view.onClose = { [weak self] in self?.close() }
        panel.contentView = view
        panel.setContentSize(view.fittingSize)
    }

    /// A new interface size rebuilds the content, keeping the panel's top edge and centre.
    @objc private func settingsChanged() {
        guard !closed, UIScale.current != ui else { return }
        let top = panel.frame.maxY
        let centre = panel.frame.midX
        let screen = panel.screen ?? NSScreen.main
        build(on: screen)
        let size = panel.frame.size
        move(to: CGPoint(x: centre - size.width / 2, y: top - size.height), on: screen)
    }

    private func place(near area: CGRect?, target: CaptureTarget?, on screen: NSScreen?) {
        guard let screen else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        guard let area else {
            move(to: CGPoint(x: visible.midX - size.width / 2, y: visible.minY + ui.metric(24)), on: screen)
            return
        }
        let below = area.minY - ui.metric(10) - size.height
        let above = area.maxY + ui.metric(10)
        let inside = max(area.minY, visible.minY) + ui.metric(24)
        let y: CGFloat
        if case .display? = target {
            y = inside
        } else if below >= visible.minY {
            y = below
        } else if above + size.height <= visible.maxY {
            y = above
        } else {
            y = inside
        }
        move(to: CGPoint(x: area.midX - size.width / 2, y: y), on: screen)
    }

    /// Moves the panel's origin to `origin`, kept inside the screen's visible frame.
    private func move(to origin: CGPoint, on screen: NSScreen?) {
        guard let visible = screen?.visibleFrame else {
            panel.setFrameOrigin(origin)
            return
        }
        let size = panel.frame.size
        let margin = ui.metric(8)
        let x = min(max(origin.x, visible.minX + margin), visible.maxX - size.width - margin)
        let y = min(max(origin.y, visible.minY + margin), visible.maxY - size.height - margin)
        panel.setFrameOrigin(CGPoint(x: x, y: y))
    }
}

/// The panel's content: the video, the file chip (its name and size, dragged to drag the file), the
/// fallback note if any, and the buttons.
/// Built from a file alone, so it can be rendered off-screen:
///
///     let view = DonePanelView(file: url, videoSize: await DonePanelView.videoSize(of: url))
///     view.frame.size = view.fittingSize
///
/// Dragging it anywhere but the preview, the file chip and the buttons drags its window.
@MainActor
final class DonePanelView: NSVisualEffectView {
    /// After × or Move to Trash.
    var onClose: (() -> Void)?
    /// The preview's size, which sets the panel's width.
    let previewSize: CGSize

    private let file: URL
    private let player: AVPlayer
    private let ui: UIScale
    private let preview: PreviewView
    private let chip: FileChip
    private let copyFileButton: ActionButton
    private let copyPathButton: ActionButton
    private var copiedReset: [ObjectIdentifier: Task<Void, Never>] = [:]

    /// `videoSize`: the recording's size in pixels, for its aspect ratio (see `videoSize(of:)`).
    /// `player`: one already playing `file`, to keep its position; by default a new one.
    /// `previewLimit`: the most room the preview may take, to fit a small screen.
    /// `scale`: the interface size, the saved one if nil.
    init(file: URL, videoSize: CGSize, note: String? = nil, player: AVPlayer? = nil, previewLimit: CGSize? = nil,
         scale: UIScale? = nil) {
        let ui = scale ?? .current
        let player = player ?? AVPlayer(url: file)
        // The buttons first: their row sets the panel's narrowest width.
        let copyFile = ActionButton(title: Self.copyFileLabel.title, symbol: Self.copyFileLabel.symbol,
                                    reserving: "Copied", ui: ui)
        let copyPath = ActionButton(title: Self.copyPathLabel.title, symbol: Self.copyPathLabel.symbol,
                                    reserving: "Copied", ui: ui)
        copyFileButton = copyFile
        copyPathButton = copyPath
        let actions: [(ActionButton, Selector)] = [
            (copyFile, #selector(DonePanelView.copyFile)),
            (copyPath, #selector(DonePanelView.copyPath)),
            (ActionButton(title: "Show in Finder", symbol: "folder", ui: ui), #selector(DonePanelView.showInFinder)),
            (ActionButton(title: "Open", symbol: "arrow.up.forward.app", ui: ui), #selector(DonePanelView.openFile)),
            (ActionButton(title: "Move to Trash", symbol: "trash", ui: ui), #selector(DonePanelView.moveToTrash)),
        ]
        let buttons = NSStackView(views: actions.map { $0.0 })
        buttons.distribution = .equalSpacing
        buttons.spacing = ui.metric(6)
        let size = Self.playerSize(for: videoSize, limit: previewLimit, minimumWidth: buttons.fittingSize.width, ui: ui)
        previewSize = size
        self.file = file
        self.player = player
        self.ui = ui
        preview = PreviewView(file: file, player: player, ui: ui)
        chip = FileChip(file: file, size: Self.formattedSize(of: file), ui: ui)
        super.init(frame: .zero)

        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        appearance = NSAppearance(named: .vibrantDark)
        wantsLayer = true
        layer?.cornerRadius = ui.metric(12)
        layer?.masksToBounds = true

        preview.onClose = { [weak self] in self?.onClose?() }


        for (button, action) in actions {
            button.target = self
            button.action = action
        }

        var rows: [NSView] = [preview, chip]
        if let note {
            let label = NSTextField(wrappingLabelWithString: note)
            label.font = ui.font(11)
            label.textColor = .systemOrange
            label.preferredMaxLayoutWidth = size.width
            rows.append(label)
        }
        rows.append(buttons)

        let padding = ui.metric(10)
        let column = NSStackView(views: rows)
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = ui.metric(8)
        column.setCustomSpacing(ui.metric(10), after: rows[rows.count - 2])
        column.edgeInsets = NSEdgeInsets(top: padding, left: padding, bottom: padding, right: padding)
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor),
            preview.heightAnchor.constraint(equalToConstant: size.height),
        ])
        for row in rows {
            row.widthAnchor.constraint(equalToConstant: size.width).isActive = true
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The size of the recording's video track, rotation applied; 16:9 if it can't be read.
    static func videoSize(of file: URL) async -> CGSize {
        let fallback = CGSize(width: 16, height: 9)
        let asset = AVURLAsset(url: file)
        guard
            let track = try? await asset.loadTracks(withMediaType: .video).first,
            let loaded = try? await track.load(.naturalSize, .preferredTransform)
        else { return fallback }
        let rect = CGRect(origin: .zero, size: loaded.0).applying(loaded.1)
        guard rect.width != 0, rect.height != 0 else { return fallback }
        return CGSize(width: abs(rect.width), height: abs(rect.height))
    }

    /// The first frame, rotation applied, at most 640 pixels on a side.
    static func firstFrame(of file: URL) async -> NSImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: file))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        guard let frame = try? await generator.image(at: .zero).image else { return nil }
        return NSImage(cgImage: frame, size: CGSize(width: frame.width, height: frame.height))
    }

    /// The video fitted in 480 × 360, but at least as wide as the buttons and 120 high so the
    /// player's controls fit (letterboxed). Scaled by the interface size, and no bigger than `limit`.
    private static func playerSize(for video: CGSize, limit: CGSize?, minimumWidth: CGFloat, ui: UIScale) -> CGSize {
        let limit = limit ?? CGSize(width: CGFloat.infinity, height: .infinity)
        let box = CGSize(width: min(ui.metric(480), limit.width), height: min(ui.metric(360), limit.height))
        let fit = min(box.width / video.width, box.height / video.height)
        let minimum = CGSize(width: min(max(ui.metric(360), ceil(minimumWidth)), limit.width),
                             height: min(ui.metric(120), limit.height))
        return CGSize(width: max((video.width * fit).rounded(), minimum.width),
                      height: max((video.height * fit).rounded(), minimum.height))
    }

    private static func formattedSize(of file: URL) -> String {
        let bytes = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// Covers the player with `image`, for snip-ui-preview: an off-screen render doesn't draw video.
    func showStill(_ image: NSImage) {
        preview.showStill(image)
    }

    // MARK: Dragging the window

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return hit is NSButton || hit.isDescendant(of: preview) || hit.isDescendant(of: chip) ? hit : self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    // MARK: Buttons

    private static let copyFileLabel = (title: "Copy File", symbol: "doc.on.doc")
    private static let copyPathLabel = (title: "Copy Path", symbol: "link")

    /// Puts the file itself on the pasteboard, to paste into Finder, Slack or Mail.
    @objc private func copyFile() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([file as NSURL])
        showCopied(on: copyFileButton, then: Self.copyFileLabel)
    }

    /// Puts the file's full path on the pasteboard as text, to paste into a terminal or a chat.
    @objc private func copyPath() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(file.path, forType: .string)
        showCopied(on: copyPathButton, then: Self.copyPathLabel)
    }

    /// Says "Copied" on `button` for a moment, then puts its own label back.
    private func showCopied(on button: ActionButton, then label: (title: String, symbol: String)) {
        button.show(title: "Copied", symbol: "checkmark")
        let key = ObjectIdentifier(button)
        copiedReset[key]?.cancel()
        copiedReset[key] = Task { [weak button] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, let button else { return }
            button.show(title: label.title, symbol: label.symbol)
        }
    }

    @objc private func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([file])
    }

    @objc private func openFile() {
        player.pause()
        NSWorkspace.shared.open(file)
    }

    @objc private func moveToTrash() {
        player.pause()
        let file = self.file
        Task { [weak self] in
            do {
                _ = try await NSWorkspace.shared.recycle([file])
            } catch {
                NSSound.beep()
                return
            }
            RecentRecordings().remove(url: file)
            self?.onClose?()
        }
    }
}

/// A flat button with an SF Symbol and a one-line label side by side, on a rounded fill. It draws
/// itself so it grows with the interface size; its label is centred, so labels line up across a row.
@MainActor
private final class ActionButton: NSButton {
    private let ui: UIScale
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let content: NSStackView
    /// The widest title it will show, so changing the title doesn't change its width.
    private let reserving: String?

    init(title: String, symbol: String, reserving: String? = nil, ui: UIScale) {
        self.ui = ui
        self.reserving = reserving
        content = NSStackView(views: [icon, label])
        super.init(frame: .zero)
        isBordered = false
        self.title = ""
        setButtonType(.momentaryPushIn)

        icon.imageScaling = .scaleNone
        icon.contentTintColor = .labelColor
        // A fixed width, so a different symbol doesn't move the label.
        icon.widthAnchor.constraint(equalToConstant: Self.iconWidth(ui)).isActive = true
        label.font = ui.font(13)
        label.textColor = .labelColor
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = ui.metric(5)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.centerXAnchor.constraint(equalTo: centerXAnchor),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        show(title: title, symbol: symbol)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(title: String, symbol: String) {
        label.stringValue = title
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.image = image?.withSymbolConfiguration(.init(pointSize: ui.metric(13), weight: .regular)) ?? image
        setAccessibilityLabel(title)
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: NSSize {
        let font = ui.font(13)
        let widest = [label.stringValue, reserving ?? ""]
            .map { ceil(NSAttributedString(string: $0, attributes: [.font: font]).size().width) }
            .max() ?? 0
        return NSSize(width: Self.iconWidth(ui) + content.spacing + widest + 2 * ui.metric(10), height: ui.metric(28))
    }

    private static func iconWidth(_ ui: UIScale) -> CGFloat {
        ui.metric(17)
    }

    // The icon and label are parts of the button, not targets of their own.
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var isHighlighted: Bool {
        didSet { needsDisplay = true }
    }

    override var wantsUpdateLayer: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let radius = ui.metric(6)
        let path = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        NSColor.labelColor.withAlphaComponent(isHighlighted ? 0.2 : 0.1).setFill()
        path.fill()
    }
}

/// The video with the player's inline controls (play/pause, scrub) and the close ×. Above the
/// controls, a click plays or pauses and a drag drags the file out.
@MainActor
private final class PreviewView: NSView {
    /// The player's inline control bar, which isn't scaled with the interface size.
    private static let controlsHeight: CGFloat = 48

    var onClose: (() -> Void)?
    private let playerView = AVPlayerView()

    init(file: URL, player: AVPlayer, ui: UIScale) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = ui.metric(6)
        layer?.masksToBounds = true

        playerView.player = player
        playerView.controlsStyle = .inline
        playerView.videoGravity = .resizeAspect
        playerView.showsFullScreenToggleButton = false
        playerView.allowsPictureInPicturePlayback = false
        playerView.showsSharingServiceButton = false

        let image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close") ?? NSImage()
        let configuration = NSImage.SymbolConfiguration(pointSize: ui.metric(16), weight: .regular)
            .applying(.init(paletteColors: [.white, NSColor.black.withAlphaComponent(0.55)]))
        let close = NSButton(image: image.withSymbolConfiguration(configuration) ?? image,
                             target: self, action: #selector(closeClicked))
        close.isBordered = false
        close.toolTip = "Close"

        let dragArea = FileDragView(file: file, ui: ui)
        dragArea.onClick = { Self.togglePlayback(player) }
        // In this order, so the × is on top of the drag area and the drag area on top of the video.
        for view in [playerView, dragArea, close] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        let inset = ui.metric(6)
        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            playerView.topAnchor.constraint(equalTo: topAnchor),
            playerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            dragArea.leadingAnchor.constraint(equalTo: leadingAnchor),
            dragArea.trailingAnchor.constraint(equalTo: trailingAnchor),
            dragArea.topAnchor.constraint(equalTo: topAnchor),
            dragArea.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.controlsHeight),
            close.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            close.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Covers the player with `image`, for snip-ui-preview: an off-screen render doesn't draw video.
    func showStill(_ image: NSImage) {
        let still = NSImageView(image: image)
        still.imageScaling = .scaleProportionallyUpOrDown
        still.translatesAutoresizingMaskIntoConstraints = false
        addSubview(still, positioned: .above, relativeTo: playerView)
        NSLayoutConstraint.activate([
            still.leadingAnchor.constraint(equalTo: leadingAnchor),
            still.trailingAnchor.constraint(equalTo: trailingAnchor),
            still.topAnchor.constraint(equalTo: topAnchor),
            still.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @objc private func closeClicked() { onClose?() }

    private static func togglePlayback(_ player: AVPlayer) {
        guard player.rate == 0 else {
            player.pause()
            return
        }
        if let item = player.currentItem, item.duration.isNumeric, item.currentTime() >= item.duration {
            player.seek(to: .zero)
        }
        player.play()
    }
}

/// A drag drags the file itself (as a file URL), so it drops into Finder, Slack, Mail or a browser
/// upload; a click calls `onClick`. Over the video, and under the file chip.
@MainActor
private class FileDragView: NSView, NSDraggingSource {
    var onClick: (() -> Void)?
    let file: URL
    let ui: UIScale
    /// The mouse-down of a click or drag in progress.
    private var mouseDownEvent: NSEvent?
    /// The first frame, for the drag image.
    private var thumbnail: NSImage?

    init(file: URL, ui: UIScale) {
        self.file = file
        self.ui = ui
        super.init(frame: .zero)
        Task { [weak self] in
            let frame = await DonePanelView.firstFrame(of: file)
            self?.thumbnail = frame
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent else { return }
        let start = down.locationInWindow
        let now = event.locationInWindow
        guard hypot(now.x - start.x, now.y - start.y) > 4 else { return }
        mouseDownEvent = nil

        let image = thumbnail ?? NSWorkspace.shared.icon(forFile: file.path)
        let box = ui.metric(160)
        let fit = min(box / max(image.size.width, 1), box / max(image.size.height, 1))
        let size = CGSize(width: image.size.width * fit, height: image.size.height * fit)
        let point = convert(now, from: nil)
        let item = NSDraggingItem(pasteboardWriter: file as NSURL)
        item.setDraggingFrame(CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                     width: size.width, height: size.height), contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        guard mouseDownEvent != nil else { return }
        mouseDownEvent = nil
        onClick?()
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // A copy, so dropping into a Finder folder never moves the recording out of the output folder.
        context == .outsideApplication ? .copy : []
    }
}

/// The file as something to pick up: its icon, name and size on a rounded fill, with an open hand
/// under the pointer. Drag it into another app instead of going through Finder.
@MainActor
private final class FileChip: FileDragView {
    private var hovering = false {
        didSet { needsDisplay = true }
    }

    init(file: URL, size: String, ui: UIScale) {
        super.init(file: file, ui: ui)
        let icon = NSImageView(image: NSWorkspace.shared.icon(forFile: file.path))
        icon.imageScaling = .scaleProportionallyUpOrDown
        let name = NSTextField(labelWithString: file.lastPathComponent)
        name.font = ui.font(13, weight: .medium)
        name.lineBreakMode = .byTruncatingMiddle
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let bytes = NSTextField(labelWithString: size)
        bytes.font = ui.font(11)
        bytes.textColor = .secondaryLabelColor
        bytes.setContentCompressionResistancePriority(.required, for: .horizontal)
        let hand = NSImageView()
        let symbol = NSImage(systemSymbolName: "hand.draw", accessibilityDescription: nil)
        hand.image = symbol?.withSymbolConfiguration(.init(pointSize: ui.metric(12), weight: .regular)) ?? symbol
        hand.contentTintColor = .secondaryLabelColor
        hand.setContentCompressionResistancePriority(.required, for: .horizontal)
        let drag = NSTextField(labelWithString: "Drag")
        drag.font = ui.font(11)
        drag.textColor = .secondaryLabelColor
        drag.setContentCompressionResistancePriority(.required, for: .horizontal)

        // The drag hint at the right edge.
        let row = NSStackView()
        row.setViews([icon, name, bytes], in: .leading)
        row.setViews([hand, drag], in: .trailing)
        row.alignment = .centerY
        row.spacing = ui.metric(8)
        row.setCustomSpacing(ui.metric(6), after: icon)
        row.setCustomSpacing(ui.metric(4), after: hand)
        row.edgeInsets = NSEdgeInsets(top: 0, left: ui.metric(6), bottom: 0, right: ui.metric(10))
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: ui.metric(22)),
            icon.heightAnchor.constraint(equalToConstant: ui.metric(22)),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: ui.metric(32)),
        ])
        toolTip = "Drag into any app, or onto a folder in Finder"
        setAccessibilityLabel(file.lastPathComponent)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // The icon and labels are parts of the chip, not targets of their own.
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // Active always: the panel doesn't activate Snip, so it is rarely the key window.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        NSCursor.openHand.set()
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        NSCursor.closedHand.set()
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        (hovering ? NSCursor.openHand : NSCursor.arrow).set()
        super.mouseUp(with: event)
    }

    override var wantsUpdateLayer: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let radius = ui.metric(6)
        let path = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        NSColor.labelColor.withAlphaComponent(hovering ? 0.16 : 0.08).setFill()
        path.fill()
    }
}
