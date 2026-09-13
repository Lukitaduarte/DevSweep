import Foundation

/// Finds DevSweep's data folders (`stacks`, `locales`).
enum ResourceLocator {
    /// The bundled copy: an environment override, the app's Resources folder,
    /// or the repository checkout when running with `swift run`.
    static func directory(named name: String, environmentKey: String) -> URL? {
        let fm = FileManager.default
        if let override = ProcessInfo.processInfo.environment[environmentKey], !override.isEmpty {
            return URL(fileURLWithPath: expandTilde(override))
        }
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent(name), fm.fileExists(atPath: bundled.path) {
            return bundled
        }
        let checkout = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(name)
        return fm.fileExists(atPath: checkout.path) ? checkout : nil
    }

    /// Personal additions and overrides kept outside the app: `~/.config/devsweep/<name>`.
    static func userDirectory(named name: String) -> URL {
        URL(fileURLWithPath: expandTilde("~/.config/devsweep")).appendingPathComponent(name)
    }

    static func yamlFiles(in directory: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { ["yaml", "yml"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
