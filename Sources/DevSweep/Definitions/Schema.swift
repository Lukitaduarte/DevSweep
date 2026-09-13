import Foundation

// Decodable shape of `stacks/*.yaml`. CONTRIBUTING.md documents every key.

/// User-facing text: a plain string (English) or a map of language code to text.
struct LocalizedText: Decodable, Sendable {
    let values: [String: String]

    init(_ values: [String: String]) {
        self.values = values
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let plain = try? container.decode(String.self) {
            values = [L10n.fallbackLanguage: plain]
        } else {
            values = try container.decode([String: String].self)
        }
    }

    var text: String { L10n.shared.pick(values) }
}

/// Sizes such as `500MB` or `2GB` (decimal units, like Finder). Plain numbers are bytes.
struct ByteSize: Decodable, Sendable {
    let bytes: Int64

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Int64.self) {
            bytes = number
            return
        }
        let text = try container.decode(String.self)
        guard let parsed = ByteSize.parse(text) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "invalid size '\(text)', use something like 500MB or 2GB"
            )
        }
        bytes = parsed
    }

    static func parse(_ text: String) -> Int64? {
        let value = text.trimmingCharacters(in: .whitespaces).uppercased()
        let units: [(String, Double)] = [("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("KB", 1e3), ("B", 1)]
        for (suffix, multiplier) in units where value.hasSuffix(suffix) {
            guard let number = Double(value.dropLast(suffix.count).trimmingCharacters(in: .whitespaces)) else { return nil }
            return Int64(number * multiplier)
        }
        return Int64(value)
    }
}

struct StackFile: Decodable {
    let stack: StackHeader
    let matchers: [String: Matcher]?
    let processes: [ProcessDefinition]?
    let storage: [StorageDefinition]?
}

struct StackHeader: Decodable, Sendable {
    let id: String
    let name: LocalizedText
    let icon: String?
    let order: Int?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, name, icon, order
    }
}

struct ProcessDefinition: Decodable, Sendable {
    let id: String
    let name: LocalizedText
    let description: LocalizedText?
    let match: Matcher
    let limbo: LimboDefinition?
    let stop: StopDefinition?
    let fallback: Bool?
    let suggestEvenIfSmall: Bool?
    let suggestWhenMemoryTight: Bool?
    let disabled: Bool?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, name, description, match, limbo, stop, fallback, disabled
        case suggestEvenIfSmall = "suggest_even_if_small"
        case suggestWhenMemoryTight = "suggest_when_memory_tight"
    }
}

/// `limbo: orphan` or `limbo: { when: idle, minutes: 20, max_cpu: 1 }`.
struct LimboDefinition: Decodable, Sendable {
    let when: String
    let minutes: Double?
    let maxCPU: Double?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case when, minutes
        case maxCPU = "max_cpu"
    }

    init(from decoder: Decoder) throws {
        if let plain = try? decoder.singleValueContainer().decode(String.self) {
            when = plain
            minutes = nil
            maxCPU = nil
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        when = try container.decode(String.self, forKey: .when)
        minutes = try container.decodeIfPresent(Double.self, forKey: .minutes)
        maxCPU = try container.decodeIfPresent(Double.self, forKey: .maxCPU)
    }
}

struct StopDefinition: Decodable, Sendable {
    let run: [[String]]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case run
    }
}

struct StorageDefinition: Decodable, Sendable {
    let id: String
    let name: LocalizedText
    let description: LocalizedText?
    let risk: String
    let paths: [PathSpec]?
    let project: ProjectSpec?
    let provider: String?
    let providerOptions: [String: [String]]?
    let method: String?
    let run: [[String]]?
    let thenDelete: Bool?
    let stopProcesses: [String]?
    let autoSuggest: Bool?
    let suggestAbove: ByteSize?
    let requiresPath: String?
    let disabled: Bool?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, name, description, risk, paths, project, provider, method, run, disabled
        case providerOptions = "provider_options"
        case thenDelete = "then_delete"
        case stopProcesses = "stop_processes"
        case autoSuggest = "auto_suggest"
        case suggestAbove = "suggest_above"
        case requiresPath = "requires_path"
    }
}

/// A glob, optionally narrowed by filters. A plain string is just the glob.
struct PathSpec: Decodable, Sendable {
    let glob: String
    let exclude: [String]?
    let nameMatches: String?
    let olderThanDays: Int?
    let keepNewest: Int?
    let onlyNewest: Int?
    let sortBy: String?
    let versionPattern: String?
    let fileContains: FileCheck?
    let fileNotContains: FileCheck?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case glob, exclude
        case nameMatches = "name_matches"
        case olderThanDays = "older_than_days"
        case keepNewest = "keep_newest"
        case onlyNewest = "only_newest"
        case sortBy = "sort_by"
        case versionPattern = "version_pattern"
        case fileContains = "file_contains"
        case fileNotContains = "file_not_contains"
    }

    init(glob: String, keepNewest: Int? = nil, onlyNewest: Int? = nil, sortBy: String? = nil, versionPattern: String? = nil) {
        self.glob = glob
        self.exclude = nil
        self.nameMatches = nil
        self.olderThanDays = nil
        self.keepNewest = keepNewest
        self.onlyNewest = onlyNewest
        self.sortBy = sortBy
        self.versionPattern = versionPattern
        self.fileContains = nil
        self.fileNotContains = nil
    }

    init(from decoder: Decoder) throws {
        if let plain = try? decoder.singleValueContainer().decode(String.self) {
            glob = plain
            exclude = nil
            nameMatches = nil
            olderThanDays = nil
            keepNewest = nil
            onlyNewest = nil
            sortBy = nil
            versionPattern = nil
            fileContains = nil
            fileNotContains = nil
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        glob = try container.decode(String.self, forKey: .glob)
        exclude = try container.decodeIfPresent([String].self, forKey: .exclude)
        nameMatches = try container.decodeIfPresent(String.self, forKey: .nameMatches)
        olderThanDays = try container.decodeIfPresent(Int.self, forKey: .olderThanDays)
        keepNewest = try container.decodeIfPresent(Int.self, forKey: .keepNewest)
        onlyNewest = try container.decodeIfPresent(Int.self, forKey: .onlyNewest)
        sortBy = try container.decodeIfPresent(String.self, forKey: .sortBy)
        versionPattern = try container.decodeIfPresent(String.self, forKey: .versionPattern)
        fileContains = try container.decodeIfPresent(FileCheck.self, forKey: .fileContains)
        fileNotContains = try container.decodeIfPresent(FileCheck.self, forKey: .fileNotContains)
    }
}

struct FileCheck: Decodable, Sendable {
    let file: String
    let text: String

    enum CodingKeys: String, CodingKey, CaseIterable {
        case file, text
    }
}

struct ProjectSpec: Decodable, Sendable {
    let markers: [String]
    let activity: String?
    let activityFiles: [String]?
    let paths: [String]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case markers, activity, paths
        case activityFiles = "activity_files"
    }
}

extension CodingKey where Self: CaseIterable {
    static var names: [String] { allCases.map(\.stringValue) }
}
