import Foundation

/// Proposes the folders to offer on first run.
///
/// Two sources, in order of confidence: the folders the user's editors have actually opened
/// (read from each editor's own state file), and the conventional folder names IDEs create.
/// The user confirms the result — this only decides what the list starts with.
enum WorkspaceDiscovery {
    /// Folder names IDEs and long-standing convention put in the home folder.
    static let conventionalRoots = [
        "~/Project", "~/Projects", "~/Developer", "~/dev", "~/code", "~/workspace", "~/src",
        "~/work", "~/git", "~/repos", "~/Sites",
        // JetBrains creates one of these per product.
        "~/StudioProjects", "~/AndroidStudioProjects", "~/IdeaProjects", "~/PycharmProjects",
        "~/WebstormProjects", "~/GolandProjects", "~/PhpstormProjects", "~/RubymineProjects",
        "~/CLionProjects", "~/RiderProjects", "~/DataGripProjects",
        // Other editors and tools.
        "~/eclipse-workspace", "~/NetBeansProjects", "~/Documents/GitHub", "~/Unity",
    ]

    /// VS Code and its forks keep opened folders here, as `file://` URIs.
    static let editorStateFiles = [
        "Code", "Code - Insiders", "Cursor", "Antigravity IDE", "Windsurf", "VSCodium",
    ].map { "\($0)/User/globalStorage/storage.json" }

    static func suggestedRoots(
        home: String = NSHomeDirectory(),
        applicationSupport: String? = nil,
        maximum: Int = 8
    ) -> [String] {
        let support = applicationSupport ?? home + "/Library/Application Support"
        var roots: [String] = []
        var seen = Set<String>()

        func add(_ path: String) {
            let absolute = path.hasPrefix("~/") ? home + "/" + path.dropFirst(2) : path
            let standardized = URL(fileURLWithPath: absolute).standardizedFileURL.path
            // Only real folders strictly inside the home folder, and never the home folder itself.
            guard standardized.hasPrefix(home + "/"), PathGlob.exists(standardized),
                  isDirectory(standardized), seen.insert(standardized.lowercased()).inserted else { return }
            // A folder already covered by one on the list adds nothing.
            guard !roots.contains(where: { standardized.hasPrefix(expand($0, home: home) + "/") }) else { return }
            roots.append(display(standardized, home: home))
        }

        for path in conventionalRoots { add(path) }
        for parent in openedProjectParents(home: home, support: support) { add(parent) }
        return Array(roots.prefix(maximum))
    }

    /// The parent folder of every project the user's editors have open or recently open.
    static func openedProjectParents(home: String, support: String) -> [String] {
        var parents: [String] = []
        for relative in editorStateFiles {
            let url = URL(fileURLWithPath: support).appendingPathComponent(relative)
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            for folder in folderURIs(in: json) {
                guard let path = URL(string: folder)?.path, !path.isEmpty else { continue }
                let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
                // A project sitting directly in the home folder gives no usable parent.
                if parent != home { parents.append(parent) }
            }
        }
        for file in jetBrainsRecentFiles(support: support) {
            guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
            for path in jetBrainsProjectPaths(in: text, home: home) {
                let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
                if parent != home { parents.append(parent) }
            }
        }
        return parents
    }

    /// Every `file://` string under a key that names a folder, at any depth.
    static func folderURIs(in json: Any) -> [String] {
        var found: [String] = []
        func walk(_ value: Any, key: String) {
            switch value {
            case let dictionary as [String: Any]:
                for (name, child) in dictionary { walk(child, key: name) }
            case let array as [Any]:
                for child in array { walk(child, key: key) }
            case let text as String:
                let isFolderKey = key == "folderUri" || key == "folder"
                if isFolderKey, text.hasPrefix("file://") { found.append(text) }
            default:
                break
            }
        }
        walk(json, key: "")
        return found
    }

    static func jetBrainsRecentFiles(support: String) -> [String] {
        ["JetBrains", "Google"].flatMap { vendor in
            PathGlob.expand("\(support)/\(vendor)/*/options/recentProjects.xml").map(\.path)
        }
    }

    /// `<entry key="$USER_HOME$/code/app" ...>` is how JetBrains records a recent project.
    static func jetBrainsProjectPaths(in xml: String, home: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"key="\$USER_HOME\$/([^"]+)""#) else { return [] }
        return regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).compactMap { match in
            Range(match.range(at: 1), in: xml).map { home + "/" + xml[$0] }
        }
    }

    private static func isDirectory(_ path: String) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue
    }

    private static func expand(_ path: String, home: String) -> String {
        path.hasPrefix("~/") ? home + "/" + path.dropFirst(2) : path
    }

    private static func display(_ path: String, home: String) -> String {
        path.hasPrefix(home + "/") ? "~/" + path.dropFirst(home.count + 1) : path
    }
}
