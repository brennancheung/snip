import AppKit

enum Pasteboard {
    /// Puts `file` on the general pasteboard as a file, to paste into Finder, Slack or Mail. A
    /// picture also goes on as PNG data, so it pastes into apps that take images but not files.
    @MainActor
    static func copy(file: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard DonePanelView.isImage(file), let data = try? Data(contentsOf: file) else {
            pasteboard.writeObjects([file as NSURL])
            return
        }
        let item = NSPasteboardItem()
        item.setString(file.absoluteString, forType: .fileURL)
        item.setData(data, forType: .png)
        pasteboard.writeObjects([item])
    }
}
