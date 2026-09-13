import XCTest
import Yams
@testable import DevSweep

/// Guards contributions to `locales/`.
final class LocalizationTests: XCTestCase {
    override func tearDown() {
        TestSupport.useEnglish()
    }

    private func table(_ file: URL) throws -> [String: String] {
        let node = try XCTUnwrap(try Yams.compose(yaml: String(contentsOf: file, encoding: .utf8)))
        var result: [String: String] = [:]
        for (key, value) in try XCTUnwrap(node.mapping) {
            if let key = key.string, let value = value.string { result[key] = value }
        }
        return result
    }

    private func placeholders(_ text: String) -> Set<String> {
        let regex = try! NSRegularExpression(pattern: #"\{[a-z_]+\}"#)
        return Set(regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        })
    }

    func testEveryLocaleMatchesEnglishKeysAndPlaceholders() throws {
        let english = try table(TestSupport.localesDirectory.appendingPathComponent("en.yaml"))
        let required = Set(english.keys.filter { !$0.hasSuffix(".one") })
        for file in ResourceLocator.yamlFiles(in: TestSupport.localesDirectory) where file.lastPathComponent != "en.yaml" {
            let locale = try table(file)
            let name = file.lastPathComponent
            XCTAssertEqual(required.subtracting(locale.keys).sorted(), [], "\(name) is missing keys")
            XCTAssertEqual(Set(locale.keys).subtracting(english.keys).sorted(), [], "\(name) has keys that en.yaml doesn't")
            for (key, value) in locale {
                guard let reference = english[key] ?? english[key.replacingOccurrences(of: ".one", with: "")] else { continue }
                let expected = placeholders(reference).subtracting(key.hasSuffix(".one") ? ["{count}"] : [])
                XCTAssertTrue(expected.isSubset(of: placeholders(value)) || key.hasSuffix(".one"),
                              "\(name) › \(key) must keep \(expected.sorted())")
            }
        }
    }

    func testEveryKeyUsedInSourcesExists() throws {
        let english = try table(TestSupport.localesDirectory.appendingPathComponent("en.yaml"))
        let regex = try NSRegularExpression(pattern: #"\btr\(\s*"([A-Za-z0-9_.]+)""#)
        let sources = TestSupport.root.appendingPathComponent("Sources")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var missing: [String] = []
        while let file = enumerator.nextObject() as? URL {
            guard file.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range(at: 1), in: text) else { continue }
                let key = String(text[range])
                if english[key] == nil { missing.append("\(file.lastPathComponent): \(key)") }
            }
        }
        XCTAssertEqual(missing, [])
    }

    func testBestLanguagePrefersExactThenLanguageThenEnglish() {
        let available: Set<String> = ["en", "pt-BR", "es"]
        XCTAssertEqual(L10n.bestLanguage(available: available, preferred: ["pt-BR", "en-US"]), "pt-BR")
        XCTAssertEqual(L10n.bestLanguage(available: available, preferred: ["pt-PT"]), "pt-BR")
        XCTAssertEqual(L10n.bestLanguage(available: available, preferred: ["es-MX"]), "es")
        XCTAssertEqual(L10n.bestLanguage(available: available, preferred: ["fr-FR", "de"]), "en")
    }

    func testMissingKeysAndStackTextsFallBackToEnglish() throws {
        let directory = try TestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try "greeting: \"Hello\"\nfarewell: \"Bye\"\n".write(to: directory.appendingPathComponent("en.yaml"), atomically: true, encoding: .utf8)
        try "greeting: \"Salut\"\nanswer: No\n".write(to: directory.appendingPathComponent("fr.yaml"), atomically: true, encoding: .utf8)

        L10n.shared.reload(directories: [directory], preference: "fr")
        XCTAssertEqual(tr("greeting"), "Salut")
        XCTAssertEqual(tr("farewell"), "Bye")
        XCTAssertEqual(tr("answer"), "No", "YAML booleans must stay text")
        XCTAssertEqual(LocalizedText(["en": "Cache", "pt-BR": "Cache"]).text, "Cache")
        XCTAssertEqual(LocalizedText(["en": "Cache", "fr-CA": "Cachette"]).text, "Cachette")
    }

    func testPluralForms() {
        TestSupport.useEnglish()
        XCTAssertEqual(tr("banner.errors", count: 1), "1 error")
        XCTAssertEqual(tr("banner.errors", count: 3), "3 errors")
    }
}
