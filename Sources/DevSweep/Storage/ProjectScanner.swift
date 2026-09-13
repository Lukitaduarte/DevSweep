import Foundation

struct DevProject: Sendable {
    let url: URL
    /// Marker files (from the stack definitions) present at the project root.
    let markers: Set<String>
    let lastActivity: Date

    var name: String { url.lastPathComponent }
}

/// Finds projects under the configured roots by the marker files stacks declare (pubspec.yaml, go.mod…).
enum ProjectScanner {
    private static let alwaysSkip: Set<String> = ["Library", "node_modules", "Pods", "DerivedData"]
    private static let gitActivity = [".git/index", ".git/FETCH_HEAD", ".git/HEAD"]

    static func scan(
        roots: [String], markers: Set<String>, activityFiles: [String],
        skipNames: Set<String>, maxDepth: Int = 4
    ) -> [DevProject] {
        guard !markers.isEmpty else { return [] }
        let fm = FileManager.default
        let skip = alwaysSkip.union(skipNames)
        let activity = Array(Set(gitActivity + Array(markers) + activityFiles))
        var visitedRoots = Set<String>()
        var projects: [DevProject] = []

        func visit(_ path: String, depth: Int) {
            guard let entries = try? fm.contentsOfDirectory(atPath: path) else { return }
            let found = markers.intersection(entries)
            if !found.isEmpty {
                projects.append(DevProject(url: URL(fileURLWithPath: path), markers: found, lastActivity: lastActivity(path, activity)))
            }
            guard depth < maxDepth else { return }
            for entry in entries where !entry.hasPrefix(".") && !skip.contains(entry) {
                let child = path + "/" + entry
                var isDirectory: ObjCBool = false
                guard fm.fileExists(atPath: child, isDirectory: &isDirectory), isDirectory.boolValue,
                      (try? fm.destinationOfSymbolicLink(atPath: child)) == nil else { continue }
                visit(child, depth: depth + 1)
            }
        }

        for root in roots {
            let path = URL(fileURLWithPath: expandTilde(root)).resolvingSymlinksInPath().path
            // APFS is usually case-insensitive: ~/Project and ~/project are the same folder.
            guard visitedRoots.insert(path.lowercased()).inserted else { continue }
            visit(path, depth: 0)
        }
        return projects
    }

    private static func lastActivity(_ path: String, _ files: [String]) -> Date {
        let dates = files.compactMap { PathGlob.modificationDate(URL(fileURLWithPath: path + "/" + $0)) }
        return dates.max() ?? PathGlob.modificationDate(URL(fileURLWithPath: path)) ?? .distantPast
    }
}
