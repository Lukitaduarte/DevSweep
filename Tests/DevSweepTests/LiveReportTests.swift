import XCTest
@testable import DevSweep

/// Read-only dry run against this Mac: `DEVSWEEP_LIVE=1 swift test --filter LiveReportTests`.
/// Prints what DevSweep would suggest; never kills or deletes anything.
final class LiveReportTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DEVSWEEP_LIVE"] == "1", "set DEVSWEEP_LIVE=1")
    }

    func testReport() {
        Prefs.register()
        L10n.shared.reload(directories: [TestSupport.localesDirectory])
        let definitions = DefinitionLoader.load(from: [TestSupport.stacksDirectory, ResourceLocator.userDirectory(named: "stacks")])
        let prefs = PrefsSnapshot.current()
        let system = SystemStats.snapshot()
        print("\n=== \(L10n.shared.language) · RAM \(Fmt.memory(system.memUsed))/\(Fmt.memory(system.memTotal)) · \(system.pressure.label) · \(Fmt.disk(system.diskFree))")
        for issue in definitions.issues { print("! \(issue)") }

        let groups = ProcessScanner.scan(rules: definitions.processRules)
        print("\n=== PROCESSES")
        for group in groups {
            print("\(group.rule.isApp ? "APP " : "TOOL") \(group.rule.title) — \(group.processCount) proc, \(Fmt.memory(group.totalRSS)), limbo \(group.limboEntries.count) (\(Fmt.memory(group.limboRSS)))")
        }

        let targets = StorageCatalog.build(prefs: prefs, definitions: definitions)
        var sizes: [String: Int64] = [:]
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: targets.count) { index in
            let size = SizeCalculator.size(of: targets[index].paths)
            lock.lock()
            sizes[targets[index].id] = size
            lock.unlock()
        }
        print("\n=== STORAGE")
        for target in targets.sorted(by: { sizes[$0.id]! > sizes[$1.id]! }) where sizes[target.id]! > 0 {
            print("\(target.stack.name) · \(target.title) — \(Fmt.disk(sizes[target.id]!)) [\(target.risk.label)\(target.autoRecommend ? "" : ", manual")]")
        }

        let recommendations = Advisor.build(groups: groups, targets: targets, sizes: sizes, system: system, prefs: prefs)
        print("\n=== SUGGESTIONS (\(recommendations.count))")
        for recommendation in recommendations {
            print("• \(recommendation.title) — \(recommendation.amountText) [\(recommendation.risk.label)]")
        }
        print("")
    }
}
