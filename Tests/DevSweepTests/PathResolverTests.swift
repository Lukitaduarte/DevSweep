import XCTest
import Yams
@testable import DevSweep

final class PathResolverEdgeTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = try TestSupport.temporaryDirectory()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func makeFolder(_ name: String, modified: Date? = nil) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
        return url
    }

    private func spec(
        _ glob: String, exclude: [String]? = nil, nameMatches: String? = nil, olderThanDays: Int? = nil,
        keepNewest: Int? = nil, onlyNewest: Int? = nil, sortBy: String? = nil,
        fileContains: FileCheck? = nil, fileNotContains: FileCheck? = nil
    ) throws -> PathSpec {
        var yaml = "glob: \"\(glob)\"\n"
        if let exclude { yaml += "exclude: [\(exclude.joined(separator: ", "))]\n" }
        if let nameMatches { yaml += "name_matches: '\(nameMatches)'\n" }
        if let olderThanDays { yaml += "older_than_days: \(olderThanDays)\n" }
        if let keepNewest { yaml += "keep_newest: \(keepNewest)\n" }
        if let onlyNewest { yaml += "only_newest: \(onlyNewest)\n" }
        if let sortBy { yaml += "sort_by: \(sortBy)\n" }
        if let fileContains { yaml += "file_contains: { file: \(fileContains.file), text: \(fileContains.text) }\n" }
        if let fileNotContains { yaml += "file_not_contains: { file: \(fileNotContains.file), text: \(fileNotContains.text) }\n" }
        return try YAMLDecoder().decode(PathSpec.self, from: yaml)
    }

    func testNameMatchesFiltersByRegularExpression() throws {
        for name in ["8.12", "8.14", "build-cache-1", "modules-2"] { try makeFolder(name) }
        let resolved = PathResolver.resolve(try spec(root.path + "/*", nameMatches: #"^\d+(\.\d+)+$"#))
        XCTAssertEqual(Set(resolved.map(\.lastPathComponent)), ["8.12", "8.14"])
    }

    func testOlderThanDaysUsesModificationTime() throws {
        try makeFolder("old", modified: Date().addingTimeInterval(-120 * 86_400))
        try makeFolder("new", modified: Date())
        let resolved = PathResolver.resolve(try spec(root.path + "/*", olderThanDays: 90))
        XCTAssertEqual(resolved.map(\.lastPathComponent), ["old"])
    }

    func testKeepAndOnlyNewestByModificationTime() throws {
        try makeFolder("first", modified: Date().addingTimeInterval(-3 * 86_400))
        try makeFolder("second", modified: Date().addingTimeInterval(-2 * 86_400))
        try makeFolder("third", modified: Date())

        let old = PathResolver.resolve(try spec(root.path + "/*", keepNewest: 1))
        XCTAssertEqual(Set(old.map(\.lastPathComponent)), ["first", "second"])
        let newest = PathResolver.resolve(try spec(root.path + "/*", onlyNewest: 2))
        XCTAssertEqual(Set(newest.map(\.lastPathComponent)), ["second", "third"])
    }

    func testFileContainsAndFileNotContains() throws {
        let withRemote = try makeFolder("public-specs")
        let withoutRemote = try makeFolder("private-specs")
        try FileManager.default.createDirectory(at: withRemote.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: withoutRemote.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try "url = https://github.com/CocoaPods/Specs.git".write(
            to: withRemote.appendingPathComponent(".git/config"), atomically: true, encoding: .utf8
        )
        try "url = https://example.invalid/internal.git".write(
            to: withoutRemote.appendingPathComponent(".git/config"), atomically: true, encoding: .utf8
        )

        let check = FileCheck(file: ".git/config", text: "github.com/CocoaPods/Specs")
        XCTAssertEqual(
            PathResolver.resolve(try spec(root.path + "/*", fileContains: check)).map(\.lastPathComponent),
            ["public-specs"]
        )
        XCTAssertEqual(
            PathResolver.resolve(try spec(root.path + "/*", fileNotContains: check)).map(\.lastPathComponent),
            ["private-specs"]
        )
    }

    func testExcludeDropsNamedEntries() throws {
        for name in ["Build", "Index.noindex"] { try makeFolder(name) }
        let resolved = PathResolver.resolve(try spec(root.path + "/*", exclude: ["Index.noindex"]))
        XCTAssertEqual(resolved.map(\.lastPathComponent), ["Build"])
    }

    func testUnmatchedGlobsAndMissingVersionsDegradeGracefully() throws {
        XCTAssertTrue(PathResolver.resolve(try spec(root.path + "/nothing/*")).isEmpty)
        // Names without a dotted number fall back to the name itself as the version key.
        try makeFolder("stable")
        try makeFolder("beta")
        let kept = PathResolver.resolve(try spec(root.path + "/*", keepNewest: 1, sortBy: "version"))
        XCTAssertEqual(kept.map(\.lastPathComponent), ["beta"])
    }

    func testVersionKeyExtraction() {
        XCTAssertEqual(PathResolver.versionKey("gradle-8.14-all", pattern: nil), "8.14")
        XCTAssertEqual(PathResolver.versionKey("18.2 (22C152)", pattern: nil), "18.2")
        XCTAssertEqual(PathResolver.versionKey("plain", pattern: nil), "plain")
        XCTAssertEqual(PathResolver.versionKey("toolchain@v0.0.1-go1.25.1", pattern: #"go(\d+(?:\.\d+)+)"#), "1.25.1")
        XCTAssertEqual(PathResolver.versionKey("no-match", pattern: #"go(\d+)"#), "no-match")
        XCTAssertEqual(PathResolver.versionKey("x", pattern: "([invalid"), "x")
    }

    func testEnvironmentSubstitutionEdgeCases() {
        XCTAssertEqual(PathTemplate.substituteEnvironment("~/plain", environment: [:]), "~/plain")
        XCTAssertEqual(PathTemplate.substituteEnvironment("${A}/x", environment: [:]), "/x")
        XCTAssertEqual(PathTemplate.substituteEnvironment("${A:-d}/x", environment: ["A": ""]), "d/x")
        XCTAssertEqual(
            PathTemplate.substituteEnvironment("${A:-a}/${B:-b}", environment: ["B": "bb"]),
            "a/bb"
        )
    }

    func testBraceExpansion() {
        XCTAssertEqual(PathTemplate.braces("/a/b"), ["/a/b"])
        XCTAssertEqual(PathTemplate.braces("/a/{only}/b"), ["/a/{only}/b"], "a group without a comma is left alone")
        XCTAssertEqual(PathTemplate.braces("/{x,y}"), ["/x", "/y"])
        XCTAssertEqual(PathTemplate.expand("~/{a,b}").count, 2)
        XCTAssertTrue(PathTemplate.expand("~/x")[0].hasPrefix(NSHomeDirectory()))
    }

    func testPathGlobHelpers() throws {
        let folder = try makeFolder("child")
        XCTAssertEqual(PathGlob.children(of: root).map(\.lastPathComponent), ["child"])
        XCTAssertTrue(PathGlob.children(of: root.appendingPathComponent("missing")).isEmpty)
        XCTAssertNotNil(PathGlob.modificationDate(folder))
        XCTAssertNil(PathGlob.modificationDate(root.appendingPathComponent("missing")))
        XCTAssertTrue(PathGlob.expand("relative/path").isEmpty)

        // A dangling symlink still "exists" for cleanup purposes.
        let link = root.appendingPathComponent("dangling")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root.appendingPathComponent("gone"))
        XCTAssertTrue(PathGlob.exists(link.path))
        XCTAssertFalse(PathGlob.exists(root.appendingPathComponent("nope").path))
    }
}
