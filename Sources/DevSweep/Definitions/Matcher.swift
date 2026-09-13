import Foundation

/// Declarative process matcher. Every key present must match (AND);
/// within a list, any item may match (OR). A single string counts as a one-item list.
struct Matcher: Decodable, Sendable {
    var exeName: [String]?
    var exeNamePrefix: [String]?
    var exePathContains: [String]?
    var commandContains: [String]?
    var commandPrefix: [String]?
    var hasPorts: Bool?
    var userTool: Bool?
    var ref: String?
    var any: [Matcher]?
    var all: [Matcher]?
    var none: [Matcher]?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case exeName = "exe_name"
        case exeNamePrefix = "exe_name_prefix"
        case exePathContains = "exe_path_contains"
        case commandContains = "command_contains"
        case commandPrefix = "command_prefix"
        case hasPorts = "has_ports"
        case userTool = "user_tool"
        case ref, any, all, none
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func list(_ key: CodingKeys) throws -> [String]? {
            if let single = try? container.decodeIfPresent(String.self, forKey: key) { return [single] }
            return try container.decodeIfPresent([String].self, forKey: key)
        }
        exeName = try list(.exeName)
        exeNamePrefix = try list(.exeNamePrefix)
        exePathContains = try list(.exePathContains)
        commandContains = try list(.commandContains)
        commandPrefix = try list(.commandPrefix)
        hasPorts = try container.decodeIfPresent(Bool.self, forKey: .hasPorts)
        userTool = try container.decodeIfPresent(Bool.self, forKey: .userTool)
        ref = try container.decodeIfPresent(String.self, forKey: .ref)
        any = try container.decodeIfPresent([Matcher].self, forKey: .any)
        all = try container.decodeIfPresent([Matcher].self, forKey: .all)
        none = try container.decodeIfPresent([Matcher].self, forKey: .none)
    }

    var isEmpty: Bool {
        [exeName, exeNamePrefix, exePathContains, commandContains, commandPrefix].allSatisfy { $0 == nil }
            && hasPorts == nil && userTool == nil && ref == nil && any == nil && all == nil && none == nil
    }

    /// Names of shared matchers used anywhere in this matcher.
    var references: [String] {
        [ref].compactMap { $0 } + [any, all, none].compactMap { $0 }.flatMap { $0.flatMap(\.references) }
    }

    func matches(_ process: ProcInfo, hasPorts ports: Bool, refs: [String: Matcher], depth: Int = 0) -> Bool {
        guard depth < 16 else { return false }
        if let names = exeName, !names.contains(process.exeName) { return false }
        if let prefixes = exeNamePrefix, !prefixes.contains(where: { process.exeName.hasPrefix($0) }) { return false }
        if let needles = exePathContains, !needles.contains(where: { process.exePath.contains($0) }) { return false }
        if let needles = commandContains, !needles.contains(where: { process.command.contains($0) }) { return false }
        if let prefixes = commandPrefix, !prefixes.contains(where: { process.command.hasPrefix($0) }) { return false }
        if let expected = hasPorts, expected != ports { return false }
        if let expected = userTool, expected != ProcessRules.isUserTool(process) { return false }

        let child = { (matcher: Matcher) in matcher.matches(process, hasPorts: ports, refs: refs, depth: depth + 1) }
        if let name = ref {
            guard let shared = refs[name], child(shared) else { return false }
        }
        if let options = any, !options.contains(where: child) { return false }
        if let required = all, !required.allSatisfy(child) { return false }
        if let excluded = none, excluded.contains(where: child) { return false }
        return true
    }
}
