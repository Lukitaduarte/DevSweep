import XCTest
@testable import DevSweep

final class ShellTests: XCTestCase {
    func testRunsAToolAndCapturesOutput() {
        let result = Shell.run("/bin/echo", ["hello", "world"])
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hello world")
        XCTAssertTrue(result.stderr.isEmpty)
    }

    func testReportsFailureStatusAndStderr() {
        let result = Shell.run("/bin/ls", ["/definitely/not/here"])
        XCTAssertNotEqual(result.status, 0)
        XCTAssertFalse(result.stderr.isEmpty)
    }

    func testMissingToolIsReportedInsteadOfCrashing() {
        TestSupport.useEnglish()
        let result = Shell.run("devsweep-does-not-exist", [])
        XCTAssertEqual(result.status, 127)
        XCTAssertTrue(result.stderr.contains("command not found"), result.stderr)
    }

    func testFindsToolsOnTheSearchPath() {
        XCTAssertNotNil(Shell.which("ls"))
        XCTAssertNil(Shell.which("devsweep-does-not-exist"))
        XCTAssertTrue(Shell.searchPath.contains("/usr/bin"))
    }

    func testTimeoutTerminatesALongCommand() {
        let started = Date()
        let result = Shell.run("/bin/sleep", ["30"], timeout: 0.5)
        XCTAssertLessThan(Date().timeIntervalSince(started), 20)
        XCTAssertNotEqual(result.status, 0)
    }

    func testRunsByNameThroughTheSearchPath() {
        XCTAssertEqual(Shell.run("echo", ["hi"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hi")
    }
}

final class SystemStatsTests: XCTestCase {
    func testSnapshotReportsPlausibleNumbers() {
        let snapshot = SystemStats.snapshot()
        XCTAssertGreaterThan(snapshot.memTotal, 0)
        XCTAssertGreaterThan(snapshot.memUsed, 0)
        XCTAssertLessThanOrEqual(snapshot.memUsed, snapshot.memTotal)
        XCTAssertGreaterThan(snapshot.diskTotal, 0)
        XCTAssertGreaterThan(snapshot.memFraction, 0)
        XCTAssertLessThanOrEqual(snapshot.memFraction, 1)
    }

    func testMemoryTightFollowsPressureAndUsage() {
        func snapshot(used: Int64, pressure: MemoryPressure) -> SystemSnapshot {
            SystemSnapshot(memUsed: used, memTotal: 100, pressure: pressure, diskFree: 1, diskTotal: 2)
        }
        XCTAssertFalse(snapshot(used: 50, pressure: .normal).memoryTight)
        XCTAssertTrue(snapshot(used: 90, pressure: .normal).memoryTight)
        XCTAssertTrue(snapshot(used: 10, pressure: .warning).memoryTight)
        XCTAssertTrue(snapshot(used: 10, pressure: .critical).memoryTight)
    }

    func testPressureLabelsAreLocalized() {
        TestSupport.useEnglish()
        XCTAssertEqual(MemoryPressure.normal.label, "normal")
        XCTAssertEqual(MemoryPressure.warning.label, "high")
        XCTAssertEqual(MemoryPressure.critical.label, "critical")
    }
}

final class PrefsTests: XCTestCase {
    private let suiteKeys = [
        Prefs.Key.projectRoots, Prefs.Key.language, Prefs.Key.inactiveProjectDays, Prefs.Key.artifactsToTrash,
    ]
    private var saved: [String: Any] = [:]

    override func setUp() {
        Prefs.register()
        saved = suiteKeys.reduce(into: [:]) { result, key in
            if let value = Prefs.defaults.object(forKey: key) { result[key] = value }
        }
    }

    override func tearDown() {
        for key in suiteKeys { Prefs.defaults.removeObject(forKey: key) }
        for (key, value) in saved { Prefs.defaults.set(value, forKey: key) }
    }

    func testDefaultsAreRegistered() {
        let snapshot = PrefsSnapshot.current()
        XCTAssertTrue(snapshot.notifications)
        XCTAssertEqual(snapshot.suggestStorageGB, 2)
        XCTAssertEqual(snapshot.notifyStorageGB, 5)
        XCTAssertEqual(snapshot.suggestLimboMB, 150)
        XCTAssertEqual(snapshot.inactiveProjectDays, 21)
        XCTAssertEqual(snapshot.artifactAgeDays, 7)
        XCTAssertTrue(snapshot.artifactsToTrash)
        XCTAssertFalse(snapshot.projectRoots.isEmpty)
    }

    func testProjectRootsAreSplitAndTrimmed() {
        Prefs.defaults.set("  ~/one  \n\n~/two\n", forKey: Prefs.Key.projectRoots)
        XCTAssertEqual(PrefsSnapshot.current().projectRoots, ["~/one", "~/two"])
    }

    func testLanguagePreferenceDefaultsToSystem() {
        Prefs.defaults.removeObject(forKey: Prefs.Key.language)
        Prefs.register()
        XCTAssertEqual(Prefs.languagePreference, "system")
        Prefs.defaults.set("es", forKey: Prefs.Key.language)
        XCTAssertEqual(Prefs.languagePreference, "es")
    }

    func testDefaultProjectRootsOnlyListExistingFolders() {
        for root in Prefs.defaultProjectRoots where root != "~/Projects" {
            XCTAssertTrue(FileManager.default.fileExists(atPath: expandTilde(root)), root)
        }
    }
}

final class FormattingTests: XCTestCase {
    override func setUp() {
        TestSupport.useEnglish()
    }

    func testDurationUsesMinutesHoursAndDays() {
        XCTAssertEqual(Fmt.duration(30), "1 min")
        XCTAssertEqual(Fmt.duration(600), "10 min")
        XCTAssertEqual(Fmt.duration(3 * 3600), "3 h")
        XCTAssertEqual(Fmt.duration(72 * 3600), "3 days")
    }

    func testSizesUseDecimalForDiskAndBinaryForMemory() {
        XCTAssertTrue(Fmt.disk(1_000_000_000).contains("1"))
        XCTAssertTrue(Fmt.memory(1_073_741_824).contains("1"))
        XCTAssertEqual(Fmt.disk(-5), Fmt.disk(0))
    }

    func testRelativeDatesAreRendered() {
        XCTAssertFalse(Fmt.relative(Date().addingTimeInterval(-3600)).isEmpty)
    }

    func testExpandTilde() {
        XCTAssertEqual(expandTilde("~/x"), NSHomeDirectory() + "/x")
        XCTAssertEqual(expandTilde("/abs"), "/abs")
    }
}

final class ResourceLocatorTests: XCTestCase {
    func testEnvironmentOverrideWins() throws {
        let directory = try TestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        setenv("DEVSWEEP_TEST_DIR", directory.path, 1)
        defer { unsetenv("DEVSWEEP_TEST_DIR") }

        XCTAssertEqual(
            ResourceLocator.directory(named: "whatever", environmentKey: "DEVSWEEP_TEST_DIR")?.path,
            directory.path
        )
    }

    func testFallsBackToTheCheckoutAndNilWhenMissing() {
        // `swift test` runs from the package root, where ./stacks exists.
        XCTAssertNotNil(ResourceLocator.directory(named: "stacks", environmentKey: "DEVSWEEP_UNSET_KEY"))
        XCTAssertNil(ResourceLocator.directory(named: "no-such-folder", environmentKey: "DEVSWEEP_UNSET_KEY"))
    }

    func testUserDirectoryIsUnderTheHomeConfigFolder() {
        XCTAssertEqual(
            ResourceLocator.userDirectory(named: "stacks").path,
            NSHomeDirectory() + "/.config/devsweep/stacks"
        )
    }

    func testYamlFilesAreListedSortedAndFiltered() throws {
        let directory = try TestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in ["b.yaml", "a.yml", "readme.md"] {
            try "x".write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        XCTAssertEqual(ResourceLocator.yamlFiles(in: directory).map(\.lastPathComponent), ["a.yml", "b.yaml"])
        XCTAssertTrue(ResourceLocator.yamlFiles(in: directory.appendingPathComponent("missing")).isEmpty)
    }
}
