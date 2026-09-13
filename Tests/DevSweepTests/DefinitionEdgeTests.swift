import XCTest
import Yams
@testable import DevSweep

/// Validation branches of the loader, plus the small model types it builds.
final class DefinitionEdgeTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        TestSupport.useEnglish()
        directory = try TestSupport.temporaryDirectory()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    @discardableResult
    private func write(_ yaml: String, named name: String = "test.yaml") throws -> Definitions {
        try yaml.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        return DefinitionLoader.load(from: [directory])
    }

    func testInvalidYamlIsReportedWithTheFileName() throws {
        let definitions = try write("stack: [this is not a mapping\n")
        XCTAssertEqual(definitions.fileCount, 0)
        XCTAssertEqual(definitions.issues.count, 1)
        XCTAssertTrue(definitions.issues[0].contains("test.yaml"), definitions.issues[0])
    }

    func testMissingRequiredFieldIsReported() throws {
        let definitions = try write("stack: { name: No id }\n")
        XCTAssertTrue(definitions.issues.contains { $0.contains("missing 'id'") }, "\(definitions.issues)")
    }

    func testDuplicateIdsInTheSameDirectoryAreReported() throws {
        let definitions = try write("""
        stack: { id: dup, name: Dup }
        processes:
          - { id: same, name: One, match: { exe_name: a } }
          - { id: same, name: Two, match: { exe_name: b } }
        storage:
          - { id: s, name: One, risk: safe, paths: [~/a] }
          - { id: s, name: Two, risk: safe, paths: [~/b] }
        """)
        XCTAssertEqual(definitions.issues.filter { $0.contains("duplicate") }.count, 2)
        XCTAssertEqual(definitions.processRules.count, 1)
        XCTAssertEqual(definitions.storage.count, 1)
    }

    func testInvalidLimboAndStopAreReported() throws {
        let definitions = try write("""
        stack: { id: p, name: P }
        processes:
          - { id: a, name: A, match: { exe_name: a }, limbo: sometimes }
          - { id: b, name: B, match: { exe_name: b }, limbo: { when: idle } }
          - { id: c, name: C, match: { exe_name: c }, limbo: { when: orphan_or_older } }
          - { id: d, name: D, match: { exe_name: d }, stop: { run: [] } }
        """)
        let issues = definitions.issues.joined(separator: "\n")
        XCTAssertTrue(issues.contains("limbo must be"), issues)
        XCTAssertTrue(issues.contains("'idle' needs minutes"), issues)
        XCTAssertTrue(issues.contains("'orphan_or_older' needs minutes"), issues)
        XCTAssertTrue(issues.contains("stop.run needs"), issues)
        XCTAssertTrue(definitions.processRules.isEmpty)
    }

    func testInvalidStorageCombinationsAreReported() throws {
        let definitions = try write("""
        stack: { id: s, name: S }
        storage:
          - { id: nothing, name: Nothing, risk: safe }
          - { id: method, name: Method, risk: safe, paths: [~/a], method: teleport }
          - { id: emptyrun, name: EmptyRun, risk: safe, paths: [~/a], method: run }
          - { id: regex, name: Regex, risk: safe, paths: [{ glob: ~/a, name_matches: "([" }] }
          - { id: sort, name: Sort, risk: safe, paths: [{ glob: ~/a, sort_by: sideways }] }
          - { id: both, name: Both, risk: safe, paths: [{ glob: ~/a, keep_newest: 1, only_newest: 1 }] }
          - { id: proj, name: Proj, risk: safe, project: { markers: [], paths: [] } }
          - { id: abs, name: Abs, risk: safe, project: { markers: [m], paths: ["/etc"] } }
          - { id: act, name: Act, risk: safe, project: { markers: [m], paths: [build], activity: whenever } }
        """)
        let issues = definitions.issues.joined(separator: "\n")
        for expected in [
            "define paths, project or provider", "method must be", "method run needs",
            "invalid regular expression", "sort_by must be", "keep_newest or only_newest",
            "project needs markers and paths", "must be relative", "activity must be",
        ] {
            XCTAssertTrue(issues.contains(expected), "missing '\(expected)' in:\n\(issues)")
        }
        XCTAssertTrue(definitions.storage.isEmpty)
    }

    func testMatcherReferencesAndCyclesAreReported() throws {
        let definitions = try write("""
        stack: { id: m, name: M }
        matchers:
          empty: {}
          loop: { ref: loop }
        processes:
          - { id: a, name: A, match: { ref: nope } }
        """)
        let issues = definitions.issues.joined(separator: "\n")
        XCTAssertTrue(issues.contains("matcher is empty"), issues)
        XCTAssertTrue(issues.contains("references itself"), issues)
        XCTAssertTrue(issues.contains("matcher 'nope' not found"), issues)
    }

    func testUnknownProviderIsReportedWithTheAvailableOnes() throws {
        let definitions = try write("""
        stack: { id: p, name: P }
        storage:
          - { id: x, name: X, risk: safe, provider: magic }
        """)
        let issue = try XCTUnwrap(definitions.issues.first { $0.contains("unknown provider") })
        XCTAssertTrue(issue.contains("fvm-versions"), issue)
    }

    func testStacksAreSortedByOrderAndMergedAcrossFiles() throws {
        try write("stack: { id: b, name: Bee, order: 50 }\nprocesses:\n  - { id: b1, name: B1, match: { exe_name: b } }\n", named: "b.yaml")
        let definitions = try write("stack: { id: a, name: Ay, order: 10 }\nprocesses:\n  - { id: a1, name: A1, match: { exe_name: a } }\n", named: "a.yaml")
        XCTAssertEqual(definitions.stacks.map(\.id), ["a", "b"])
        XCTAssertEqual(definitions.processRules.map(\.id), ["a1", "b1"])
        XCTAssertEqual(definitions.fileCount, 2)
    }

    func testFallbackRulesAreEvaluatedLast() throws {
        let definitions = try write("""
        stack: { id: f, name: F, order: 10 }
        processes:
          - { id: catch-all, name: Catch, fallback: true, match: { exe_name: tool } }
          - { id: specific, name: Specific, match: { exe_name: tool, command_contains: serve } }
        """)
        XCTAssertEqual(definitions.processRules.map(\.id), ["specific", "catch-all"])
    }

    func testDisabledEntriesAreDropped() throws {
        let definitions = try write("""
        stack: { id: d, name: D }
        processes:
          - { id: gone, name: Gone, disabled: true, match: { exe_name: x } }
        storage:
          - { id: gone, name: Gone, disabled: true, risk: safe, paths: [~/x] }
        """)
        XCTAssertTrue(definitions.processRules.isEmpty)
        XCTAssertTrue(definitions.storage.isEmpty)
        XCTAssertEqual(definitions.issues, [])
    }

    func testEmptyDirectoryLoadsNothing() {
        let definitions = DefinitionLoader.load(from: [directory])
        XCTAssertEqual(definitions.fileCount, 0)
        XCTAssertEqual(definitions.issues, [])
        XCTAssertTrue(definitions.stacks.isEmpty)
    }
}

final class SchemaTypeTests: XCTestCase {
    func testRiskOrderingAndLabels() {
        TestSupport.useEnglish()
        XCTAssertLessThan(Risk.safe, Risk.redownload)
        XCTAssertLessThan(Risk.redownload, Risk.dataLoss)
        XCTAssertEqual(Risk(rawValue: "data_loss"), .dataLoss)
        XCTAssertNil(Risk(rawValue: "whatever"))
        XCTAssertEqual(Risk.safe.label, "Safe")
        XCTAssertEqual(Risk.dataLoss.label, "Deletes data")
    }

    func testLimboPolicyParsing() {
        XCTAssertNil(ProcessRules.limboPolicy(from: nil).problem)
        let idle = ProcessRules.limboPolicy(from: try? YAMLDecoder().decode(LimboDefinition.self, from: "{when: idle, minutes: 5}"))
        if case .idle(let minutes, let maxCPU)? = idle.policy {
            XCTAssertEqual(minutes, 5)
            XCTAssertEqual(maxCPU, 1, "max_cpu defaults to 1%")
        } else {
            XCTFail("expected an idle policy")
        }
        let never = ProcessRules.limboPolicy(from: try? YAMLDecoder().decode(LimboDefinition.self, from: "never"))
        if case .never? = never.policy {} else { XCTFail("expected never") }
    }

    func testByteSizeDecodesNumbersAndStrings() throws {
        struct Holder: Decodable { let size: ByteSize }
        XCTAssertEqual(try YAMLDecoder().decode(Holder.self, from: "size: 2GB").size.bytes, 2_000_000_000)
        XCTAssertEqual(try YAMLDecoder().decode(Holder.self, from: "size: 1024").size.bytes, 1024)
        XCTAssertThrowsError(try YAMLDecoder().decode(Holder.self, from: "size: huge"))
    }

    func testLocalizedTextAcceptsPlainStringsAndMaps() throws {
        struct Holder: Decodable { let text: LocalizedText }
        TestSupport.useEnglish()
        XCTAssertEqual(try YAMLDecoder().decode(Holder.self, from: "text: Plain").text.text, "Plain")
        XCTAssertEqual(try YAMLDecoder().decode(Holder.self, from: "text: { en: Hello, es: Hola }").text.text, "Hello")
    }

    func testMatcherAcceptsSingleStringsAndReportsReferences() throws {
        let matcher = try YAMLDecoder().decode(Matcher.self, from: """
        ref: base
        any:
          - { ref: other }
          - { exe_name: tool }
        """)
        XCTAssertEqual(Set(matcher.references), ["base", "other"])
        XCTAssertFalse(matcher.isEmpty)
        XCTAssertTrue(Matcher().isEmpty)
    }

    func testSchemaLintAcceptsAnchorKeysAndFlagsNonMappings() {
        XCTAssertEqual(SchemaLint.check(yaml: "x-anchors: [a, b]\nstack: { id: a, name: A }\n"), [])
        XCTAssertEqual(SchemaLint.check(yaml: "- just\n- a list\n").count, 0)
        XCTAssertTrue(SchemaLint.check(yaml: "stack: { id: a, name: A, bogus: 1 }").contains { $0.contains("bogus") })
    }

    func testLevenshteinDistance() {
        XCTAssertEqual(SchemaLint.distance("", "abc"), 3)
        XCTAssertEqual(SchemaLint.distance("abc", ""), 3)
        XCTAssertEqual(SchemaLint.distance("icn", "icon"), 1)
        XCTAssertEqual(SchemaLint.distance("same", "same"), 0)
    }
}
