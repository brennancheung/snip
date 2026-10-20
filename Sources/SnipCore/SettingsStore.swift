import Foundation

/// The global hotkey as Carbon `RegisterEventHotKey` takes it. SnipUI registers it.
public struct HotKeySpec: Codable, Equatable, Sendable {
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

/// The saved `RecordingSettings` and hotkey, kept in UserDefaults as JSON.
/// Setting either saves it and posts `SettingsStore.didChange`.
public final class SettingsStore: @unchecked Sendable {
    public static let shared = SettingsStore()
    /// Posted (object: the store) after `settings` or `hotKey` changes.
    public static let didChange = Notification.Name("SnipSettingsDidChange")

    static let settingsKey = "recordingSettings"
    static let hotKeyKey = "hotKey"

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var storedSettings: RecordingSettings
    private var storedHotKey: HotKeySpec

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        storedSettings = Self.load(RecordingSettings.self, key: Self.settingsKey, from: defaults) ?? RecordingSettings()
        storedHotKey = Self.load(HotKeySpec.self, key: Self.hotKeyKey, from: defaults) ?? .default
    }

    public var settings: RecordingSettings {
        get { lock.withLock { storedSettings } }
        set { update(\.storedSettings, to: newValue, key: Self.settingsKey) }
    }

    public var hotKey: HotKeySpec {
        get { lock.withLock { storedHotKey } }
        set { update(\.storedHotKey, to: newValue, key: Self.hotKeyKey) }
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
