import Foundation
import Testing
@testable import SnipCore

@Test func removeForgetsOnlyThatFile() {
    let suite = "SnipTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let recents = RecentRecordings(defaults: defaults)
    let first = URL(fileURLWithPath: "/tmp/Snip 1.mp4")
    let second = URL(fileURLWithPath: "/tmp/Snip 2.mp4")
    recents.add(.init(url: first, sizeBytes: 1, date: Date()))
    recents.add(.init(url: second, sizeBytes: 2, date: Date()))

    recents.remove(url: first)

    // `list()` drops entries whose files are missing, so check the stored JSON directly.
    let data = defaults.data(forKey: RecentRecordings.key)!
    let urls = try? JSONDecoder().decode([RecentRecordings.Entry].self, from: data).map(\.url)
    #expect(urls == [second])
}
