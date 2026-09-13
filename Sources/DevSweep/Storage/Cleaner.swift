import Foundation

enum SizeCalculator {
    /// Allocated size on disk, via `du` (much faster than enumerating in Swift for large trees).
    static func size(of paths: [URL]) -> Int64 {
        let existing = paths.map(\.path).filter(PathGlob.exists)
        guard !existing.isEmpty else { return 0 }
        var total: Int64 = 0
        for start in stride(from: 0, to: existing.count, by: 200) {
            let chunk = Array(existing[start..<min(start + 200, existing.count)])
            let result = Shell.run("/usr/bin/du", ["-sk"] + chunk, timeout: 900)
            for line in result.stdout.split(separator: "\n") {
                if let field = line.split(separator: "\t").first, let kb = Int64(field) {
                    total += kb * 1024
                }
            }
        }
        return total
    }
}

enum Cleaner {
    /// Cleans a target and returns human-readable errors (empty on success).
    static func clean(_ target: StorageTarget) -> [String] {
        var errors: [String] = []
        if !target.stopProcesses.isEmpty {
            ProcessKiller.terminateMatching(target.stopProcesses)
        }
        switch target.method {
        case .delete:
            errors += target.paths.compactMap(SafeDelete.remove)
        case .trash:
            for url in target.paths where PathGlob.exists(url.path) {
                do {
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                } catch {
                    errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
        case .commands(let commands, let thenDelete):
            for command in commands {
                let result = Shell.run(command[0], Array(command.dropFirst()), timeout: 900)
                if result.status != 0 {
                    let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    errors.append("\(command.joined(separator: " ")): \(message.prefix(160))")
                }
            }
            if thenDelete {
                errors += target.paths.compactMap(SafeDelete.remove)
            }
        }
        return errors
    }
}

enum SafeDelete {
    private static let protectedTopLevel: Set<String> = [
        "Desktop", "Documents", "Downloads", "Library", "Pictures", "Movies", "Music",
        "Applications", "Public", "Project", "Projects", "Developer", ".ssh", ".gnupg", ".config",
    ]
    private static let protectedInLibrary: Set<String> = [
        "Caches", "Application Support", "Developer", "Preferences", "Keychains",
        "Containers", "Group Containers", "Mobile Documents", "Mail", "Messages",
    ]

    /// Last line of defense: only paths strictly inside the home folder, never the well-known roots themselves.
    static func isAllowed(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let home = NSHomeDirectory()
        guard path.hasPrefix(home + "/"), !path.contains("/../") else { return false }
        let parts = path.dropFirst(home.count + 1).split(separator: "/").map(String.init)
        guard !parts.isEmpty else { return false }
        if parts.count == 1 && protectedTopLevel.contains(parts[0]) { return false }
        if parts.count == 2 && parts[0] == "Library" && protectedInLibrary.contains(parts[1]) { return false }
        return true
    }

    static func remove(_ url: URL) -> String? {
        guard PathGlob.exists(url.path) else { return nil }
        guard isAllowed(url) else { return tr("error.blocked", ["path": url.path]) }
        do {
            try FileManager.default.removeItem(at: url)
            return nil
        } catch {
            // Go's module cache (and some Pods) are read-only on purpose.
            Shell.run("/bin/chmod", ["-R", "u+w", url.path], timeout: 300)
            let result = Shell.run("/bin/rm", ["-rf", url.path], timeout: 900)
            guard PathGlob.exists(url.path) else { return nil }
            let reason = result.stderr.split(separator: "\n").first.map(String.init) ?? error.localizedDescription
            return "\(url.lastPathComponent): \(reason)"
        }
    }
}
