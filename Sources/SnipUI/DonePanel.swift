import AppKit
import AVKit
import SnipCore

/// After a recording: the video ready to play, its name and size, and Copy, Show in Finder, Open,
/// Move to Trash. Floats beside the recorded area until ×, Escape or the next recording.
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

/// The panel's content: the video, its name and size, the fallback note if any, and the buttons.
/// Built from a file alone, so it can be rendered off-screen:
///
///     let view = DonePanelView(file: url, videoSize: await DonePanelView.videoSize(of: url))
///     view.frame.size = view.fittingSize
///
/// Dragging it anywhere but the preview and buttons drags its window.
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
    private var copyButton: NSButton?
    private var copiedReset: Task<Void, Never>?

    /// `videoSize`: the recording's size in pixels, for its aspect ratio (see `videoSize(of:)`).
    /// `player`: one already playing `file`, to keep its position; by default a new one.
    /// `previewLimit`: the most room the preview may take, to fit a small screen.
    /// `scale`: the interface size, the saved one if nil.
    init(file: URL, videoSize: CGSize, note: String? = nil, player: AVPlayer? = nil, previewLimit: CGSize? = nil,
         scale: UIScale? = nil) {
        let ui = scale ?? .current
        let player = player ?? AVPlayer(url: file)
        let size = Self.playerSize(for: videoSize, limit: previewLimit, ui: ui)
        previewSize = size
        self.file = file
        self.player = player
        self.ui = ui
        preview = PreviewView(file: file, player: player, ui: ui)
        super.init(frame: .zero)

        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        appearance = NSAppearance(named: .vibrantDark)
        wantsLayer = true
        layer?.cornerRadius = ui.metric(12)
        layer?.masksToBounds = true

        preview.onClose = { [weak self] in self?.onClose?() }

        let name = NSTextField(labelWithString: file.lastPathComponent)
        name.font = ui.font(13, weight: .medium)
        name.lineBreakMode = .byTruncatingMiddle
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let bytes = NSTextField(labelWithString: Self.formattedSize(of: file))
        bytes.font = ui.font(11)
        bytes.textColor = .secondaryLabelColor
        bytes.setContentCompressionResistancePriority(.required, for: .horizontal)
        let info = NSStackView(views: [name, bytes])
        info.alignment = .firstBaseline
        info.spacing = ui.metric(8)

        let copy = actionButton("Copy", symbol: "doc.on.doc", action: #selector(copyFile))
        copyButton = copy
        let buttons = NSStackView(views: [
            copy,
            actionButton("Show in Finder", symbol: "folder", action: #selector(showInFinder)),
            actionButton("Open", symbol: "arrow.up.forward.app", action: #selector(openFile)),
            actionButton("Move to Trash", symbol: "trash", action: #selector(moveToTrash)),
        ])
        buttons.distribution = .fillEqually
        buttons.spacing = ui.metric(6)

        var rows: [NSView] = [preview, info]
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

    /// The video fitted in 480 × 360, but at least 360 × 120 so the buttons and the player's
    /// controls fit (letterboxed). Scaled by the interface size, and no bigger than `limit`.
    private static func playerSize(for video: CGSize, limit: CGSize?, ui: UIScale) -> CGSize {
        let limit = limit ?? CGSize(width: CGFloat.infinity, height: .infinity)
        let box = CGSize(width: min(ui.metric(480), limit.width), height: min(ui.metric(360), limit.height))
        let fit = min(box.width / video.width, box.height / video.height)
        let minimum = CGSize(width: min(ui.metric(360), limit.width), height: min(ui.metric(120), limit.height))
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
        return hit is NSButton || hit.isDescendant(of: preview) ? hit : self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    // MARK: Buttons

    private func actionButton(_ title: String, symbol: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, image: self.symbol(symbol, title), target: self, action: action)
        button.imagePosition = .imageAbove
        button.imageHugsTitle = true
        button.isBordered = false
        button.font = ui.font(11)
        button.contentTintColor = .labelColor
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
        button.layer?.cornerRadius = ui.metric(8)
        button.heightAnchor.constraint(equalToConstant: ui.metric(46)).isActive = true
        return button
    }

    private func symbol(_ name: String, _ description: String) -> NSImage {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: description) ?? NSImage()
        return image.withSymbolConfiguration(.init(pointSize: ui.metric(15), weight: .regular)) ?? image
    }

    /// Puts the file on the pasteboard, and says "Copied" on the button for a moment.
    @objc private func copyFile() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([file as NSURL])
        copyButton?.title = "Copied"
        copyButton?.image = symbol("checkmark", "Copied")
        copiedReset?.cancel()
        copiedReset = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, let self else { return }
            copyButton?.title = "Copy"
            copyButton?.image = symbol("doc.on.doc", "Copy")
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

        let dragArea = FileDragArea(file: file, player: player, ui: ui)
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
}

/// Over the video: a click plays or pauses, a drag drags the file itself (as a file URL), so it
/// drops into Finder, Slack, Mail or a browser upload.
@MainActor
private final class FileDragArea: NSView, NSDraggingSource {
    private let file: URL
    private let player: AVPlayer
    private let ui: UIScale
    /// The mouse-down of a click or drag in progress.
    private var mouseDownEvent: NSEvent?
    /// The first frame, for the drag image.
    private var thumbnail: NSImage?

    init(file: URL, player: AVPlayer, ui: UIScale) {
        self.file = file
        self.player = player
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
        togglePlayback()
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // A copy, so dropping into a Finder folder never moves the recording out of the output folder.
        context == .outsideApplication ? .copy : []
    }

    private func togglePlayback() {
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
