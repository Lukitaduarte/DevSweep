import XCTest
@testable import DevSweep

final class ProcessParsingTests: XCTestCase {
    func testParseElapsed() {
        XCTAssertEqual(ProcessScanner.parseElapsed("01:35"), 95)
        XCTAssertEqual(ProcessScanner.parseElapsed("06:02:01"), 21_721)
        XCTAssertEqual(ProcessScanner.parseElapsed("17-01:53:04"), 1_475_584)
    }

    func testParseKeepsSpacesInCommand() {
        let output = """
          2856     1   501    16   0.0 13-22:28:18 /bin/sh /opt/tools/Application Support/tool --flag a b
        97067 96956   501 102800  12.5 01-16:08:47 /opt/fvm/versions/3.38.10/bin/cache/dart-sdk/bin/dart language-server --protocol lsp
        """
        let processes = ProcessScanner.parse(output)
        XCTAssertEqual(processes.count, 2)
        XCTAssertEqual(processes[0].pid, 2856)
        XCTAssertEqual(processes[0].ppid, 1)
        XCTAssertEqual(processes[0].uid, 501)
        XCTAssertEqual(processes[0].rssBytes, 16 * 1024)
        XCTAssertEqual(processes[0].command, "/bin/sh /opt/tools/Application Support/tool --flag a b")
        XCTAssertEqual(processes[1].cpu, 12.5)
        XCTAssertEqual(processes[1].exeName, "dart")
    }
}

/// Exercises the bundled stack files together with the scanner.
final class ProcessGroupingTests: XCTestCase {
    private func process(
        _ pid: Int32, parent: Int32, _ command: String, exe: String? = nil,
        rss: Int64 = 1_000_000, cpu: Double = 0, elapsed: TimeInterval = 600
    ) -> ProcInfo {
        ProcInfo(
            pid: pid, ppid: parent, uid: 501, rssBytes: rss, cpu: cpu, elapsed: elapsed,
            command: command, exePath: exe ?? String(command.split(separator: " ")[0])
        )
    }

    private func group(_ processes: [ProcInfo], ports: [Int32: [Int]] = [:]) -> [ProcessGroup] {
        ProcessScanner.group(processes, ports: ports, selfPID: 0, rules: TestSupport.rules)
    }

    func testOrphanCrashlyticsScriptIsLimboAndCountsChildren() throws {
        let shell = process(10, parent: 1, "/bin/sh /p/ios/Pods/FirebaseCrashlytics/run --flutter-project /p", exe: "/bin/sh")
        let upload = process(11, parent: 10, "/p/ios/Pods/FirebaseCrashlytics/upload-symbols --build-phase", rss: 4_000_000)

        let crashlytics = try XCTUnwrap(group([shell, upload]).first { $0.id == "crashlytics" })
        XCTAssertEqual(crashlytics.entries.count, 1, "the child belongs to the orphaned root, not a second entry")
        XCTAssertTrue(crashlytics.entries[0].isLimbo)
        XCTAssertEqual(crashlytics.totalRSS, 5_000_000)
        XCTAssertTrue(crashlytics.rule.suggestEvenIfSmall)
    }

    func testCrashlyticsRunningTooLongIsLimboEvenWithParent() {
        let xcode = process(5, parent: 1, "/Applications/Xcode.app/Contents/MacOS/Xcode")
        let upload = process(6, parent: 5, "/p/Pods/FirebaseCrashlytics/upload-symbols", elapsed: 3 * 3600)
        XCTAssertEqual(group([xcode, upload]).first { $0.id == "crashlytics" }?.entries.first?.isLimbo, true)
    }

    func testAnalyzerWithLiveEditorIsNotLimbo() {
        let editor = process(100, parent: 1, "/Applications/Editor.app/Contents/MacOS/Electron")
        let analyzer = process(101, parent: 100, "/opt/fvm/versions/3.38.10/bin/cache/dart-sdk/bin/dart language-server --protocol lsp")
        let orphan = process(102, parent: 1, "/opt/fvm/versions/3.35.6/bin/cache/dart-sdk/bin/dartaotruntime /opt/fvm/versions/3.35.6/bin/cache/dart-sdk/bin/snapshots/dart_tooling_daemon_aot.dart.snapshot")
        let groups = group([editor, analyzer, orphan])

        XCTAssertEqual(groups.first { $0.id == "dart-analyzer" }?.entries.first?.isLimbo, false)
        XCTAssertEqual(groups.first { $0.id == "dart-dtd" }?.entries.first?.isLimbo, true)
    }

    func testFallbackRuleOnlyCatchesWhatSpecificRulesMiss() {
        let script = process(150, parent: 1, "/opt/dart-sdk/bin/dart run build_runner watch")
        let analyzer = process(151, parent: 1, "/opt/dart-sdk/bin/dart language-server")
        let groups = group([script, analyzer])
        XCTAssertEqual(groups.first { $0.id == "dart-other" }?.entries.map(\.id), [150])
        XCTAssertEqual(groups.first { $0.id == "dart-analyzer" }?.entries.map(\.id), [151])
    }

    func testIdleGradleDaemonIsLimboButBusyOneIsNot() {
        let idle = process(200, parent: 1, "/usr/bin/java -cp gradle-launcher.jar org.gradle.launcher.daemon.bootstrap.GradleDaemon 8.14", cpu: 0.1, elapsed: 7200)
        let busy = process(201, parent: 1, "/usr/bin/java org.gradle.launcher.daemon.bootstrap.GradleDaemon 8.14", cpu: 90, elapsed: 7200)
        let entries = group([idle, busy]).first { $0.id == "gradle" }?.entries ?? []
        XCTAssertEqual(entries.first { $0.id == 200 }?.isLimbo, true)
        XCTAssertEqual(entries.first { $0.id == 201 }?.isLimbo, false)
    }

    func testNodeDevServerNeedsJavaScriptRuntime() {
        let next = process(250, parent: 1, "node /p/node_modules/.bin/next dev", exe: "/opt/homebrew/bin/node")
        let unrelated = process(251, parent: 1, "/usr/bin/vim vite.config.ts", exe: "/usr/bin/vim")
        let groups = group([next, unrelated])
        XCTAssertEqual(groups.first { $0.id == "node-dev" }?.entries.map(\.id), [250])
    }

    func testLocalServerFallbackUsesPorts() {
        let server = process(260, parent: 1, "/opt/homebrew/bin/python3 -m http.server 8000", exe: "/opt/homebrew/bin/python3")
        XCTAssertNil(group([server]).first { $0.id == "local-servers" })
        XCTAssertEqual(group([server], ports: [260: [8000]]).first { $0.id == "local-servers" }?.ports, [8000])
    }

    func testOrphanElectronHelperIsLimboOnlyWhenMainAppIsClosed() {
        let helperPath = "/Applications/Slack.app/Contents/Frameworks/Slack Helper (Renderer).app/Contents/MacOS/Slack Helper (Renderer)"
        let helper = process(300, parent: 1, helperPath, exe: helperPath, rss: 500_000_000)

        XCTAssertEqual(group([helper]).first { $0.rule.isApp }?.entries.first?.isLimbo, true)

        let main = process(301, parent: 1, "/Applications/Slack.app/Contents/MacOS/Slack", rss: 500_000_000)
        XCTAssertEqual(group([helper, main]).first { $0.rule.isApp }?.limboEntries.count, 0)
    }

    func testAppLoginItemIsNeverTreatedAsOrphanHelper() {
        let path = "/Applications/Foo.app/Contents/Library/LoginItems/Foo Helper.app/Contents/MacOS/Foo Helper"
        let loginItem = process(400, parent: 1, path, exe: path, rss: 600_000_000)
        XCTAssertEqual(group([loginItem]).first { $0.rule.isApp }?.limboEntries.count, 0)
    }
}
