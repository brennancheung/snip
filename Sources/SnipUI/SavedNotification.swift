import AppKit
import UserNotifications

/// The "Saved to snip" notification with a Show in Finder action.
final class SavedNotification: NSObject, UNUserNotificationCenterDelegate {
    private static let category = "saved"
    private static let showInFinder = "show-in-finder"
    private static let pathKey = "path"

    /// UserNotifications needs a bundle; `swift run` has none.
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : .current()
    }

    /// Registers the action and asks permission (macOS only asks once).
    func setUp() {
        guard let center else { return }
        center.delegate = self
        let show = UNNotificationAction(identifier: Self.showInFinder, title: "Show in Finder", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: [show], intentIdentifiers: [], options: []),
        ])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Title "Saved to snip", body "Snip 2026-10-19 at 14.03.22.mp4 · 4.2 MB", and `note` on a second line.
    func post(file: URL, note: String?) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        let folder = FileManager.default.displayName(atPath: file.deletingLastPathComponent().path)
        content.title = "Saved to \(folder)"
        var body = file.lastPathComponent
        if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            body += " · " + ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        }
        if let note { body += "\n" + note }
        content.body = body
        content.categoryIdentifier = Self.category
        content.userInfo = [Self.pathKey: file.path]
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil), withCompletionHandler: nil)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = response.actionIdentifier
        if action == Self.showInFinder || action == UNNotificationDefaultActionIdentifier,
           let path = response.notification.request.content.userInfo[Self.pathKey] as? String {
            Task { @MainActor in
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }
}
