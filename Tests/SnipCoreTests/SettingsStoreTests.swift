import Foundation
import Testing
@testable import SnipCore

private func freshDefaults() -> UserDefaults {
    let suite = "SnipTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@Test func settingsRoundTripThroughJSON() throws {
    var settings = RecordingSettings()
    settings.fps = 60
    settings.crf = 28
    settings.preset = "slow"
    settings.scale = .half
    settings.showCursor = false
    settings.countdownSeconds = 0
    settings.copyToClipboard = false
    settings.outputDirectory = URL(fileURLWithPath: "/Users/me/Movies", isDirectory: true)
    settings.recordMicrophone = true
    settings.microphoneDeviceID = "BuiltInMicrophoneDevice"
    settings.recordSystemAudio = false
    settings.interfaceScale = 1.75
    let decoded = try JSONDecoder().decode(RecordingSettings.self, from: JSONEncoder().encode(settings))
    #expect(decoded == settings)
}

@Test func missingAndBadKeysFallBackToDefaults() throws {
    let json = #"{"crf": 30, "scale": "quarter", "fps": "sixty", "recordMicrophone": "yes"}"#
    let decoded = try JSONDecoder().decode(RecordingSettings.self, from: Data(json.utf8))
    var expected = RecordingSettings()
    expected.crf = 30
    #expect(decoded == expected)
    // Settings saved before the audio keys existed: microphone off, system audio on.
    #expect(!decoded.recordMicrophone && decoded.microphoneDeviceID == nil && decoded.recordSystemAudio)
    #expect(decoded.interfaceScale == nil)
}

@Test func unreadableInterfaceScaleMeansAutomatic() throws {
    let json = #"{"interfaceScale": "huge"}"#
    let decoded = try JSONDecoder().decode(RecordingSettings.self, from: Data(json.utf8))
    #expect(decoded.interfaceScale == nil)
}

@Test func storePersistsAndNotifies() {
    let defaults = freshDefaults()
    let store = SettingsStore(defaults: defaults)
    #expect(store.settings == RecordingSettings())
    #expect(store.hotKey == HotKeySpec(keyCode: 0x16, carbonModifiers: 0x0300))

    let notifications = Fractions()
    let observer = NotificationCenter.default.addObserver(forName: SettingsStore.didChange, object: nil, queue: nil) { _ in
        notifications.append(1)
    }
    defer { NotificationCenter.default.removeObserver(observer) }

    store.settings.crf = 19
    store.hotKey = HotKeySpec(keyCode: 0x17, carbonModifiers: 0x0100)
    store.settings.crf = 19
    #expect(notifications.values.count == 2)

    let reloaded = SettingsStore(defaults: defaults)
    #expect(reloaded.settings.crf == 19)
    #expect(reloaded.hotKey == HotKeySpec(keyCode: 0x17, carbonModifiers: 0x0100))
}

@Test func recentRecordingsKeepFiveExistingFiles() throws {
    let directory = try temporaryDirectory()
    let recents = RecentRecordings(defaults: freshDefaults())
    var urls: [URL] = []
    for index in 1...7 {
        let url = directory.appendingPathComponent("clip \(index).mp4")
        try Data(repeating: 0, count: index * 10).write(to: url)
        urls.append(url)
        recents.add(url: url, date: Date(timeIntervalSince1970: Double(index)))
    }
    #expect(recents.list().map(\.url.lastPathComponent) == ["clip 7.mp4", "clip 6.mp4", "clip 5.mp4", "clip 4.mp4", "clip 3.mp4"])
    #expect(recents.list().first?.sizeBytes == 70)

    try FileManager.default.removeItem(at: urls[5])
    #expect(recents.list().map(\.url.lastPathComponent) == ["clip 7.mp4", "clip 5.mp4", "clip 4.mp4", "clip 3.mp4"])
}
