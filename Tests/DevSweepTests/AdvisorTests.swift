import XCTest
@testable import DevSweep

final class AdvisorTests: XCTestCase {
    private let stack = StackInfo(id: "test", name: "Test", icon: "gear", order: 1)

    override func setUp() {
        TestSupport.useEnglish()
    }

    private func rule(
        _ id: String, limbo: LimboPolicy = .orphan, isApp: Bool = false,
        evenIfSmall: Bool = false, whenMemoryTight: Bool = false
    ) -> ProcessRule {
        ProcessRule(
            id: id, title: id, detail: "detail of \(id)", stack: stack, limbo: limbo,
            isApp: isApp, suggestEvenIfSmall: evenIfSmall, suggestWhenMemoryTight: whenMemoryTight
        ) { _, _ in false }
    }

    private func entry(_ pid: Int32, rss: Int64, limbo: Bool, descendants: Int = 0, elapsed: TimeInterval = 3600) -> ProcEntry {
        let process = ProcInfo(
            pid: pid, ppid: 1, uid: 501, rssBytes: rss, cpu: 0, elapsed: elapsed,
            command: "/opt/tool-\(pid)", exePath: "/opt/tool-\(pid)"
        )
        return ProcEntry(
            process: process, totalRSS: rss, descendantCount: descendants,
            ports: [], isLimbo: limbo, reason: limbo ? "orphaned" : nil
        )
    }

    private func prefs(
        suggestStorageGB: Double = 2, suggestLimboMB: Double = 150, lowDiskGB: Double = 30,
        workspacesConfirmed: Bool = true
    ) -> PrefsSnapshot {
        PrefsSnapshot(
            notifications: true, suggestStorageGB: suggestStorageGB, notifyStorageGB: 5,
            suggestLimboMB: suggestLimboMB, notifyRAMMB: 500, lowDiskGB: lowDiskGB,
            inactiveProjectDays: 21, artifactAgeDays: 7, artifactsToTrash: true, projectRoots: [],
            workspacesConfirmed: workspacesConfirmed
        )
    }

    /// Before the user says where their projects are, every "abandoned" judgement is a guess.
    func testNothingIsRecommendedUntilTheWorkspacesAreConfirmed() {
        let group = ProcessGroup(
            rule: rule("dart-other"),
            entries: [entry(1, rss: 900 * 1_048_576, limbo: true)]
        )
        let target = StorageTarget(
            id: "derived-data", stack: StackInfo(id: "ios", name: "iOS", icon: "iphone", order: 10),
            title: "DerivedData", detail: "", risk: .safe,
            paths: [URL(fileURLWithPath: "/p/DerivedData")]
        )
        let sizes = ["derived-data": Int64(40_000_000_000)]

        XCTAssertTrue(
            Advisor.build(
                groups: [group], targets: [target], sizes: sizes,
                system: system(), prefs: prefs(workspacesConfirmed: false)
            ).isEmpty,
            "not even a 40 GB cache is offered before the project folders are confirmed"
        )
        XCTAssertFalse(
            Advisor.build(
                groups: [group], targets: [target], sizes: sizes,
                system: system(), prefs: prefs()
            ).isEmpty,
            "and the same input is recommended once they are"
        )
    }

    private func system(free: Int64 = 500_000_000_000, pressure: MemoryPressure = .normal, used: Int64 = 8) -> SystemSnapshot {
        SystemSnapshot(
            memUsed: used * 1_073_741_824, memTotal: 32 * 1_073_741_824,
            pressure: pressure, diskFree: free, diskTotal: 1_000_000_000_000
        )
    }

    private func target(_ id: String, risk: Risk = .safe, auto: Bool = true, min: Int64? = nil) -> StorageTarget {
        StorageTarget(
            id: id, stack: stack, title: id, detail: "detail", risk: risk,
            paths: [URL(fileURLWithPath: "/tmp/\(id)")], autoRecommend: auto, recommendMinBytes: min
        )
    }

    // MARK: Processes

    func testLimboBelowThresholdIsNotSuggested() {
        let group = ProcessGroup(rule: rule("small"), entries: [entry(1, rss: 10_000_000, limbo: true)])
        let recommendations = Advisor.build(groups: [group], targets: [], sizes: [:], system: system(), prefs: prefs())
        XCTAssertTrue(recommendations.isEmpty)
    }

    func testLimboIsSuggestedAboveThresholdByCountOrFlag() {
        let heavy = ProcessGroup(rule: rule("heavy"), entries: [entry(1, rss: 300_000_000, limbo: true)])
        let two = ProcessGroup(rule: rule("two"), entries: [entry(2, rss: 1_000, limbo: true), entry(3, rss: 1_000, limbo: true)])
        let flagged = ProcessGroup(rule: rule("hung", evenIfSmall: true), entries: [entry(4, rss: 1_000, limbo: true)])

        let ids = Advisor.build(groups: [heavy, two, flagged], targets: [], sizes: [:], system: system(), prefs: prefs()).map(\.id)
        XCTAssertEqual(Set(ids), ["proc-heavy", "proc-two", "proc-hung"])
    }

    func testLimboTitleUsesSingularAndPluralAndCarriesTheProcesses() throws {
        let one = ProcessGroup(rule: rule("solo", evenIfSmall: true), entries: [entry(1, rss: 1_000, limbo: true)])
        let many = ProcessGroup(
            rule: rule("many", evenIfSmall: true),
            entries: [entry(2, rss: 1_000, limbo: true), entry(3, rss: 1_000, limbo: true)]
        )
        let recommendations = Advisor.build(groups: [one, many], targets: [], sizes: [:], system: system(), prefs: prefs())

        let solo = try XCTUnwrap(recommendations.first { $0.id == "proc-solo" })
        XCTAssertEqual(solo.title, "Stop solo")
        XCTAssertTrue(solo.isProcess)
        XCTAssertEqual(solo.risk, .safe)
        let plural = try XCTUnwrap(recommendations.first { $0.id == "proc-many" })
        XCTAssertEqual(plural.title, "Stop 2× many")
        if case .processes(_, let processes) = plural.action {
            XCTAssertEqual(processes.map(\.pid), [2, 3])
        } else {
            XCTFail("expected a process action")
        }
    }

    func testIdleAndOrphanHelperUseTheirOwnWording() throws {
        let idle = ProcessGroup(
            rule: rule("gradle", limbo: .idle(minutes: 20, maxCPU: 1), evenIfSmall: true),
            entries: [entry(1, rss: 1_000, limbo: true)]
        )
        let helpers = ProcessGroup(
            rule: rule("Slack", limbo: .orphanHelper, isApp: true),
            entries: [entry(2, rss: 300_000_000, limbo: true)]
        )
        let recommendations = Advisor.build(groups: [idle, helpers], targets: [], sizes: [:], system: system(), prefs: prefs())

        XCTAssertEqual(recommendations.first { $0.id == "proc-gradle" }?.title, "Stop gradle")
        let helper = try XCTUnwrap(recommendations.first { $0.id == "proc-Slack" })
        XCTAssertEqual(helper.title, "Stop orphaned Slack helpers")
        XCTAssertEqual(helper.detail, "1 helper left running with the app closed.")
    }

    func testHeavyProcessesOnlyWhenMemoryIsTight() {
        let simulators = ProcessGroup(rule: rule("sim", limbo: .never, whenMemoryTight: true), entries: [entry(1, rss: 900_000_000, limbo: false)])
        let app = ProcessGroup(rule: rule("Browser", limbo: .never, isApp: true), entries: [entry(2, rss: 2_000_000_000, limbo: false, descendants: 12)])

        let calm = Advisor.build(groups: [simulators, app], targets: [], sizes: [:], system: system(), prefs: prefs())
        XCTAssertTrue(calm.isEmpty)

        let tight = Advisor.build(groups: [simulators, app], targets: [], sizes: [:], system: system(pressure: .warning), prefs: prefs())
        XCTAssertEqual(Set(tight.map(\.id)), ["heavy-sim", "heavy-Browser"])
        // Quitting an app or a simulator loses state, so it never runs in bulk.
        XCTAssertTrue(tight.allSatisfy { $0.risk == .dataLoss })
        XCTAssertEqual(tight.first { $0.id == "heavy-Browser" }?.detail.contains("13 processes"), true)
    }

    func testCriticalPressureMarksRecommendationsUrgent() {
        let group = ProcessGroup(rule: rule("x", evenIfSmall: true), entries: [entry(1, rss: 1_000, limbo: true)])
        let recommendations = Advisor.build(groups: [group], targets: [], sizes: [:], system: system(pressure: .critical), prefs: prefs())
        XCTAssertEqual(recommendations.first?.urgent, true)
    }

    // MARK: Storage

    func testStorageRespectsThresholdsAndManualFlag() {
        let targets = [target("big"), target("small"), target("manual", auto: false), target("custom", min: 500_000_000)]
        let sizes = ["big": Int64(3_000_000_000), "small": 100_000_000, "manual": 9_000_000_000, "custom": 700_000_000]

        let ids = Advisor.build(groups: [], targets: targets, sizes: sizes, system: system(), prefs: prefs()).map(\.id)
        XCTAssertEqual(ids, ["storage-big", "storage-custom"])
    }

    func testZeroSizedAndUnmeasuredTargetsAreIgnored() {
        let targets = [target("empty"), target("unmeasured")]
        let ids = Advisor.build(groups: [], targets: targets, sizes: ["empty": 0], system: system(), prefs: prefs()).map(\.id)
        XCTAssertTrue(ids.isEmpty)
    }

    func testLowDiskLowersTheBarAndMarksUrgent() throws {
        let targets = [target("medium")]
        let sizes = ["medium": Int64(800_000_000)]

        XCTAssertTrue(Advisor.build(groups: [], targets: targets, sizes: sizes, system: system(), prefs: prefs()).isEmpty)

        let recommendations = Advisor.build(
            groups: [], targets: targets, sizes: sizes,
            system: system(free: 10_000_000_000), prefs: prefs()
        )
        let first = try XCTUnwrap(recommendations.first)
        XCTAssertEqual(first.id, "storage-medium")
        XCTAssertTrue(first.urgent)
    }

    func testProcessesComeFirstAndEachGroupIsSortedBySize() {
        let groups = [
            ProcessGroup(rule: rule("light", evenIfSmall: true), entries: [entry(1, rss: 200_000_000, limbo: true)]),
            ProcessGroup(rule: rule("heavy", evenIfSmall: true), entries: [entry(2, rss: 900_000_000, limbo: true)]),
        ]
        let targets = [target("smaller"), target("bigger")]
        let sizes = ["smaller": Int64(3_000_000_000), "bigger": 9_000_000_000]

        let ids = Advisor.build(groups: groups, targets: targets, sizes: sizes, system: system(), prefs: prefs()).map(\.id)
        XCTAssertEqual(ids, ["proc-heavy", "proc-light", "storage-bigger", "storage-smaller"])
    }

    func testAmountTextMentionsOnlyWhatIsPresent() {
        let groups = [ProcessGroup(rule: rule("p", evenIfSmall: true), entries: [entry(1, rss: 1_048_576, limbo: true)])]
        let recommendations = Advisor.build(
            groups: groups, targets: [target("s")], sizes: ["s": 3_000_000_000],
            system: system(), prefs: prefs()
        )
        XCTAssertTrue(recommendations[0].amountText.hasSuffix("of RAM"))
        XCTAssertTrue(recommendations[1].amountText.hasSuffix("of disk"))
        XCTAssertNil(recommendations[1].rule)
    }
}
