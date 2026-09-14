import Foundation

/// Append-only record of every cleanup, so a "what broke my setup?" report can be answered.
///
/// One JSON object per line in `~/Library/Application Support/DevSweep/cleanup.log`, holding the
/// item that ran, what it deleted and any errors. Without it there is no way to tell which rule
/// touched a given file after the fact.
enum CleanupLog {
    struct Entry: Codable, Equatable {
        var date: Date
        var item: String
        var risk: String
        var method: String
        var paths: [String]
        var errors: [String]
    }

    static var directory: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/DevSweep", isDirectory: true)
    }

    static func fileURL(in directory: URL = CleanupLog.directory) -> URL {
        directory.appendingPathComponent("cleanup.log")
    }

    static func record(_ entry: Entry, in directory: URL = CleanupLog.directory) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var line = try? encoder.encode(entry) else { return }
        line.append(0x0A)

        let url = fileURL(in: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: url, options: .atomic)
        }
        trim(url)
    }

    static func read(in directory: URL = CleanupLog.directory) -> [Entry] {
        guard let text = try? String(contentsOf: fileURL(in: directory), encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text.split(separator: "\n").compactMap { line in
            line.data(using: .utf8).flatMap { try? decoder.decode(Entry.self, from: $0) }
        }
    }

    /// Keeps the log bounded; it is a debugging aid, not an archive.
    private static let maxEntries = 500

    private static func trim(_ url: URL, limit: Int = maxEntries) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count > limit else { return }
        let kept = lines.suffix(limit).joined(separator: "\n") + "\n"
        try? kept.write(to: url, atomically: true, encoding: .utf8)
    }
}
