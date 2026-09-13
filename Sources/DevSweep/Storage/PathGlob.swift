import Darwin
import Foundation

enum PathGlob {
    /// Expands `~` and shell-style wildcards (`*`, `?`, `[...]`) component by component.
    /// `excluding` filters results by their last path component.
    static func expand(_ pattern: String, excluding: Set<String> = []) -> [URL] {
        let full = expandTilde(pattern)
        guard full.hasPrefix("/") else { return [] }
        let fm = FileManager.default
        var current = ["/"]
        for component in full.split(separator: "/").map(String.init) {
            let isPattern = component.contains { "*?[".contains($0) }
            var next: [String] = []
            for base in current {
                if isPattern {
                    guard let children = try? fm.contentsOfDirectory(atPath: base) else { continue }
                    for child in children.sorted() where fnmatch(component, child, 0) == 0 {
                        next.append((base as NSString).appendingPathComponent(child))
                    }
                } else {
                    let candidate = (base as NSString).appendingPathComponent(component)
                    if exists(candidate) { next.append(candidate) }
                }
            }
            current = next
            if current.isEmpty { return [] }
        }
        return current
            .filter { $0 != "/" && !excluding.contains(($0 as NSString).lastPathComponent) }
            .map { URL(fileURLWithPath: $0) }
    }

    static func children(of url: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        return names.sorted().map { url.appendingPathComponent($0) }
    }

    /// True for anything present on disk, including dangling symlinks.
    static func exists(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }

    static func modificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
