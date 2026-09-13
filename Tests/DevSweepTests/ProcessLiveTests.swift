import XCTest
@testable import DevSweep

/// Exercises the process layer against the running system. Everything here is read-only,
/// except for a `sleep` this test starts itself and then stops.
final class ProcessLiveTests: XCTestCase {
    func testListsTheCurrentUsersProcessesIncludingThisOne() {
        let processes = ProcessScanner.listProcesses()
        XCTAssertFalse(processes.isEmpty)
        XCTAssertTrue(processes.allSatisfy { $0.uid == getuid() })
        let me = processes.first { $0.pid == getpid() }
        XCTAssertNotNil(me)
        XCTAssertTrue(me?.exePath.contains("xctest") == true || me?.command.contains("xctest") == true)
    }

    func testResolvesExecutablePathsAndFallsBackToTheCommand() {
        XCTAssertTrue(ProcessScanner.resolveExecutable(pid: getpid(), command: "fallback").hasPrefix("/"))
        // PID 0 has no path, so the first token of the command is used.
        XCTAssertEqual(ProcessScanner.resolveExecutable(pid: 0, command: "/opt/tool --flag"), "/opt/tool")
        XCTAssertEqual(ProcessScanner.firstToken(pid: 1, command: "/sbin/launchd"), "/sbin/launchd")
        XCTAssertEqual(ProcessScanner.firstToken(pid: 1, command: ""), "")
    }

    func testListeningPortsAreReadable() {
        // Nothing may be listening on a CI runner, so only the shape is asserted.
        for (pid, ports) in ProcessScanner.listeningPorts() {
            XCTAssertGreaterThan(pid, 0)
            XCTAssertTrue(ports.allSatisfy { $0 > 0 && $0 <= 65_535 })
        }
    }

    func testScanGroupsRealProcessesWithTheBundledRules() {
        let groups = ProcessScanner.scan(rules: TestSupport.rules)
        for group in groups {
            XCTAssertFalse(group.entries.isEmpty)
            XCTAssertGreaterThanOrEqual(group.processCount, group.entries.count)
            XCTAssertEqual(group.limboRSS, group.limboEntries.reduce(0) { $0 + $1.totalRSS })
        }
        // The test runner itself must never be offered up for killing.
        XCTAssertFalse(groups.flatMap(\.entries).contains { $0.process.pid == getpid() })
    }

    func testTerminateStopsAProcessThisTestStarted() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["120"]
        try process.run()
        let pid = process.processIdentifier

        let info = try XCTUnwrap(ProcessScanner.listProcesses(resolveExe: false).first { $0.pid == pid })
        XCTAssertEqual(ProcessKiller.terminate([info]), 1)
        process.waitUntilExit()
        XCTAssertFalse(process.isRunning)
    }

    func testTerminateIgnoresPidsWhoseCommandChanged() {
        let stale = ProcInfo(
            pid: getpid(), ppid: 1, uid: getuid(), rssBytes: 0, cpu: 0, elapsed: 0,
            command: "something else entirely", exePath: "/opt/gone"
        )
        XCTAssertEqual(ProcessKiller.terminate([stale]), 0, "a reused PID must never be signaled")
        XCTAssertEqual(ProcessKiller.terminate([]), 0)
    }

    func testTerminateMatchingStopsBySubstring() throws {
        let marker = "devsweep-test-\(UUID().uuidString)"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "exec -a \(marker) /bin/sleep 120"]
        try process.run()
        defer { if process.isRunning { process.terminate() } }

        // Give launchd a moment to publish the new process in ps.
        var seen = false
        for _ in 0..<20 where !seen {
            seen = ProcessScanner.listProcesses(resolveExe: false).contains { $0.command.contains(marker) }
            if !seen { usleep(100_000) }
        }
        try XCTSkipUnless(seen, "the helper process never showed up in ps")

        ProcessKiller.terminateMatching([marker])
        process.waitUntilExit()
        XCTAssertFalse(ProcessScanner.listProcesses(resolveExe: false).contains { $0.command.contains(marker) })
    }
}

final class ProcessModelTests: XCTestCase {
    private func process(_ exePath: String, ppid: Int32 = 1, command: String? = nil) -> ProcInfo {
        ProcInfo(
            pid: 42, ppid: ppid, uid: 501, rssBytes: 0, cpu: 0, elapsed: 0,
            command: command ?? exePath, exePath: exePath
        )
    }

    func testAppBundleDetection() {
        let helper = process("/Applications/Slack.app/Contents/Frameworks/Slack Helper.app/Contents/MacOS/Slack Helper")
        XCTAssertEqual(helper.appBundlePath, "/Applications/Slack.app")
        XCTAssertFalse(helper.isAppMainExecutable)
        XCTAssertTrue(helper.isFrameworkHelper)

        let main = process("/Applications/Slack.app/Contents/MacOS/Slack")
        XCTAssertTrue(main.isAppMainExecutable)
        XCTAssertFalse(main.isFrameworkHelper)

        let userApp = process(NSHomeDirectory() + "/Applications/Tool.app/Contents/MacOS/Tool")
        XCTAssertEqual(userApp.appBundlePath, NSHomeDirectory() + "/Applications/Tool.app")

        XCTAssertNil(process("/usr/bin/ssh").appBundlePath)
        XCTAssertNil(process("/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder").appBundlePath)
    }

    func testOrphanAndShortCommand() {
        XCTAssertTrue(process("/opt/tool", ppid: 1).isOrphan)
        XCTAssertFalse(process("/opt/tool", ppid: 500).isOrphan)
        let inHome = process("/opt/tool", command: NSHomeDirectory() + "/code/app --run")
        XCTAssertEqual(inHome.shortCommand, "~/code/app --run")
        XCTAssertEqual(process("/opt/some-tool").exeName, "some-tool")
    }

    func testIsUserToolExcludesSystemAndBundledExecutables() {
        XCTAssertTrue(ProcessRules.isUserTool(process("/opt/homebrew/bin/node")))
        XCTAssertTrue(ProcessRules.isUserTool(process(NSHomeDirectory() + "/go/bin/gopls")))
        XCTAssertFalse(ProcessRules.isUserTool(process("/System/Library/x")))
        XCTAssertFalse(ProcessRules.isUserTool(process("/usr/libexec/x")))
        XCTAssertFalse(ProcessRules.isUserTool(process("/Applications/Some.app/Contents/MacOS/Some")))
    }

    func testAppRuleNamesTheBundleAndQuitsIt() {
        TestSupport.useEnglish()
        let rule = ProcessRules.appRule(bundlePath: "/Applications/Brave Browser.app")
        XCTAssertEqual(rule.title, "Brave Browser")
        XCTAssertTrue(rule.isApp)
        XCTAssertEqual(rule.stack.id, "apps")
        if case .quitApp(let bundle) = rule.stop {
            XCTAssertEqual(bundle, "/Applications/Brave Browser.app")
        } else {
            XCTFail("apps are quit, not signaled")
        }
    }

    func testEvaluateCoversEveryPolicy() {
        TestSupport.useEnglish()
        let orphan = ProcInfo(pid: 1, ppid: 1, uid: 1, rssBytes: 0, cpu: 0, elapsed: 7200, command: "c", exePath: "/opt/c")
        let child = ProcInfo(pid: 2, ppid: 99, uid: 1, rssBytes: 0, cpu: 50, elapsed: 60, command: "c", exePath: "/opt/c")

        XCTAssertTrue(ProcessScanner.evaluate(.orphan, orphan, runningApps: []).0)
        XCTAssertFalse(ProcessScanner.evaluate(.orphan, child, runningApps: []).0)
        XCTAssertTrue(ProcessScanner.evaluate(.orphanOrOlderThan(minutes: 30), orphan, runningApps: []).0)
        XCTAssertFalse(ProcessScanner.evaluate(.orphanOrOlderThan(minutes: 30), child, runningApps: []).0)
        XCTAssertTrue(ProcessScanner.evaluate(.idle(minutes: 20, maxCPU: 1), orphan, runningApps: []).0)
        XCTAssertFalse(ProcessScanner.evaluate(.idle(minutes: 20, maxCPU: 1), child, runningApps: []).0)
        XCTAssertFalse(ProcessScanner.evaluate(.never, orphan, runningApps: []).0)
        XCTAssertNil(ProcessScanner.evaluate(.never, orphan, runningApps: []).1)

        let helperPath = "/Applications/App.app/Contents/Frameworks/App Helper.app/Contents/MacOS/App Helper"
        let helper = ProcInfo(pid: 3, ppid: 1, uid: 1, rssBytes: 0, cpu: 0, elapsed: 60, command: helperPath, exePath: helperPath)
        XCTAssertTrue(ProcessScanner.evaluate(.orphanHelper, helper, runningApps: []).0)
        XCTAssertFalse(ProcessScanner.evaluate(.orphanHelper, helper, runningApps: ["/Applications/App.app"]).0)
        XCTAssertFalse(ProcessScanner.evaluate(.orphanHelper, orphan, runningApps: []).0)
    }
}
