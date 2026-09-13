import Foundation

struct ProcInfo: Sendable, Hashable, Identifiable {
    let pid: Int32
    let ppid: Int32
    let uid: UInt32
    let rssBytes: Int64
    let cpu: Double
    let elapsed: TimeInterval
    let command: String
    let exePath: String

    var id: Int32 { pid }
    var exeName: String { (exePath as NSString).lastPathComponent }
    /// Re-parented to launchd: whatever started it (editor, terminal, build) is gone.
    var isOrphan: Bool { ppid == 1 }
    var shortCommand: String { command.replacingOccurrences(of: NSHomeDirectory(), with: "~") }

    /// Outermost `.app` bundle the executable belongs to, for apps in an Applications folder.
    var appBundlePath: String? {
        let home = NSHomeDirectory()
        guard exePath.hasPrefix("/Applications/") || exePath.hasPrefix(home + "/Applications/"),
              let range = exePath.range(of: ".app/") else { return nil }
        return String(exePath[..<range.lowerBound]) + ".app"
    }

    var isAppMainExecutable: Bool {
        guard let bundle = appBundlePath else { return false }
        let macOS = bundle + "/Contents/MacOS/"
        return exePath.hasPrefix(macOS) && !exePath.dropFirst(macOS.count).contains("/")
    }

    /// Chromium/Electron helper processes, which only make sense while their main app runs.
    var isFrameworkHelper: Bool {
        exePath.contains("/Contents/Frameworks/") && exeName.contains("Helper")
    }
}

struct ProcEntry: Sendable, Identifiable {
    let process: ProcInfo
    /// Resident memory of the process plus descendants that aren't tracked on their own.
    let totalRSS: Int64
    let descendantCount: Int
    let ports: [Int]
    let isLimbo: Bool
    let reason: String?

    var id: Int32 { process.pid }
}

struct ProcessGroup: Sendable, Identifiable {
    let rule: ProcessRule
    let entries: [ProcEntry]

    var id: String { rule.id }
    var totalRSS: Int64 { entries.reduce(0) { $0 + $1.totalRSS } }
    var processCount: Int { entries.reduce(0) { $0 + 1 + $1.descendantCount } }
    var limboEntries: [ProcEntry] { entries.filter(\.isLimbo) }
    var limboRSS: Int64 { limboEntries.reduce(0) { $0 + $1.totalRSS } }
    var ports: [Int] { Array(Set(entries.flatMap(\.ports))).sorted() }
}
