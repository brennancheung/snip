import Foundation

/// The last few finished recordings, newest first, for the menu bar. Kept in UserDefaults.
public struct RecentRecordings {
    public struct Entry: Codable, Equatable, Sendable {
        public var url: URL
        public var sizeBytes: Int64
        public var date: Date

        public init(url: URL, sizeBytes: Int64, date: Date) {
            self.url = url
            self.sizeBytes = sizeBytes
            self.date = date
        }
    }

    public static let limit = 5
    static let key = "recentRecordings"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Records a finished file, reading its size from disk. A file already in the list moves to the top.
    public func add(url: URL, date: Date = Date()) {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        add(Entry(url: url, sizeBytes: size, date: date))
    }

    public func add(_ entry: Entry) {
        var entries = stored().filter { $0.url != entry.url }
        entries.insert(entry, at: 0)
        save(Array(entries.prefix(Self.limit)))
    }

    /// Forgets a file, for one moved to the Trash.
    public func remove(url: URL) {
        save(stored().filter { $0.url != url })
    }

    /// The entries whose files still exist, newest first.
    public func list() -> [Entry] {
        let entries = stored()
        let existing = entries.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        if existing.count != entries.count { save(existing) }
        return existing
    }

    private func stored() -> [Entry] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    private func save(_ entries: [Entry]) {
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
