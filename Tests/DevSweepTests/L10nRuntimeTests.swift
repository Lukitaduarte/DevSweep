import XCTest
@testable import DevSweep

/// Language selection and lookup at runtime, using throwaway locale folders.
final class L10nRuntimeTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = try TestSupport.temporaryDirectory()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        TestSupport.useEnglish()
    }

    private func write(_ code: String, _ lines: String, in directory: URL? = nil) throws {
        let folder = directory ?? root!
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try lines.write(to: folder.appendingPathComponent("\(code).yaml"), atomically: true, encoding: .utf8)
    }

    func testPreferenceWinsOverTheSystemLanguage() throws {
        try write("en", "_name: \"English\"\ngreeting: \"Hello\"\n")
        try write("es", "_name: \"Español\"\ngreeting: \"Hola\"\n")

        L10n.shared.reload(directories: [root], preference: "es")
        XCTAssertEqual(L10n.shared.language, "es")
        XCTAssertEqual(tr("greeting"), "Hola")

        // An unknown preference falls back to the system choice, which ends at English here.
        L10n.shared.reload(directories: [root], preference: "de")
        XCTAssertEqual(tr("greeting"), L10n.shared.language == "es" ? "Hola" : "Hello")
    }

    func testAvailableLanguagesUseTheirOwnNames() throws {
        try write("en", "_name: \"English\"\n")
        try write("fr", "_name: \"Français\"\n")
        L10n.shared.reload(directories: [root], preference: "en")

        let languages = L10n.shared.availableLanguages
        XCTAssertEqual(languages.map(\.code).sorted(), ["en", "fr"])
        XCTAssertEqual(languages.first { $0.code == "fr" }?.name, "Français")
    }

    func testLanguageWithoutANameFallsBackToItsCode() throws {
        try write("en", "greeting: \"Hello\"\n")
        L10n.shared.reload(directories: [root], preference: "en")
        XCTAssertEqual(L10n.shared.availableLanguages.first?.name, "en")
    }

    func testPersonalLocalesOverrideBundledOnes() throws {
        let bundled = root.appendingPathComponent("bundled")
        let personal = root.appendingPathComponent("personal")
        try write("en", "_name: \"English\"\ngreeting: \"Hello\"\nkept: \"Kept\"\n", in: bundled)
        try write("en", "greeting: \"Hi there\"\n", in: personal)

        L10n.shared.reload(directories: [bundled, personal], preference: "en")
        XCTAssertEqual(tr("greeting"), "Hi there")
        XCTAssertEqual(tr("kept"), "Kept")
    }

    func testUnknownKeysComeBackAsThemselvesAndArgumentsAreReplaced() throws {
        try write("en", "_name: \"English\"\nwelcome: \"Hi {name}, you have {count} items\"\n")
        L10n.shared.reload(directories: [root], preference: "en")

        XCTAssertEqual(tr("missing.key"), "missing.key")
        XCTAssertEqual(tr("welcome", ["name": "Ana", "count": 3]), "Hi Ana, you have 3 items")
        XCTAssertEqual(tr("welcome", ["name": "Ana"]), "Hi Ana, you have {count} items")
    }

    func testPluralFallsBackToThePluralFormWhenSingularIsMissing() throws {
        try write("en", "_name: \"English\"\nfiles: \"{count} files\"\nboxes: \"{count} boxes\"\nboxes.one: \"one box\"\n")
        L10n.shared.reload(directories: [root], preference: "en")

        XCTAssertEqual(tr("files", count: 1), "1 files")
        XCTAssertEqual(tr("boxes", count: 1), "one box")
        XCTAssertEqual(tr("boxes", count: 4), "4 boxes")
    }

    func testStackTextsPickRegionalVariantsThenEnglish() throws {
        try write("pt-BR", "_name: \"Português\"\n")
        L10n.shared.reload(directories: [root], preference: "pt-BR")

        XCTAssertEqual(LocalizedText(["pt-BR": "Exato", "en": "Exact"]).text, "Exato")
        XCTAssertEqual(LocalizedText(["pt-PT": "Regional", "en": "Exact"]).text, "Regional")
        XCTAssertEqual(LocalizedText(["en": "Only English"]).text, "Only English")
        XCTAssertEqual(LocalizedText(["de": "Nur Deutsch"]).text, "Nur Deutsch", "last resort: whatever exists")
        XCTAssertEqual(LocalizedText([:]).text, "")
    }

    func testEmptyAndUnreadableFoldersLeaveEnglishAsTheFallback() {
        L10n.shared.reload(directories: [root.appendingPathComponent("missing")], preference: "system")
        XCTAssertEqual(L10n.shared.language, "en")
        XCTAssertEqual(tr("anything"), "anything")
    }
}
