import AppKit
import AVFoundation
import SnipCore

/// The audio inputs Snip can record, and the microphone permission.
@MainActor
enum Microphone {
    struct Input: Identifiable, Equatable {
        /// `AVCaptureDevice.uniqueID`, what `RecordingSettings.microphoneDeviceID` holds.
        let id: String
        let name: String
    }

    /// Built-in and external microphones, the system default first.
    static func inputs() -> [Input] {
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified
        ).devices
        let defaultID = AVCaptureDevice.default(for: .audio)?.uniqueID
        let sorted = devices.filter { $0.uniqueID == defaultID } + devices.filter { $0.uniqueID != defaultID }
        return sorted.map { Input(id: $0.uniqueID, name: $0.localizedName) }
    }

    /// The device to record: the chosen one if it is still connected, otherwise nil (the system default).
    static func available(_ deviceID: String?) -> String? {
        guard let deviceID, inputs().contains(where: { $0.id == deviceID }) else { return nil }
        return deviceID
    }

    /// Turns the microphone on in the saved settings, with `deviceID` when given, once Snip may use it.
    /// The first time, this asks for microphone access; if it is refused, the setting stays off and an
    /// alert says where to turn it on. A recording in progress follows the setting (AppController).
    static func turnOn(deviceID: String? = nil) {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            setOn(deviceID: deviceID)
            return
        }
        Task {
            if await hasAccess() {
                setOn(deviceID: deviceID)
                return
            }
            let alert = NSAlert()
            alert.messageText = "Snip can’t use the microphone"
            alert.informativeText = "Turn on Snip in System Settings › Privacy & Security › Microphone."
            NSApp.activate()
            alert.runModal()
        }
    }

    static func turnOff() {
        SettingsStore.shared.settings.recordMicrophone = false
    }

    static func toggle() {
        if SettingsStore.shared.settings.recordMicrophone { turnOff() } else { turnOn() }
    }

    private static func setOn(deviceID: String?) {
        var settings = SettingsStore.shared.settings
        settings.recordMicrophone = true
        if let deviceID { settings.microphoneDeviceID = deviceID }
        SettingsStore.shared.settings = settings
    }

    /// Shows the system prompt if the user hasn't been asked yet.
    private static func hasAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }
}
