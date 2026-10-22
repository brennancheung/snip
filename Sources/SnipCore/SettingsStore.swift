import Foundation

/// The global hotkey as Carbon `RegisterEventHotKey` takes it. SnipUI registers it.
public struct HotKeySpec: Codable, Hashable, Sendable {
    /// A virtual key code (`kVK_*`).
    public var keyCode: UInt32
    /// Carbon modifier flags (`cmdKey`, `shiftKey`, `optionKey`, `controlKey`).
    public var carbonModifiers: UInt32

    public init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    /// ⇧⌘6: kVK_ANSI_6 with cmdKey | shiftKey.
    public static let `default` = HotKeySpec(keyCode: 0x16, carbonModifiers: 0x0100 | 0x0200)
}

/// What each global shortcut does. Each can be set in Settings, or removed.
public enum Shortcut: String, CaseIterable, Sendable {
    /// Start a recording, cancel its countdown, or stop it.
    case record
    /// Drag a box and save a picture of it.
    case areaImage
    /// Click a window and save a picture of it.
    case windowImage

    /// Its name in Settings and messages.
    public var title: String {
        switch self {
        case .record: return "Record"
        case .areaImage: return "Screenshot of an area"
        case .windowImage: return "Screenshot of a window"
        }
    }

    /// ⇧⌘6, ⇧⌘4 and ⇧⌘3.
    public var defaultSpec: HotKeySpec {
        let commandShift: UInt32 = 0x0100 | 0x0200
        switch self {
        case .record: return .default
        case .areaImage: return HotKeySpec(keyCode: 0x15, carbonModifiers: commandShift)  // kVK_ANSI_4
        case .windowImage: return HotKeySpec(keyCode: 0x14, carbonModifiers: commandShift)  // kVK_ANSI_3
        }
    }

    /// The record shortcut keeps the key older builds saved it under.
    var storageKey: String {
        switch self {
        case .record: return "hotKey"
        case .areaImage: return "areaImageHotKey"
        case .windowImage: return "windowImageHotKey"
        }
    }
}

/// The saved `RecordingSettings` and shortcuts, kept in UserDefaults as JSON.
/// Setting any of them saves it and posts `SettingsStore.didChange`.
public final class SettingsStore: @unchecked Sendable {
    public static let shared = SettingsStore()
    /// Posted (object: the store) after `settings` or a shortcut changes.
    public static let didChange = Notification.Name("SnipSettingsDidChange")

    static let settingsKey = "recordingSettings"

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var storedSettings: RecordingSettings
    /// nil: removed in Settings.
    private var storedShortcuts: [Shortcut: HotKeySpec?]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        storedSettings = Self.load(RecordingSettings.self, key: Self.settingsKey, from: defaults) ?? RecordingSettings()
        var shortcuts: [Shortcut: HotKeySpec?] = [:]
        for shortcut in Shortcut.allCases {
            // Never saved: the default. Saved as null: removed.
            shortcuts[shortcut] = Self.load(HotKeySpec?.self, key: shortcut.storageKey, from: defaults) ?? shortcut.defaultSpec
        }
        storedShortcuts = shortcuts
    }

    public var settings: RecordingSettings {
        get { lock.withLock { storedSettings } }
        set { update(\.storedSettings, to: newValue, key: Self.settingsKey) }
    }

    /// The keys for `shortcut`, or nil if it was removed.
    public func hotKey(for shortcut: Shortcut) -> HotKeySpec? {
        lock.withLock { storedShortcuts[shortcut] ?? nil }
    }

    /// Sets the keys for `shortcut`; nil removes it.
    public func setHotKey(_ spec: HotKeySpec?, for shortcut: Shortcut) {
        // Every shortcut has an entry, so the outer optional is always there; null is saved for nil.
        update(\.storedShortcuts[shortcut], to: .some(spec), key: shortcut.storageKey)
    }

    private func update<Value: Codable & Equatable>(
        _ keyPath: ReferenceWritableKeyPath<SettingsStore, Value>, to value: Value, key: String
    ) {
        let changed: Bool = lock.withLock {
            guard self[keyPath: keyPath] != value else { return false }
            self[keyPath: keyPath] = value
            if let data = try? JSONEncoder().encode(value) {
                defaults.set(data, forKey: key)
            }
            return true
        }
        if changed {
            NotificationCenter.default.post(name: Self.didChange, object: self)
        }
    }

    private static func load<Value: Decodable>(_ type: Value.Type, key: String, from defaults: UserDefaults) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
