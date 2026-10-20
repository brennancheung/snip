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
