import Foundation

/// Names for finished recordings and the temporary files they are made from.
public enum OutputNaming {
    /// "Snip 2026-10-19 at 14.03.22.mp4" in `directory` (local time, like macOS screenshots),
    /// with " 2", " 3" and so on added when that name is already taken.
    public static func outputURL(in directory: URL, date: Date = Date(), ext: String = "mp4") -> URL {
        uniqueURL(in: directory, baseName: "Snip \(stamp(for: date))", ext: ext)
    }

    /// A new, unique .mov in a Snip folder under the temporary directory, for the recorder to write to.
    public static func intermediateURL() -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Snip", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("recording-\(UUID().uuidString)").appendingPathExtension("mov")
    }

    /// `baseName.ext` in `directory`, or `baseName 2.ext`, `baseName 3.ext`... if it exists.
    static func uniqueURL(in directory: URL, baseName: String, ext: String) -> URL {
        let fileManager = FileManager.default
        var candidate = directory.appendingPathComponent(baseName).appendingPathExtension(ext)
        var counter = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) \(counter)").appendingPathExtension(ext)
            counter += 1
        }
        return candidate
    }

    static func stamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter.string(from: date)
    }
}
