import AppKit
import Carbon.HIToolbox

/// Names and conversions for hotkeys stored as a Carbon key code and Carbon modifier mask.
enum KeyCombo {
    /// "⇧⌘6".
    static func display(keyCode: UInt32, carbonModifiers: UInt32) -> String {
        modifierSymbols(carbonModifiers) + (keyName(keyCode) ?? "Key \(keyCode)")
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon = 0
        if flags.contains(.control) { carbon |= controlKey }
        if flags.contains(.option) { carbon |= optionKey }
        if flags.contains(.shift) { carbon |= shiftKey }
        if flags.contains(.command) { carbon |= cmdKey }
        return UInt32(carbon)
    }

    static func modifierFlags(carbon: UInt32) -> NSEvent.ModifierFlags {
        let carbon = Int(carbon)
        var flags: NSEvent.ModifierFlags = []
        if carbon & controlKey != 0 { flags.insert(.control) }
        if carbon & optionKey != 0 { flags.insert(.option) }
        if carbon & shiftKey != 0 { flags.insert(.shift) }
        if carbon & cmdKey != 0 { flags.insert(.command) }
        return flags
    }

    /// A menu item key equivalent for the key, or nil if there is none.
    static func keyEquivalent(keyCode: UInt32) -> String? {
        if let character = characters[Int(keyCode)] { return character.lowercased() }
        if let function = functionKeys[Int(keyCode)] {
            return String(Character(UnicodeScalar(UInt16(NSF1FunctionKey) + UInt16(function - 1))!))
        }
        return nil
    }

    /// A function key, or a key with at least one of ⌃⌥⌘, works as a global shortcut.
    static func isUsable(keyCode: UInt32, carbonModifiers: UInt32) -> Bool {
        let strong = UInt32(controlKey | optionKey | cmdKey)
        return carbonModifiers & strong != 0 || functionKeys[Int(keyCode)] != nil
    }

    private static func modifierSymbols(_ carbon: UInt32) -> String {
        let carbon = Int(carbon)
        var symbols = ""
        if carbon & controlKey != 0 { symbols += "⌃" }
        if carbon & optionKey != 0 { symbols += "⌥" }
        if carbon & shiftKey != 0 { symbols += "⇧" }
        if carbon & cmdKey != 0 { symbols += "⌘" }
        return symbols
    }

    private static func keyName(_ keyCode: UInt32) -> String? {
        let code = Int(keyCode)
        if let character = characters[code] { return character }
        if let function = functionKeys[code] { return "F\(function)" }
        return named[code]
    }

    /// The ANSI layout's printable keys.
    private static let characters: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
        kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
        kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
        kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
        kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Backslash: "\\", kVK_ANSI_Comma: ",",
        kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/", kVK_ANSI_Grave: "`",
    ]

    private static let functionKeys: [Int: Int] = [
        kVK_F1: 1, kVK_F2: 2, kVK_F3: 3, kVK_F4: 4, kVK_F5: 5, kVK_F6: 6, kVK_F7: 7, kVK_F8: 8,
        kVK_F9: 9, kVK_F10: 10, kVK_F11: 11, kVK_F12: 12, kVK_F13: 13, kVK_F14: 14, kVK_F15: 15,
        kVK_F16: 16, kVK_F17: 17, kVK_F18: 18, kVK_F19: 19,
    ]

    private static let named: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    ]
}
