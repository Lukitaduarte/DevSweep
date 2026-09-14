import AppKit
import XCTest
import Yams
@testable import DevSweep

/// Guards contributions to `stacks/`: these run in CI on every pull request.
final class StackDefinitionTests: XCTestCase {
    func testBundledStacksLoadWithoutIssues() {
        let definitions = TestSupport.definitions
        XCTAssertEqual(definitions.issues, [], "fix the problems above in stacks/*.yaml")
        XCTAssertGreaterThan(definitions.processRules.count, 10)
        XCTAssertGreaterThan(definitions.storage.count, 20)
    }

    /// Shared dependency caches are expensive to rebuild and are shared by every project, so a
    /// bulk "clean recommended" must never take one: re-downloading every pod, including private
    /// ones behind credentials, is not something a routine cleanup should trigger.
    func testSharedDependencyCachesAreNeverSuggestedAutomatically() {
        let manualOnly = [
            "cocoapods-cache", "cocoapods-public-specs", "cocoapods-private-repos",
            "flutter-inactive-pods", "pub-cache-git", "gradle-modules", "go-modcache",
        ]
        let byID = Dictionary(
            TestSupport.definitions.storage.map { ($0.definition.id, $0.definition) },
            uniquingKeysWith: { first, _ in first }
        )
        for id in manualOnly {
            guard let item = byID[id] else {
                XCTFail("\(id) is gone: keep this list in step with stacks/*.yaml")
                continue
            }
            XCTAssertEqual(item.autoSuggest, false, "\(id) must stay manual-only")
        }
    }

    func testStackTemplateIsValid() {
        let definitions = DefinitionLoader.load(from: [TestSupport.root.appendingPathComponent("docs")])
        XCTAssertEqual(definitions.issues, [])
        XCTAssertEqual(definitions.fileCount, 1)
    }

    func testEveryTextHasEnglish() throws {
        for file in ResourceLocator.yamlFiles(in: TestSupport.stacksDirectory) {
            let stack = try YAMLDecoder().decode(StackFile.self, from: String(contentsOf: file, encoding: .utf8))
            var texts: [(String, LocalizedText)] = [("stack.name", stack.stack.name)]
            for process in stack.processes ?? [] {
                texts.append(("processes.\(process.id).name", process.name))
                if let description = process.description { texts.append(("processes.\(process.id).description", description)) }
            }
            for item in stack.storage ?? [] {
                texts.append(("storage.\(item.id).name", item.name))
                if let description = item.description { texts.append(("storage.\(item.id).description", description)) }
            }
            for (path, text) in texts {
                XCTAssertNotNil(text.values["en"], "\(file.lastPathComponent) › \(path) needs an 'en' text")
            }
        }
    }

    func testStackIconsAreRealSFSymbols() {
        for stack in TestSupport.definitions.stacks {
            XCTAssertNotNil(NSImage(systemSymbolName: stack.icon, accessibilityDescription: nil), "\(stack.id): unknown SF Symbol '\(stack.icon)'")
        }
    }

    func testLintFlagsTyposWithSuggestion() {
        let yaml = """
        stack: { id: demo, name: Demo, icn: star }
        processes:
          - id: demo
            name: Demo
            match: { comand_contains: demo }
        """
        let issues = SchemaLint.check(yaml: yaml)
        XCTAssertTrue(issues.contains { $0.contains("'icn'") && $0.contains("'icon'") }, "\(issues)")
        XCTAssertTrue(issues.contains { $0.contains("'comand_contains'") && $0.contains("'command_contains'") }, "\(issues)")
    }

    func testLoaderRejectsAbsolutePathsUnknownRefsAndEmptyMatchers() throws {
        let directory = try TestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let yaml = """
        stack: { id: demo, name: Demo }
        processes:
          - { id: empty, name: Empty, match: {} }
          - { id: missing-ref, name: Missing, match: { ref: nope } }
        storage:
          - { id: absolute, name: Absolute, risk: safe, paths: [/opt/somewhere] }
          - { id: bad-risk, name: Bad, risk: maybe, paths: [~/x] }
        """
        try yaml.write(to: directory.appendingPathComponent("demo.yaml"), atomically: true, encoding: .utf8)

        let definitions = DefinitionLoader.load(from: [directory])
        XCTAssertTrue(definitions.processRules.isEmpty)
        XCTAssertTrue(definitions.storage.isEmpty)
        let issues = definitions.issues.joined(separator: "\n")
        XCTAssertTrue(issues.contains("would match every process"), issues)
        XCTAssertTrue(issues.contains("matcher 'nope' not found"), issues)
        XCTAssertTrue(issues.contains("absolute paths are not allowed"), issues)
        XCTAssertTrue(issues.contains("risk must be"), issues)
    }

    func testPersonalStacksOverrideAndDisableBuiltIns() throws {
        let personal = try TestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: personal) }
        let yaml = """
        stack: { id: go, name: Go }
        processes:
          - { id: gopls, name: gopls, disabled: true, match: { exe_name: gopls } }
        storage:
          - { id: go-build, name: My Go cache, risk: safe, paths: ["~/Library/Caches/go-build"] }
        """
        try yaml.write(to: personal.appendingPathComponent("go.yaml"), atomically: true, encoding: .utf8)

        let definitions = DefinitionLoader.load(from: [TestSupport.stacksDirectory, personal])
        XCTAssertEqual(definitions.issues, [])
        XCTAssertFalse(definitions.processRules.contains { $0.id == "gopls" })
        XCTAssertEqual(definitions.storage.filter { $0.definition.id == "go-build" }.map(\.definition.name.text), ["My Go cache"])
    }

    func testMatcherSemantics() throws {
        let yaml = """
        all:
          - exe_name: node
          - command_contains: [vite, next dev]
        none:
          - command_contains: --version
        """
        let matcher = try YAMLDecoder().decode(Matcher.self, from: yaml)
        func process(_ command: String, exe: String = "/usr/local/bin/node") -> ProcInfo {
            ProcInfo(pid: 1, ppid: 1, uid: 1, rssBytes: 0, cpu: 0, elapsed: 0, command: command, exePath: exe)
        }
        XCTAssertTrue(matcher.matches(process("node vite"), hasPorts: false, refs: [:]))
        XCTAssertFalse(matcher.matches(process("node vite --version"), hasPorts: false, refs: [:]))
        XCTAssertFalse(matcher.matches(process("bun vite", exe: "/usr/local/bin/bun"), hasPorts: false, refs: [:]))
    }
}
