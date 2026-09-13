import Foundation

struct ProviderContext: Sendable {
    let prefs: PrefsSnapshot
    let projects: [DevProject]
    let inactiveCutoff: Date
    let options: [String: [String]]
}

struct ProviderResult: Sendable {
    /// When set, the storage item is repeated per result with id `<id>:<key>`.
    var key: String? = nil
    /// Values for `{placeholders}` in the item's name and description.
    var vars: [String: String] = [:]
    var paths: [URL]
    var autoSuggest: Bool? = nil
    var method: CleanMethod? = nil
    var risk: Risk? = nil
    var stopProcesses: [String] = []
}

/// Swift escape hatch for cleanups that globs can't express.
/// Stack files reference providers by name: `provider: fvm-versions`.
enum StorageProviders {
    static let names: Set<String> = [
        "fvm-versions", "xcode-unavailable-simulators", "android-unused-system-images",
        "nvm-non-default-versions", "old-installers",
    ]

    static func run(_ name: String, context: ProviderContext) -> [ProviderResult] {
        switch name {
        case "fvm-versions": fvmVersions(context)
        case "xcode-unavailable-simulators": [ProviderResult(paths: unavailableSimulators())]
        case "android-unused-system-images": [ProviderResult(paths: unusedAndroidSystemImages(context))]
        case "nvm-non-default-versions": [ProviderResult(paths: nvmNonDefaultVersions())]
        case "old-installers": [oldInstallers(context)]
        default: []
        }
    }

    // MARK: FVM

    /// Every installed Flutter SDK except the global default, with the projects that pin it.
    private static func fvmVersions(_ context: ProviderContext) -> [ProviderResult] {
        var roots = ["~/fvm", "~/.fvm"].map(expandTilde)
        if let custom = ProcessInfo.processInfo.environment["FVM_CACHE_PATH"], !custom.isEmpty {
            roots.insert(expandTilde(custom), at: 0)
        }
        let pinned = context.projects.compactMap { project in fvmVersion(of: project.url).map { (project, $0) } }
        var results: [ProviderResult] = []
        var seen = Set<String>()

        for root in roots {
            let defaultPath = (try? FileManager.default.destinationOfSymbolicLink(atPath: root + "/default")).map {
                URL(fileURLWithPath: $0, relativeTo: URL(fileURLWithPath: root, isDirectory: true)).standardizedFileURL.path
            }
            for url in PathGlob.expand(root + "/versions/*") {
                let path = url.standardizedFileURL.path
                guard path != defaultPath, seen.insert(path).inserted else { continue }
                let version = url.lastPathComponent
                let users = pinned.filter { $0.1 == version }.map(\.0)
                let active = users.filter { $0.lastActivity > context.inactiveCutoff }
                let usage = users.isEmpty
                    ? tr("provider.fvm.unused")
                    : tr(active.isEmpty ? "provider.fvm.used_by_inactive" : "provider.fvm.used_by",
                         ["projects": StorageCatalog.projectList(users)])
                results.append(ProviderResult(
                    key: version, vars: ["version": version, "usage": usage], paths: [url],
                    autoSuggest: active.isEmpty, stopProcesses: [path + "/"]
                ))
            }
        }
        return results
    }

    static func fvmVersion(of project: URL) -> String? {
        for file in [".fvmrc", ".fvm/fvm_config.json"] {
            guard let text = try? String(contentsOf: project.appendingPathComponent(file), encoding: .utf8),
                  let regex = try? NSRegularExpression(pattern: #""(?:flutter|flutterSdkVersion)"\s*:\s*"([^"]+)""#),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else { continue }
            return String(text[range])
        }
        return nil
    }

    // MARK: Xcode

    private static func unavailableSimulators() -> [URL] {
        // Calling xcrun without Xcode pops the "install developer tools" dialog, so check first.
        let xcode = Shell.run("/usr/bin/xcode-select", ["-p"], timeout: 5)
        guard xcode.status == 0, xcode.stdout.contains(".app/") else { return [] }
        let result = Shell.run("/usr/bin/xcrun", ["simctl", "list", "devices", "unavailable", "-j"], timeout: 30)
        guard let json = try? JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any],
              let devices = json["devices"] as? [String: [[String: Any]]] else { return [] }
        return devices.values.flatMap { $0 }
            .compactMap { $0["dataPath"] as? String }
            .map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
    }

    // MARK: Android

    /// System images that no AVD's config.ini points to. Option `sdk` overrides the SDK location.
    private static func unusedAndroidSystemImages(_ context: ProviderContext) -> [URL] {
        let template = context.options["sdk"]?.first ?? "${ANDROID_HOME:-~/Library/Android/sdk}"
        guard let sdk = PathTemplate.expand(template).first else { return [] }
        var used = Set<String>()
        for config in PathGlob.expand(expandTilde("~/.android/avd/*.avd/config.ini")) {
            guard let text = try? String(contentsOf: config, encoding: .utf8) else { continue }
            for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("image.sysdir.1") {
                let value = line.split(separator: "=", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
                let relative = value.hasSuffix("/") ? String(value.dropLast()) : value
                used.insert(URL(fileURLWithPath: sdk + "/" + relative).standardizedFileURL.path)
            }
        }
        return PathGlob.expand(sdk + "/system-images/*/*/*").filter { !used.contains($0.standardizedFileURL.path) }
    }

    // MARK: Node

    /// nvm installs other than the default alias and the newest one.
    private static func nvmNonDefaultVersions() -> [URL] {
        let versions = PathGlob.expand(expandTilde("~/.nvm/versions/node/*"))
            .sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedAscending }
        let alias = (try? String(contentsOfFile: expandTilde("~/.nvm/alias/default"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let keep = Set(versions.filter { url in
            let name = url.lastPathComponent
            return !alias.isEmpty && (name == alias || name == "v" + alias || name.hasPrefix("v" + alias + "."))
        } + versions.suffix(1))
        return versions.filter { !keep.contains($0) }
    }

    // MARK: Installers

    /// Old build artifacts in personal folders. Options: `extensions`, `folders`.
    private static func oldInstallers(_ context: ProviderContext) -> ProviderResult {
        let extensions = Set((context.options["extensions"] ?? ["ipa", "apk", "aab"]).map { $0.lowercased() })
        let folders = context.options["folders"] ?? ["~/Downloads", "~/Desktop", "~/Documents"]
        let days = context.prefs.artifactAgeDays
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let keys: [URLResourceKey] = [.addedToDirectoryDateKey, .creationDateKey, .contentModificationDateKey]

        var found: [URL] = []
        for folder in folders.flatMap({ PathTemplate.expand($0) }) {
            guard let enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: folder), includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            while let url = enumerator.nextObject() as? URL {
                if enumerator.level > 3 || url.lastPathComponent == "node_modules" {
                    enumerator.skipDescendants()
                    continue
                }
                guard extensions.contains(url.pathExtension.lowercased()) else { continue }
                let values = try? url.resourceValues(forKeys: Set(keys))
                let date = values?.addedToDirectoryDate ?? values?.creationDate ?? values?.contentModificationDate ?? .now
                if date < cutoff { found.append(url) }
            }
        }

        let toTrash = context.prefs.artifactsToTrash
        return ProviderResult(
            vars: [
                "count": String(found.count), "days": String(days),
                "trash_note": toTrash ? tr("provider.installers.trash_note") : "",
            ],
            paths: found,
            method: toTrash ? .trash : .delete,
            risk: toTrash ? .safe : .dataLoss
        )
    }
}
