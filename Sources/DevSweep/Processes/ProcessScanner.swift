import Darwin
import Foundation

enum ProcessScanner {
    static func scan(rules: [ProcessRule]) -> [ProcessGroup] {
        group(listProcesses(), ports: listeningPorts(), selfPID: getpid(), rules: rules)
    }

    /// Processes owned by the current user.
    static func listProcesses(resolveExe: Bool = true) -> [ProcInfo] {
        let result = Shell.run("/bin/ps", ["-axww", "-o", "pid=,ppid=,uid=,rss=,%cpu=,etime=,command="], timeout: 20)
        let uid = getuid()
        return parse(result.stdout, exeResolver: resolveExe ? resolveExecutable : firstToken)
            .filter { $0.uid == uid }
    }

    static func parse(_ output: String, exeResolver: (Int32, String) -> String = firstToken) -> [ProcInfo] {
        var processes: [ProcInfo] = []
        for line in output.split(separator: "\n") {
            var fields: [Substring] = []
            var rest = line[...]
            for _ in 0..<6 {
                rest = rest.drop(while: { $0 == " " })
                guard let end = rest.firstIndex(of: " ") else { break }
                fields.append(rest[..<end])
                rest = rest[end...]
            }
            let command = String(rest.drop(while: { $0 == " " }))
            guard fields.count == 6, !command.isEmpty,
                  let pid = Int32(fields[0]), let ppid = Int32(fields[1]),
                  let uid = UInt32(fields[2]), let rssKB = Int64(fields[3]) else { continue }
            processes.append(ProcInfo(
                pid: pid, ppid: ppid, uid: uid, rssBytes: rssKB * 1024,
                cpu: Double(fields[4]) ?? 0,
                elapsed: parseElapsed(String(fields[5])),
                command: command,
                exePath: exeResolver(pid, command)
            ))
        }
        return processes
    }

    /// Parses ps etime: `[[dd-]hh:]mm:ss`.
    static func parseElapsed(_ value: String) -> TimeInterval {
        var days = 0.0
        var clock = Substring(value)
        if let dash = value.firstIndex(of: "-") {
            days = Double(value[..<dash]) ?? 0
            clock = value[value.index(after: dash)...]
        }
        let parts = clock.split(separator: ":").compactMap { Double($0) }
        let seconds = parts.reduce(0) { $0 * 60 + $1 }
        return days * 86_400 + seconds
    }

    static func resolveExecutable(pid: Int32, command: String) -> String {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 {
            return String(cString: buffer)
        }
        return firstToken(pid: pid, command: command)
    }

    static func firstToken(pid: Int32, command: String) -> String {
        String(command.split(separator: " ").first ?? "")
    }

    static func listeningPorts() -> [Int32: [Int]] {
        let result = Shell.run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpn"], timeout: 15)
        var ports: [Int32: Set<Int>] = [:]
        var current: Int32?
        for line in result.stdout.split(separator: "\n") {
            if line.hasPrefix("p") {
                current = Int32(line.dropFirst())
            } else if line.hasPrefix("n"), let pid = current, let colon = line.lastIndex(of: ":"),
                      let port = Int(line[line.index(after: colon)...]) {
                ports[pid, default: []].insert(port)
            }
        }
        return ports.mapValues { Array($0) }
    }

    static func group(_ processes: [ProcInfo], ports: [Int32: [Int]], selfPID: Int32, rules: [ProcessRule]) -> [ProcessGroup] {
        let byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var children: [Int32: [Int32]] = [:]
        for process in processes { children[process.ppid, default: []].append(process.pid) }

        var ruleFor: [Int32: ProcessRule] = [:]
        var appRules: [String: ProcessRule] = [:]
        for process in processes where process.pid != selfPID {
            let hasPorts = !(ports[process.pid] ?? []).isEmpty
            if let rule = rules.first(where: { $0.matches(process, hasPorts) }) {
                ruleFor[process.pid] = rule
            } else if let bundle = process.appBundlePath, !bundle.contains("DevSweep") {
                let rule = appRules[bundle] ?? ProcessRules.appRule(bundlePath: bundle)
                appRules[bundle] = rule
                ruleFor[process.pid] = rule
            }
        }
        let runningApps = Set(processes.filter(\.isAppMainExecutable).compactMap(\.appBundlePath))

        func hasAncestor(_ pid: Int32, matching ruleID: String) -> Bool {
            var parent = byPID[pid]?.ppid
            var hops = 0
            while let current = parent, current > 1, hops < 64 {
                if ruleFor[current]?.id == ruleID { return true }
                parent = byPID[current]?.ppid
                hops += 1
            }
            return false
        }

        let roots = ruleFor.filter { !hasAncestor($0.key, matching: $0.value.id) }
        let rootPIDs = Set(roots.keys)
        var entriesByRule: [String: [ProcEntry]] = [:]

        for (pid, rule) in roots {
            guard let process = byPID[pid] else { continue }
            var total = process.rssBytes
            var descendants = 0
            var stack = children[pid] ?? []
            var visited = Set<Int32>()
            while let child = stack.popLast() {
                guard !rootPIDs.contains(child), visited.insert(child).inserted, let info = byPID[child] else { continue }
                total += info.rssBytes
                descendants += 1
                stack += children[child] ?? []
            }
            let (isLimbo, reason) = evaluate(rule.limbo, process, runningApps: runningApps)
            entriesByRule[rule.id, default: []].append(ProcEntry(
                process: process, totalRSS: total, descendantCount: descendants,
                ports: (ports[pid] ?? []).sorted(), isLimbo: isLimbo, reason: reason
            ))
        }

        let tools = rules.compactMap { rule -> ProcessGroup? in
            guard let entries = entriesByRule[rule.id] else { return nil }
            return ProcessGroup(rule: rule, entries: entries.sorted { $0.totalRSS > $1.totalRSS })
        }
        // Only surface apps worth looking at: heavy, helper-bloated, or with orphans.
        let apps = appRules.values.compactMap { rule -> ProcessGroup? in
            guard let entries = entriesByRule[rule.id] else { return nil }
            let group = ProcessGroup(rule: rule, entries: entries.sorted { $0.totalRSS > $1.totalRSS })
            let interesting = !group.limboEntries.isEmpty || group.totalRSS >= 400 * 1_048_576 || group.processCount >= 6
            return interesting ? group : nil
        }.sorted { $0.totalRSS > $1.totalRSS }
        return tools + apps
    }

    static func evaluate(_ policy: LimboPolicy, _ process: ProcInfo, runningApps: Set<String>) -> (Bool, String?) {
        let age = Fmt.duration(process.elapsed)
        switch policy {
        case .orphan:
            return process.isOrphan ? (true, tr("reason.orphan", ["age": age])) : (false, nil)
        case .orphanOrOlderThan(let minutes):
            if process.isOrphan { return (true, tr("reason.orphan_build", ["age": age])) }
            if process.elapsed > minutes * 60 { return (true, tr("reason.stuck", ["age": age])) }
            return (false, nil)
        case .idle(let minutes, let maxCPU):
            guard process.elapsed > minutes * 60 && process.cpu < maxCPU else { return (false, nil) }
            return (true, tr("reason.idle", ["cpu": String(format: "%.1f", process.cpu), "age": age]))
        case .orphanHelper:
            guard process.isOrphan, process.isFrameworkHelper, let bundle = process.appBundlePath,
                  !runningApps.contains(bundle) else { return (false, nil) }
            return (true, tr("reason.orphan_helper", ["age": age]))
        case .never:
            return (false, nil)
        }
    }
}

enum ProcessKiller {
    /// Sends SIGTERM to each process and its descendants (children first), then SIGKILL after 3s.
    /// A process is skipped if its PID now belongs to a different command.
    @discardableResult
    static func terminate(_ targets: [ProcInfo]) -> Int {
        guard !targets.isEmpty else { return 0 }
        let current = ProcessScanner.listProcesses(resolveExe: false)
        let byPID = Dictionary(current.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var children: [Int32: [Int32]] = [:]
        for process in current { children[process.ppid, default: []].append(process.pid) }

        let me = getpid()
        var ordered: [Int32] = []
        var seen = Set<Int32>()
        func collect(_ pid: Int32) {
            guard pid > 1, pid != me, seen.insert(pid).inserted else { return }
            for child in children[pid] ?? [] { collect(child) }
            ordered.append(pid)
        }
        for target in targets {
            guard let live = byPID[target.pid], live.command == target.command else { continue }
            collect(target.pid)
        }
        guard !ordered.isEmpty else { return 0 }

        for pid in ordered { kill(pid, SIGTERM) }
        var alive = ordered
        let deadline = Date().addingTimeInterval(3)
        while !alive.isEmpty && Date() < deadline {
            usleep(100_000)
            alive = alive.filter { kill($0, 0) == 0 }
        }
        for pid in alive { kill(pid, SIGKILL) }
        return ordered.count
    }

    static func terminateMatching(_ needles: [String]) {
        let me = getpid()
        let matches = ProcessScanner.listProcesses(resolveExe: false).filter { process in
            process.pid != me && needles.contains { process.command.contains($0) }
        }
        terminate(matches)
    }
}
