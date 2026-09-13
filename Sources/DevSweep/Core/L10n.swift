import Foundation
import Yams

/// UI translations loaded from `locales/<language>.yaml`. Missing keys fall back to English.
final class L10n: @unchecked Sendable {
    static let shared = L10n()
    static let fallbackLanguage = "en"

    private let lock = NSLock()
    private var tables: [String: [String: String]] = [:]
    private var current = fallbackLanguage
    private var loaded = false

    static func defaultDirectories() -> [URL] {
        [
            ResourceLocator.directory(named: "locales", environmentKey: "DEVSWEEP_LOCALES_DIR"),
            ResourceLocator.userDirectory(named: "locales"),
        ].compactMap { $0 }
    }

    func reload(directories: [URL] = L10n.defaultDirectories(), preference: String = Prefs.languagePreference) {
        lock.lock()
        defer { lock.unlock() }
        load(directories: directories, preference: preference)
    }

    var language: String {
        withTables { _ in current }
    }

    /// Languages with a locale file, named in their own language (`_name`).
    var availableLanguages: [(code: String, name: String)] {
        withTables { tables in
            tables.map { (code: $0.key, name: $0.value["_name"] ?? $0.key) }.sorted { $0.name < $1.name }
        }
    }

    func string(_ key: String) -> String? {
        withTables { tables in tables[current]?[key] ?? tables[Self.fallbackLanguage]?[key] }
    }

    /// Chooses the best variant of a text defined inline in a stack file.
    func pick(_ values: [String: String]) -> String {
        withTables { _ in
            if let exact = values[current] { return exact }
            let language = Self.baseLanguage(current)
            if let sibling = values.keys.sorted().first(where: { Self.baseLanguage($0) == language }) {
                return values[sibling] ?? ""
            }
            return values[Self.fallbackLanguage] ?? values.keys.sorted().first.flatMap { values[$0] } ?? ""
        }
    }

    static func bestLanguage(available: Set<String>, preferred: [String]) -> String {
        let byLowercase = Dictionary(available.map { ($0.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        for identifier in preferred {
            let normalized = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
            if let exact = byLowercase[normalized] { return exact }
            let language = baseLanguage(normalized)
            if let plain = byLowercase[language] { return plain }
            if let regional = available.sorted().first(where: { baseLanguage($0.lowercased()) == language }) { return regional }
        }
        return available.contains(fallbackLanguage) ? fallbackLanguage : (available.sorted().first ?? fallbackLanguage)
    }

    private static func baseLanguage(_ code: String) -> String {
        String(code.split(separator: "-").first ?? Substring(code)).lowercased()
    }

    private func withTables<T>(_ body: ([String: [String: String]]) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        if !loaded { load(directories: Self.defaultDirectories(), preference: Prefs.languagePreference) }
        return body(tables)
    }

    private func load(directories: [URL], preference: String) {
        var result: [String: [String: String]] = [:]
        for directory in directories {
            for file in ResourceLocator.yamlFiles(in: directory) {
                let code = file.deletingPathExtension().lastPathComponent
                // Read raw scalars so values like "No" or "On" stay text instead of becoming booleans.
                guard let text = try? String(contentsOf: file, encoding: .utf8),
                      let node = try? Yams.compose(yaml: text), let mapping = node.mapping else { continue }
                for (key, value) in mapping {
                    guard let key = key.string, let value = value.string else { continue }
                    result[code, default: [:]][key] = value
                }
            }
        }
        tables = result
        current = preference != "system" && result[preference] != nil
            ? preference
            : Self.bestLanguage(available: Set(result.keys), preferred: Locale.preferredLanguages)
        loaded = true
    }
}

/// Translated UI text; `{name}` placeholders are replaced by `arguments`.
func tr(_ key: String, _ arguments: [String: Any] = [:]) -> String {
    var text = L10n.shared.string(key) ?? key
    for (name, value) in arguments {
        text = text.replacingOccurrences(of: "{\(name)}", with: "\(value)")
    }
    return text
}

/// Like `tr`, but uses `<key>.one` for a count of 1 when the language defines it.
func tr(_ key: String, count: Int, _ arguments: [String: Any] = [:]) -> String {
    var all = arguments
    all["count"] = count
    if count == 1, L10n.shared.string(key + ".one") != nil {
        return tr(key + ".one", all)
    }
    return tr(key, all)
}
