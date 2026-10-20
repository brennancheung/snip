import Foundation
import Testing
@testable import SnipCore

private func localDate() -> Date {
    Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 14, minute: 3, second: 22))!
}

@Test func namesLikeScreenshots() throws {
    let directory = try temporaryDirectory()
    let url = OutputNaming.outputURL(in: directory, date: localDate())
    #expect(url.lastPathComponent == "Snip 2026-10-19 at 14.03.22.mp4")
    #expect(url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL)
}

@Test func addsSuffixWhenTaken() throws {
    let directory = try temporaryDirectory()
    let first = OutputNaming.outputURL(in: directory, date: localDate())
    try Data().write(to: first)
    let second = OutputNaming.outputURL(in: directory, date: localDate())
    #expect(second.lastPathComponent == "Snip 2026-10-19 at 14.03.22 2.mp4")
    try Data().write(to: second)
    #expect(OutputNaming.outputURL(in: directory, date: localDate()).lastPathComponent == "Snip 2026-10-19 at 14.03.22 3.mp4")
    #expect(OutputNaming.outputURL(in: directory, date: localDate(), ext: "mov").lastPathComponent == "Snip 2026-10-19 at 14.03.22.mov")
}

@Test func intermediatesAreUniqueMovs() {
    let a = OutputNaming.intermediateURL()
    let b = OutputNaming.intermediateURL()
    #expect(a != b)
    #expect(a.pathExtension == "mov")
    #expect(a.deletingLastPathComponent().lastPathComponent == "Snip")
}
