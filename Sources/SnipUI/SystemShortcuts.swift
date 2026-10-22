import AppKit
import Carbon.HIToolbox
import SnipCore

/// macOS's own screenshot shortcuts. While one is on, macOS takes its keys before any app sees
/// them, so a Snip shortcut on the same keys never fires.
enum SystemShortcuts {
    private struct Screenshot {
        /// Its number in com.apple.symbolichotkeys.
        let id: String
        /// Its name in System Settings › Keyboard › Keyboard Shortcuts › Screenshots.
        let name: String
        let keyCode: Int
        let carbonModifiers: Int
    }

    private static let screenshots = [
        Screenshot(id: "28", name: "Save picture of screen as a file", keyCode: kVK_ANSI_3, carbonModifiers: cmdKey | shiftKey),
        Screenshot(id: "29", name: "Copy picture of screen to the clipboard", keyCode: kVK_ANSI_3, carbonModifiers: controlKey | cmdKey | shiftKey),
        Screenshot(id: "30", name: "Save picture of selected area as a file", keyCode: kVK_ANSI_4, carbonModifiers: cmdKey | shiftKey),
        Screenshot(id: "31", name: "Copy picture of selected area to the clipboard", keyCode: kVK_ANSI_4, carbonModifiers: controlKey | cmdKey | shiftKey),
        Screenshot(id: "184", name: "Screenshot and recording options", keyCode: kVK_ANSI_5, carbonModifiers: cmdKey | shiftKey),
    ]

    /// The name of the macOS screenshot shortcut that is on with the keys of `spec`, if any.
    /// A shortcut never changed in System Settings has no saved entry: it is on, with its default keys.
    static func conflict(with spec: HotKeySpec) -> String? {
        let saved = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys") ?? [:]
        for shortcut in screenshots {
            var enabled = true
            var keyCode = shortcut.keyCode
            var modifiers = shortcut.carbonModifiers
            if let entry = saved[shortcut.id] as? [String: Any] {
                enabled = entry["enabled"] as? Bool ?? true
                // parameters: the character, the virtual key code, the NSEvent modifier flags.
                if let value = entry["value"] as? [String: Any], let parameters = value["parameters"] as? [Int], parameters.count == 3 {
                    keyCode = parameters[1]
                    modifiers = Int(KeyCombo.carbonModifiers(NSEvent.ModifierFlags(rawValue: UInt(parameters[2]))))
                }
            }
            if enabled, UInt32(keyCode) == spec.keyCode, UInt32(modifiers) == spec.carbonModifiers {
                return shortcut.name
            }
        }
        return nil
    }
}
