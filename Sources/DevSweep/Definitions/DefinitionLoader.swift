import Foundation
import Yams

struct StackInfo: Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    let icon: String
    let order: Int

    /// Apps found in /Applications, grouped automatically without a stack file.
    static var apps: StackInfo {
        StackInfo(id: "apps", name: tr("stack.apps"), icon: "app.dashed", order: 10_000)
    }
}

struct StorageSpec: Sendable {
    let definition: StorageDefinition
    let stack: StackInfo
    let risk: Risk
    let method: CleanMethod
}

struct Definitions: Sendable {
    var stacks: [StackInfo] = []
    var processRules: [ProcessRule] = []
    var storage: [StorageSpec] = []
    var issues: [String] = []
    var fileCount = 0

    static let empty = Definitions()
}

/// Loads `stacks/*.yaml` (bundled) and `~/.config/devsweep/stacks/*.yaml` (personal).
/// Later directories override entries with the same id; `disabled: true` removes one.
enum DefinitionLoader {
    static func defaultDirectories() -> [URL] {
        [
            ResourceLocator.directory(named: "stacks", environmentKey: "DEVSWEEP_STACKS_DIR"),
            ResourceLocator.userDirectory(named: "stacks"),
        ].compactMap { $0 }
    }

    private struct Entry<Definition> {
        let stackID: String
        let definition: Definition
        let source: String
    }

    static func load(from directories: [URL] = defaultDirectories()) -> Definitions {
        var result = Definitions()
        var headers: [String: StackHeader] = [:]
        var matchers: [String: Matcher] = [:]
        var processes: [Entry<ProcessDefinition>] = []
        var storage: [Entry<StorageDefinition>] = []

        for directory in directories {
            var processIDs = Set<String>()
            var storageIDs = Set<String>()
            for file in ResourceLocator.yamlFiles(in: directory) {
                let source = file.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
                let text: String
                let parsed: StackFile
                do {
                    text = try String(contentsOf: file, encoding: .utf8)
                    parsed = try YAMLDecoder().decode(StackFile.self, from: text)
                } catch {
                    result.issues.append("\(source): \(describe(error))")
                    continue
                }
                result.issues += SchemaLint.check(yaml: text).map { "\(source): \($0)" }
                result.fileCount += 1

                let stackID = parsed.stack.id
                headers[stackID] = parsed.stack
                matchers.merge(parsed.matchers ?? [:]) { _, new in new }

                for definition in parsed.processes ?? [] {
                    guard processIDs.insert(definition.id).inserted else {
                        result.issues.append("\(source): duplicate process id '\(definition.id)'")
                        continue
                    }
                    let entry = Entry(stackID: stackID, definition: definition, source: source)
                    if let index = processes.firstIndex(where: { $0.definition.id == definition.id }) {
                        processes[index] = entry
                    } else {
                        processes.append(entry)
                    }
                }
                for definition in parsed.storage ?? [] {
                    guard storageIDs.insert(definition.id).inserted else {
                        result.issues.append("\(source): duplicate storage id '\(definition.id)'")
                        continue
                    }
                    let entry = Entry(stackID: stackID, definition: definition, source: source)
                    if let index = storage.firstIndex(where: { $0.definition.id == definition.id }) {
                        storage[index] = entry
                    } else {
                        storage.append(entry)
                    }
                }
            }
        }

        var stacks: [String: StackInfo] = [:]
        for (id, header) in headers {
            stacks[id] = StackInfo(id: id, name: header.name.text, icon: header.icon ?? "shippingbox", order: header.order ?? 100)
        }

        for (name, matcher) in matchers {
            if matcher.isEmpty { result.issues.append("matchers.\(name): matcher is empty") }
            for missing in matcher.references where matchers[missing] == nil {
                result.issues.append("matchers.\(name): matcher '\(missing)' not found")
            }
            if hasCycle(from: name, matchers) {
                result.issues.append("matchers.\(name): references itself")
            }
        }

        result.processRules = buildRules(processes, stacks: stacks, matchers: matchers, issues: &result.issues)
        result.storage = buildStorage(storage, stacks: stacks, issues: &result.issues)
        result.stacks = stacks.values.sorted { ($0.order, $0.name) < ($1.order, $1.name) }
        return result
    }

    private static func buildRules(
        _ entries: [Entry<ProcessDefinition>], stacks: [String: StackInfo],
        matchers: [String: Matcher], issues: inout [String]
    ) -> [ProcessRule] {
        var ordered: [(fallback: Int, order: Int, index: Int, rule: ProcessRule)] = []
        for (index, entry) in entries.enumerated() where entry.definition.disabled != true {
            let definition = entry.definition
            let context = "\(entry.source) › processes.\(definition.id)"
            var problems: [String] = []

            if definition.name.values.isEmpty { problems.append("name is empty") }
            if definition.match.isEmpty { problems.append("'match' is empty and would match every process") }
            for missing in definition.match.references where matchers[missing] == nil {
                problems.append("matcher '\(missing)' not found")
            }
            let limbo = ProcessRules.limboPolicy(from: definition.limbo)
            if let problem = limbo.problem { problems.append(problem) }
            if let run = definition.stop?.run, run.isEmpty || run.contains(where: \.isEmpty) {
                problems.append("stop.run needs at least one non-empty command")
            }
            guard problems.isEmpty, let policy = limbo.policy, let stack = stacks[entry.stackID] else {
                issues += problems.map { "\(context): \($0)" }
                continue
            }

            let matcher = definition.match
            let rule = ProcessRule(
                id: definition.id,
                title: definition.name.text,
                detail: definition.description?.text ?? "",
                stack: stack,
                limbo: policy,
                stop: definition.stop.map { .commandsThenSignal($0.run) } ?? .signal,
                suggestEvenIfSmall: definition.suggestEvenIfSmall ?? false,
                suggestWhenMemoryTight: definition.suggestWhenMemoryTight ?? false
            ) { process, hasPorts in
                matcher.matches(process, hasPorts: hasPorts, refs: matchers)
            }
            ordered.append((definition.fallback == true ? 1 : 0, stack.order, index, rule))
        }
        // First match wins: stack order, then file order; fallbacks are tried last.
        return ordered.sorted { ($0.fallback, $0.order, $0.index) < ($1.fallback, $1.order, $1.index) }.map(\.rule)
    }

    private static func buildStorage(
        _ entries: [Entry<StorageDefinition>], stacks: [String: StackInfo], issues: inout [String]
    ) -> [StorageSpec] {
        var specs: [StorageSpec] = []
        for entry in entries where entry.definition.disabled != true {
            let definition = entry.definition
            let context = "\(entry.source) › storage.\(definition.id)"
            var problems: [String] = []

            if definition.name.values.isEmpty { problems.append("name is empty") }
            let risk = Risk(rawValue: definition.risk)
            if risk == nil { problems.append("risk must be safe, redownload or data_loss") }

            let sources = [definition.paths != nil, definition.project != nil, definition.provider != nil].filter { $0 }.count
            if sources == 0 { problems.append("define paths, project or provider") }
            if let provider = definition.provider, !StorageProviders.names.contains(provider) {
                problems.append("unknown provider '\(provider)' (available: \(StorageProviders.names.sorted().joined(separator: ", ")))")
            }

            for spec in definition.paths ?? [] {
                if !(spec.glob.hasPrefix("~/") || spec.glob.hasPrefix("${")) {
                    problems.append("path '\(spec.glob)' must start with ~/ or ${VAR:-~/...}; absolute paths are not allowed")
                }
                for pattern in [spec.nameMatches, spec.versionPattern].compactMap({ $0 })
                where (try? NSRegularExpression(pattern: pattern)) == nil {
                    problems.append("invalid regular expression '\(pattern)'")
                }
                if let sort = spec.sortBy, !["modified", "version"].contains(sort) {
                    problems.append("sort_by must be modified or version")
                }
                if spec.keepNewest != nil && spec.onlyNewest != nil {
                    problems.append("use keep_newest or only_newest, not both")
                }
            }

            if let project = definition.project {
                if project.markers.isEmpty || project.paths.isEmpty { problems.append("project needs markers and paths") }
                if project.paths.contains(where: { $0.hasPrefix("/") || $0.hasPrefix("~") || $0.contains("..") }) {
                    problems.append("project.paths must be relative to the project folder")
                }
                if let activity = project.activity, !["active", "inactive", "any"].contains(activity) {
                    problems.append("project.activity must be active, inactive or any")
                }
            }

            var method = CleanMethod.delete
            switch definition.method ?? (definition.run != nil ? "run" : "delete") {
            case "delete":
                method = .delete
            case "trash":
                method = .trash
            case "run":
                if let run = definition.run, !run.isEmpty, !run.contains(where: \.isEmpty) {
                    method = .commands(run, thenDelete: definition.thenDelete ?? false)
                } else {
                    problems.append("method run needs a non-empty 'run' list of commands")
                }
            default:
                problems.append("method must be delete, trash or run")
            }

            guard problems.isEmpty, let risk, let stack = stacks[entry.stackID] else {
                issues += problems.map { "\(context): \($0)" }
                continue
            }
            specs.append(StorageSpec(definition: definition, stack: stack, risk: risk, method: method))
        }
        return specs
    }

    private static func hasCycle(from start: String, _ matchers: [String: Matcher]) -> Bool {
        var pending = matchers[start]?.references ?? []
        var visited = Set<String>()
        while let name = pending.popLast() {
            if name == start { return true }
            guard visited.insert(name).inserted else { continue }
            pending += matchers[name]?.references ?? []
        }
        return false
    }

    static func describe(_ error: Error) -> String {
        func path(_ keys: [CodingKey]) -> String {
            let joined = keys.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
            return joined.hasPrefix(".") ? String(joined.dropFirst()) : joined
        }
        switch error as? DecodingError {
        case .keyNotFound(let key, let context)?:
            return "missing '\(key.stringValue)' at \(path(context.codingPath))"
        case .typeMismatch(_, let context)?, .valueNotFound(_, let context)?, .dataCorrupted(let context)?:
            return "\(context.debugDescription) at \(path(context.codingPath))"
        default:
            return "\(error)"
        }
    }
}
