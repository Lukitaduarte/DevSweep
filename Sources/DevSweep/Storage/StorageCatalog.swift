import Foundation

/// Turns the storage entries from the stack files into concrete targets on this Mac.
enum StorageCatalog {
    static func build(prefs: PrefsSnapshot, definitions: Definitions) -> [StorageTarget] {
        let projectSpecs = definitions.storage.compactMap(\.definition.project)
        let projects = ProjectScanner.scan(
            roots: prefs.projectRoots,
            markers: Set(projectSpecs.flatMap(\.markers)),
            activityFiles: projectSpecs.flatMap { $0.activityFiles ?? [] },
            skipNames: Set(projectSpecs.flatMap { $0.paths.compactMap { $0.split(separator: "/").first.map(String.init) } })
        )
        let inactiveCutoff = Date().addingTimeInterval(-Double(prefs.inactiveProjectDays) * 86_400)
        var targets: [StorageTarget] = []

        for spec in definitions.storage {
            let definition = spec.definition
            if let required = definition.requiresPath, !PathTemplate.expand(required).contains(where: PathGlob.exists) {
                continue
            }
            var vars = ["inactive_days": String(prefs.inactiveProjectDays)]

            if let provider = definition.provider {
                let context = ProviderContext(
                    prefs: prefs, projects: projects, inactiveCutoff: inactiveCutoff,
                    options: definition.providerOptions ?? [:]
                )
                for result in StorageProviders.run(provider, context: context) {
                    targets.append(makeTarget(spec, vars: vars.merging(result.vars) { $1 }, paths: result.paths, result: result))
                }
                continue
            }

            var paths = (definition.paths ?? []).flatMap { PathResolver.resolve($0) }
            if let project = definition.project {
                var contributing: [DevProject] = []
                for candidate in projects where !candidate.markers.isDisjoint(with: project.markers) {
                    switch project.activity ?? "any" {
                    case "inactive": guard candidate.lastActivity < inactiveCutoff else { continue }
                    case "active": guard candidate.lastActivity >= inactiveCutoff else { continue }
                    default: break
                    }
                    let found = project.paths.map { candidate.url.appendingPathComponent($0) }.filter { PathGlob.exists($0.path) }
                    if !found.isEmpty {
                        contributing.append(candidate)
                        paths += found
                    }
                }
                vars["projects"] = projectList(contributing)
                vars["project_count"] = String(contributing.count)
            }
            targets.append(makeTarget(spec, vars: vars, paths: paths, result: nil))
        }
        return targets.filter { !$0.paths.isEmpty }
    }

    private static func makeTarget(_ spec: StorageSpec, vars: [String: String], paths: [URL], result: ProviderResult?) -> StorageTarget {
        let definition = spec.definition
        return StorageTarget(
            id: result?.key.map { "\(definition.id):\($0)" } ?? definition.id,
            stack: spec.stack,
            title: render(definition.name.text, vars),
            detail: render(definition.description?.text ?? "", vars),
            risk: result?.risk ?? spec.risk,
            paths: paths,
            method: result?.method ?? spec.method,
            stopProcesses: (definition.stopProcesses ?? []) + (result?.stopProcesses ?? []),
            autoRecommend: (definition.autoSuggest ?? true) && (result?.autoSuggest ?? true),
            recommendMinBytes: definition.suggestAbove?.bytes
        )
    }

    static func render(_ template: String, _ vars: [String: String]) -> String {
        vars.reduce(template) { text, pair in text.replacingOccurrences(of: "{\(pair.key)}", with: pair.value) }
    }

    static func projectList(_ projects: [DevProject]) -> String {
        let names = projects.map(\.name)
        let shown = names.prefix(3).joined(separator: ", ")
        return names.count > 3 ? tr("list.and_more", ["items": shown, "count": names.count - 3]) : shown
    }
}
