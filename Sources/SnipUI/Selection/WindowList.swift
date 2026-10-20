import AppKit

/// A normal on-screen window the overlay can highlight.
struct OverlayWindow: Equatable {
    let id: CGWindowID
    let appName: String
    /// In AppKit global coordinates.
    let frame: CGRect
}

enum WindowList {
    /// Normal on-screen windows, front to back, without Snip's own. Owner names need no permission;
    /// window titles would need Screen Recording, and the overlay doesn't use them.
    static func onScreen(primaryHeight: CGFloat) -> [OverlayWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let entries = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return entries.compactMap { entry in
            guard (entry[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let number = entry[kCGWindowNumber as String] as? NSNumber,
                  let pid = entry[kCGWindowOwnerPID as String] as? NSNumber, pid.int32Value != ownPID,
                  let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
                  bounds.width >= 40, bounds.height >= 40
            else { return nil }
            if let alpha = entry[kCGWindowAlpha as String] as? NSNumber, alpha.doubleValue <= 0.01 { return nil }
            return OverlayWindow(
                id: number.uint32Value,
                appName: entry[kCGWindowOwnerName as String] as? String ?? "",
                frame: SelectionGeometry.appKitRect(fromQuartz: bounds, primaryHeight: primaryHeight)
            )
        }
    }
}
