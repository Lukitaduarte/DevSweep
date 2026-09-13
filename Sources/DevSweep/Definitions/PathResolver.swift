import Foundation

enum PathTemplate {
    /// Expands `${VAR:-default}`, `{a,b}` alternatives and `~`.
    static func expand(_ template: String, environment: [String: String] = ProcessInfo.processInfo.environment) -> [String] {
        braces(substituteEnvironment(template, environment: environment)).map(expandTilde)
    }

    static func substituteEnvironment(_ text: String, environment: [String: String]) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\$\{([A-Za-z_][A-Za-z0-9_]*)(?::-([^}]*))?\}"#) else { return text }
        var result = text
        // Replace back to front so earlier ranges stay valid.
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let nameRange = Range(match.range(at: 1), in: text), let whole = Range(match.range, in: result) else { continue }
            let fallback = Range(match.range(at: 2), in: text).map { String(text[$0]) } ?? ""
            let value = environment[String(text[nameRange])].flatMap { $0.isEmpty ? nil : $0 } ?? fallback
            result.replaceSubrange(whole, with: value)
        }
        return result
    }

    static func braces(_ text: String) -> [String] {
        guard let open = text.firstIndex(of: "{"),
              let close = text[open...].firstIndex(of: "}") else { return [text] }
        let inner = text[text.index(after: open)..<close]
        guard inner.contains(",") else { return [text] }
        let prefix = text[..<open]
        let suffix = text[text.index(after: close)...]
        return inner.split(separator: ",", omittingEmptySubsequences: false).flatMap { option in
            braces(String(prefix) + option + String(suffix))
        }
    }
}

enum PathResolver {
    static func resolve(_ spec: PathSpec, now: Date = Date()) -> [URL] {
        var urls = PathTemplate.expand(spec.glob).flatMap { PathGlob.expand($0, excluding: Set(spec.exclude ?? [])) }

        if let pattern = spec.nameMatches {
            urls = urls.filter { $0.lastPathComponent.range(of: pattern, options: .regularExpression) != nil }
        }
        if let days = spec.olderThanDays {
            let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
            urls = urls.filter { (PathGlob.modificationDate($0) ?? now) < cutoff }
        }
        if let check = spec.fileContains {
            urls = urls.filter { contains($0, check) }
        }
        if let check = spec.fileNotContains {
            urls = urls.filter { !contains($0, check) }
        }

        guard let count = spec.keepNewest ?? spec.onlyNewest else { return urls }
        let newest: Set<URL>
        if spec.sortBy == "version" {
            // Group by version so e.g. gradle-8.14-all and gradle-8.14-bin count as one.
            let key = { (url: URL) in versionKey(url.lastPathComponent, pattern: spec.versionPattern) }
            let versions = Set(urls.map(key)).sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            let top = Set(versions.prefix(count))
            newest = Set(urls.filter { top.contains(key($0)) })
        } else {
            let sorted = urls.sorted {
                (PathGlob.modificationDate($0) ?? .distantPast) > (PathGlob.modificationDate($1) ?? .distantPast)
            }
            newest = Set(sorted.prefix(count))
        }
        return spec.keepNewest != nil ? urls.filter { !newest.contains($0) } : urls.filter { newest.contains($0) }
    }

    /// First capture group of `pattern` (or the whole match); defaults to the first dotted number.
    static func versionKey(_ name: String, pattern: String?) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern ?? #"\d+(?:\.\d+)+"#),
              let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) else { return name }
        let group = match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound ? 1 : 0
        return Range(match.range(at: group), in: name).map { String(name[$0]) } ?? name
    }

    private static func contains(_ url: URL, _ check: FileCheck) -> Bool {
        let text = (try? String(contentsOf: url.appendingPathComponent(check.file), encoding: .utf8)) ?? ""
        return text.localizedCaseInsensitiveContains(check.text)
    }
}
