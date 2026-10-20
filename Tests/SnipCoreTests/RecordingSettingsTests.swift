import Foundation
import Testing
@testable import SnipCore

@Test func defaultsGoToDownloads() {
    let settings = RecordingSettings()
    #expect(settings.resolvedOutputDirectory.lastPathComponent == "Downloads")
    #expect(settings.crf == 23)
}
