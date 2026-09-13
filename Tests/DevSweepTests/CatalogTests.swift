import XCTest
@testable import DevSweep

/// Definitions → concrete targets, including project scanning and providers.
final class CatalogTests: XCTestCase {
    private var root: URL!
    private var stacks: URL!
    private var projects: URL!

    override func setUpWithError() throws {
        TestSupport.useEnglish()
        root = try TestSupport.temporaryDirectory()
        stacks = root.appendingPathComponent("stacks")
        projects = root.appendingPathComponent("projects")
        try FileManager.default.createDirectory(at: stacks, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeProject(_ name: String, daysSinceActivity: Int, contents: [String] = ["build"]) throws {
        let project = projects.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        for folder in contents {
            try FileManager.default.createDirectory(at: project.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        let marker = project.appendingPathComponent("marker.txt")
        try "x".write(to: marker, atomically: true, encoding: .utf8)
        let date = Date().addingTimeInterval(-Double(daysSinceActivity) * 86_400)
        for url in [marker, project] + contents.map({ project.appendingPathComponent($0) }) {
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
    }

    private func write(_ yaml: String) throws -> Definitions {
        try yaml.write(to: stacks.appendingPathComponent("test.yaml"), atomically: true, encoding: .utf8)
        let definitions = DefinitionLoader.load(from: [stacks])
        XCTAssertEqual(definitions.issues, [])
        return definitions
    }

    private func prefs(days: Int = 21, installerDays: Int = 7, trashInstallers: Bool = true) -> PrefsSnapshot {
        PrefsSnapshot(
            notifications: true, suggestStorageGB: 2, notifyStorageGB: 5, suggestLimboMB: 150,
            notifyRAMMB: 500, lowDiskGB: 30, inactiveProjectDays: days, artifactAgeDays: installerDays,
            artifactsToTrash: trashInstallers, projectRoots: [projects.path]
        )
    }

    func testProjectEntriesPickTheRightProjectsAndRenderPlaceholders() throws {
        try makeProject("old-app", daysSinceActivity: 60)
        try makeProject("fresh-app", daysSinceActivity: 1)

        let definitions = try write("""
        stack: { id: test, name: Test }
        storage:
          - id: inactive
            name: Inactive builds
            description: "{project_count} project(s) idle for {inactive_days}+ days: {projects}."
            risk: safe
            project:
              markers: [marker.txt]
              activity: inactive
              paths: [build]
          - id: active
            name: Active builds
            description: "{projects}"
            risk: safe
            project:
              markers: [marker.txt]
              activity: active
              paths: [build]
          - id: any
            name: All builds
            description: "{project_count}"
            risk: safe
            project:
              markers: [marker.txt]
              paths: [build]
        """)

        let targets = StorageCatalog.build(prefs: prefs(), definitions: definitions)
        let inactive = try XCTUnwrap(targets.first { $0.id == "inactive" })
        XCTAssertEqual(inactive.detail, "1 project(s) idle for 21+ days: old-app.")
        XCTAssertEqual(inactive.paths.map(\.lastPathComponent), ["build"])
        XCTAssertTrue(inactive.paths[0].path.contains("old-app"))

        XCTAssertEqual(targets.first { $0.id == "active" }?.detail, "fresh-app")
        XCTAssertEqual(targets.first { $0.id == "any" }?.detail, "2")
    }

    func testProjectsWithoutTheFolderAreNotCounted() throws {
        try makeProject("no-build", daysSinceActivity: 60, contents: [])
        let definitions = try write("""
        stack: { id: test, name: Test }
        storage:
          - id: inactive
            name: Inactive builds
            description: "{project_count}"
            risk: safe
            project: { markers: [marker.txt], activity: inactive, paths: [build] }
        """)
        // No paths means the target is dropped entirely.
        XCTAssertTrue(StorageCatalog.build(prefs: prefs(), definitions: definitions).isEmpty)
    }

    func testRequiresPathSkipsTheEntry() throws {
        let definitions = try write("""
        stack: { id: test, name: Test }
        storage:
          - id: needs-missing
            name: Needs missing
            risk: safe
            requires_path: ~/definitely-not-here-\(UUID().uuidString)
            project: { markers: [marker.txt], paths: [build] }
        """)
        XCTAssertTrue(StorageCatalog.build(prefs: prefs(), definitions: definitions).isEmpty)
    }

    func testInstallerProviderUsesOptionsAndPreferences() throws {
        let downloads = root.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        // Age comes from the date the file landed in the folder, which is "now" for files a
        // test just created, so the two thresholds are what separate "old" from "recent" here.
        for name in ["app-release.ipa", "today.ipa", "notes.txt"] {
            try "x".write(to: downloads.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }

        let definitions = try write("""
        stack: { id: test, name: Test }
        storage:
          - id: installers
            name: Installers
            description: "{count} file(s) older than {days} days.{trash_note}"
            risk: safe
            provider: old-installers
            provider_options:
              extensions: [ipa]
              folders: ["\(downloads.path)"]
        """)

        let target = try XCTUnwrap(StorageCatalog.build(prefs: prefs(installerDays: 0), definitions: definitions).first)
        XCTAssertEqual(Set(target.paths.map(\.lastPathComponent)), ["app-release.ipa", "today.ipa"], "only the listed extensions")
        XCTAssertEqual(target.detail, "2 file(s) older than 0 days. They go to the Trash.")
        XCTAssertEqual(target.risk, .safe)
        if case .trash = target.method {} else { XCTFail("expected the trash method") }

        let deleting = StorageCatalog.build(prefs: prefs(installerDays: 0, trashInstallers: false), definitions: definitions)
        XCTAssertEqual(deleting.first?.risk, .dataLoss)
        XCTAssertEqual(deleting.first?.detail, "2 file(s) older than 0 days.")
        if case .delete = try XCTUnwrap(deleting.first?.method) {} else { XCTFail("expected the delete method") }

        // Nothing is old enough: the target disappears instead of showing an empty entry.
        XCTAssertTrue(StorageCatalog.build(prefs: prefs(installerDays: 365), definitions: definitions).isEmpty)
    }

    func testTargetKeepsRiskMethodAndSuggestionSettings() throws {
        try makeProject("app", daysSinceActivity: 1)
        let definitions = try write("""
        stack: { id: test, name: Test, icon: hare, order: 7 }
        storage:
          - id: manual-run
            name: Manual
            description: "d"
            risk: data_loss
            auto_suggest: false
            suggest_above: 2GB
            stop_processes: [some-daemon]
            run:
              - ["/bin/echo", "hi"]
            then_delete: true
            project: { markers: [marker.txt], paths: [build] }
        """)

        let target = try XCTUnwrap(StorageCatalog.build(prefs: prefs(), definitions: definitions).first)
        XCTAssertEqual(target.risk, .dataLoss)
        XCTAssertFalse(target.autoRecommend)
        XCTAssertEqual(target.recommendMinBytes, 2_000_000_000)
        XCTAssertEqual(target.stopProcesses, ["some-daemon"])
        XCTAssertEqual(target.stack.icon, "hare")
        XCTAssertEqual(target.stack.order, 7)
        if case .commands(let commands, let thenDelete) = target.method {
            XCTAssertEqual(commands, [["/bin/echo", "hi"]])
            XCTAssertTrue(thenDelete)
        } else {
            XCTFail("expected commands")
        }
    }

    func testProjectListAbbreviatesLongLists() {
        let names = ["a", "b", "c", "d", "e"].map { name in
            DevProject(url: URL(fileURLWithPath: "/p/\(name)"), markers: [], lastActivity: .now)
        }
        XCTAssertEqual(StorageCatalog.projectList(Array(names.prefix(2))), "a, b")
        XCTAssertEqual(StorageCatalog.projectList(names), "a, b, c and 2 more")
    }

    func testRenderLeavesUnknownPlaceholdersAlone() {
        XCTAssertEqual(StorageCatalog.render("{a} and {b}", ["a": "1"]), "1 and {b}")
    }
}

final class ProjectScannerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = try TestSupport.temporaryDirectory()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func create(_ relativePath: String, file: String? = nil) throws {
        let directory = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let file {
            try "x".write(to: directory.appendingPathComponent(file), atomically: true, encoding: .utf8)
        }
    }

    func testFindsProjectsByMarkerAndSkipsHeavyFolders() throws {
        try create("app", file: "pubspec.yaml")
        try create("api", file: "go.mod")
        try create("app/node_modules/inner", file: "package.json")
        try create("app/build/nested", file: "pubspec.yaml")
        try create(".hidden", file: "go.mod")

        let found = ProjectScanner.scan(
            roots: [root.path], markers: ["pubspec.yaml", "go.mod", "package.json"],
            activityFiles: [], skipNames: ["build"]
        )
        XCTAssertEqual(Set(found.map(\.name)), ["app", "api"])
        XCTAssertEqual(found.first { $0.name == "app" }?.markers, ["pubspec.yaml"])
    }

    func testActivityUsesTheNewestMarkerOrActivityFile() throws {
        try create("app", file: "pubspec.yaml")
        let project = root.appendingPathComponent("app")
        let lock = project.appendingPathComponent("pubspec.lock")
        try "x".write(to: lock, atomically: true, encoding: .utf8)
        let old = Date().addingTimeInterval(-90 * 86_400)
        for path in [project.appendingPathComponent("pubspec.yaml"), project] {
            try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: path.path)
        }

        let withoutLock = ProjectScanner.scan(roots: [root.path], markers: ["pubspec.yaml"], activityFiles: [], skipNames: [])
        XCTAssertLessThan(try XCTUnwrap(withoutLock.first).lastActivity, Date().addingTimeInterval(-60 * 86_400))

        let withLock = ProjectScanner.scan(roots: [root.path], markers: ["pubspec.yaml"], activityFiles: ["pubspec.lock"], skipNames: [])
        XCTAssertGreaterThan(try XCTUnwrap(withLock.first).lastActivity, Date().addingTimeInterval(-60))
    }

    func testNoMarkersMeansNoScan() {
        XCTAssertTrue(ProjectScanner.scan(roots: [root.path], markers: [], activityFiles: [], skipNames: []).isEmpty)
    }

    func testSymlinkedAndRepeatedRootsAreVisitedOnce() throws {
        try create("app", file: "go.mod")
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root.appendingPathComponent("app"))

        let found = ProjectScanner.scan(
            roots: [root.path, root.path], markers: ["go.mod"], activityFiles: [], skipNames: []
        )
        XCTAssertEqual(found.count, 1)
    }
}

final class StorageProviderHelpersTests: XCTestCase {
    func testFvmVersionReadsBothConfigLayouts() throws {
        let root = try TestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let modern = root.appendingPathComponent("modern")
        try FileManager.default.createDirectory(at: modern, withIntermediateDirectories: true)
        try #"{"flutter": "3.38.10"}"#.write(to: modern.appendingPathComponent(".fvmrc"), atomically: true, encoding: .utf8)
        XCTAssertEqual(StorageProviders.fvmVersion(of: modern), "3.38.10")

        let legacy = root.appendingPathComponent("legacy")
        try FileManager.default.createDirectory(at: legacy.appendingPathComponent(".fvm"), withIntermediateDirectories: true)
        try #"{"flutterSdkVersion": "3.35.6"}"#.write(
            to: legacy.appendingPathComponent(".fvm/fvm_config.json"), atomically: true, encoding: .utf8
        )
        XCTAssertEqual(StorageProviders.fvmVersion(of: legacy), "3.35.6")

        XCTAssertNil(StorageProviders.fvmVersion(of: root.appendingPathComponent("missing")))
    }

    func testUnknownProviderReturnsNothing() {
        let context = ProviderContext(
            prefs: PrefsSnapshot(
                notifications: true, suggestStorageGB: 2, notifyStorageGB: 5, suggestLimboMB: 150,
                notifyRAMMB: 500, lowDiskGB: 30, inactiveProjectDays: 21, artifactAgeDays: 7,
                artifactsToTrash: true, projectRoots: []
            ),
            projects: [], inactiveCutoff: .now, options: [:]
        )
        XCTAssertTrue(StorageProviders.run("nope", context: context).isEmpty)
    }
}
