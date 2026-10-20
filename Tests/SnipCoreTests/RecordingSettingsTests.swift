import Foundation
import Testing
@testable import SnipCore

@Test func defaultsGoToMoviesSnip() {
    let settings = RecordingSettings()
    let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
    #expect(settings.resolvedOutputDirectory.path == movies.appendingPathComponent("snip").path)
    #expect(settings.crf == 23)
}

@Test func choosingTheDefaultFolderStoresNil() {
    var settings = RecordingSettings()
    let other = URL(fileURLWithPath: "/tmp/elsewhere", isDirectory: true)
    settings.setOutputDirectory(other)
    #expect(settings.outputDirectory == other)
    settings.setOutputDirectory(URL(fileURLWithPath: RecordingSettings.defaultOutputDirectory.path + "/"))
    #expect(settings.outputDirectory == nil)
}

@Test func createsAMissingOutputFolder() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("snip-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    var settings = RecordingSettings()
    settings.outputDirectory = root.appendingPathComponent("a/b", isDirectory: true)
    let created = try settings.createOutputDirectory()
    var isDirectory: ObjCBool = false
    #expect(FileManager.default.fileExists(atPath: created.path, isDirectory: &isDirectory))
    #expect(isDirectory.boolValue)
    // Again, now that it exists.
    _ = try settings.createOutputDirectory()
}

@Test func automaticInterfaceSizeIsLargeOnlyOnWideOneXDisplays() {
    // The owner's 7680 × 2160 monitor at 1x.
    #expect(RecordingSettings.automaticInterfaceScale(displayWidth: 7680, backingScale: 1) == 2)
    #expect(RecordingSettings.automaticInterfaceScale(displayWidth: 5120, backingScale: 1) == 2)
    #expect(RecordingSettings.automaticInterfaceScale(displayWidth: 5000, backingScale: 1) == 1)
    #expect(RecordingSettings.automaticInterfaceScale(displayWidth: 2560, backingScale: 1) == 1)
    // Retina: the default sizes are already physically right.
    #expect(RecordingSettings.automaticInterfaceScale(displayWidth: 7680, backingScale: 2) == 1)
    #expect(RecordingSettings.automaticInterfaceScale(displayWidth: 1512, backingScale: 2) == 1)
}

@Test func chosenInterfaceSizeWinsAndStaysInRange() {
    var settings = RecordingSettings()
    #expect(settings.interfaceScale == nil)
    #expect(settings.effectiveInterfaceScale(displayWidth: 7680, backingScale: 1) == 2)
    #expect(settings.effectiveInterfaceScale(displayWidth: 1512, backingScale: 2) == 1)

    settings.interfaceScale = 1.25
    #expect(settings.effectiveInterfaceScale(displayWidth: 7680, backingScale: 1) == 1.25)
    settings.interfaceScale = 9
    #expect(settings.effectiveInterfaceScale(displayWidth: 1512, backingScale: 2) == 2.5)
    settings.interfaceScale = 0.1
    #expect(settings.effectiveInterfaceScale(displayWidth: 1512, backingScale: 2) == 1)
    settings.interfaceScale = .nan
    #expect(settings.effectiveInterfaceScale(displayWidth: 7680, backingScale: 1) == 2)
}
