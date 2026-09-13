import Foundation
import Yams

/// Flags keys the decoder would silently ignore, so a typo in a contribution fails loudly.
enum SchemaLint {
    static func check(yaml: String) -> [String] {
        guard let root = try? Yams.compose(yaml: yaml) else { return [] }
        var issues: [String] = []

        // `x-` keys are free for YAML anchors and notes.
        let topLevel = keys(root).filter { !$0.hasPrefix("x-") }
        unknown(topLevel, allowed: ["stack", "matchers", "processes", "storage"], at: "file", &issues)
        if let stack = value(root, "stack") {
            unknown(keys(stack), allowed: StackHeader.CodingKeys.names, at: "stack", &issues)
        }
        for (name, matcher) in pairs(value(root, "matchers")) {
            checkMatcher(matcher, at: "matchers.\(name)", &issues)
        }

        for (index, process) in items(value(root, "processes")).enumerated() {
            let at = "processes.\(value(process, "id")?.string ?? String(index))"
            unknown(keys(process), allowed: ProcessDefinition.CodingKeys.names, at: at, &issues)
            if let match = value(process, "match") { checkMatcher(match, at: at + ".match", &issues) }
            if let limbo = value(process, "limbo"), limbo.mapping != nil {
                unknown(keys(limbo), allowed: LimboDefinition.CodingKeys.names, at: at + ".limbo", &issues)
            }
            if let stop = value(process, "stop") {
                unknown(keys(stop), allowed: StopDefinition.CodingKeys.names, at: at + ".stop", &issues)
            }
        }

        for (index, item) in items(value(root, "storage")).enumerated() {
            let at = "storage.\(value(item, "id")?.string ?? String(index))"
            unknown(keys(item), allowed: StorageDefinition.CodingKeys.names, at: at, &issues)
            for (pathIndex, path) in items(value(item, "paths")).enumerated() where path.mapping != nil {
                let pathAt = "\(at).paths[\(pathIndex)]"
                unknown(keys(path), allowed: PathSpec.CodingKeys.names, at: pathAt, &issues)
                for key in ["file_contains", "file_not_contains"] {
                    if let check = value(path, key) {
                        unknown(keys(check), allowed: FileCheck.CodingKeys.names, at: "\(pathAt).\(key)", &issues)
                    }
                }
            }
            if let project = value(item, "project") {
                unknown(keys(project), allowed: ProjectSpec.CodingKeys.names, at: at + ".project", &issues)
            }
        }
        return issues
    }

    private static func checkMatcher(_ node: Node, at: String, _ issues: inout [String]) {
        unknown(keys(node), allowed: Matcher.CodingKeys.names, at: at, &issues)
        for key in ["any", "all", "none"] {
            for (index, child) in items(value(node, key)).enumerated() {
                checkMatcher(child, at: "\(at).\(key)[\(index)]", &issues)
            }
        }
    }

    private static func unknown(_ keys: [String], allowed: [String], at: String, _ issues: inout [String]) {
        for key in keys where !allowed.contains(key) {
            let closest = allowed.min { distance(key, $0) < distance(key, $1) }
            let hint = closest.flatMap { distance(key, $0) <= 3 ? " (did you mean '\($0)'?)" : nil } ?? ""
            issues.append("unknown key '\(key)' in \(at)\(hint)")
        }
    }

    private static func pairs(_ node: Node?) -> [(String, Node)] {
        guard let mapping = node?.mapping else { return [] }
        return mapping.compactMap { element in element.key.string.map { ($0, element.value) } }
    }

    private static func keys(_ node: Node) -> [String] {
        pairs(node).map(\.0)
    }

    private static func value(_ node: Node?, _ key: String) -> Node? {
        pairs(node).first { $0.0 == key }?.1
    }

    private static func items(_ node: Node?) -> [Node] {
        node?.sequence.map { Array($0) } ?? []
    }

    /// Levenshtein distance, for "did you mean" hints.
    static func distance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs), b = Array(rhs)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
            }
            previous = current
        }
        return previous[b.count]
    }
}
