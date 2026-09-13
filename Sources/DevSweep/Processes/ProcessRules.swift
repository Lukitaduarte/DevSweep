import Foundation

enum LimboPolicy: Sendable {
    /// Limbo when the parent that started it has exited.
    case orphan
    /// Limbo when orphaned or running longer than any sane build step.
    case orphanOrOlderThan(minutes: Double)
    /// Daemons that are always parented by launchd: limbo when idle for a while.
    case idle(minutes: Double, maxCPU: Double)
    /// App bundles: a Chromium/Electron helper left behind after the main app quit.
    case orphanHelper
    case never
}

enum StopMethod: Sendable {
    case signal
    case commandsThenSignal([[String]])
    case quitApp(bundlePath: String)
}

struct ProcessRule: Sendable, Identifiable {
    let id: String
    let title: String
    let detail: String
    let stack: StackInfo
    var limbo: LimboPolicy = .orphan
    var stop: StopMethod = .signal
    var isApp: Bool = false
    /// Suggest stopping limbo processes even below the RAM threshold (hung build scripts).
    var suggestEvenIfSmall: Bool = false
    /// Suggest stopping in-use processes when memory is tight (simulators, emulators).
    var suggestWhenMemoryTight: Bool = false
    /// Receives the process and whether it has listening TCP ports.
    let matches: @Sendable (ProcInfo, Bool) -> Bool
}

enum ProcessRules {
    /// Something the user runs from a terminal or tool, as opposed to a system or app-bundled service.
    static func isUserTool(_ process: ProcInfo) -> Bool {
        let systemPrefixes = ["/System/", "/usr/libexec/", "/usr/sbin/", "/Library/Apple/", "/sbin/"]
        return !systemPrefixes.contains(where: process.exePath.hasPrefix) && !process.exePath.contains(".app/")
    }

    static func appRule(bundlePath: String) -> ProcessRule {
        let name = ((bundlePath as NSString).lastPathComponent as NSString).deletingPathExtension
        return ProcessRule(
            id: "app:\(bundlePath)", title: name, detail: tr("apps.detail"),
            stack: .apps, limbo: .orphanHelper, stop: .quitApp(bundlePath: bundlePath), isApp: true
        ) { _, _ in false }
    }

    static func limboPolicy(from definition: LimboDefinition?) -> (policy: LimboPolicy?, problem: String?) {
        guard let definition else { return (.orphan, nil) }
        switch definition.when {
        case "orphan":
            return (.orphan, nil)
        case "never":
            return (.never, nil)
        case "orphan_or_older":
            guard let minutes = definition.minutes else { return (nil, "limbo 'orphan_or_older' needs minutes") }
            return (.orphanOrOlderThan(minutes: minutes), nil)
        case "idle":
            guard let minutes = definition.minutes else { return (nil, "limbo 'idle' needs minutes") }
            return (.idle(minutes: minutes, maxCPU: definition.maxCPU ?? 1), nil)
        default:
            return (nil, "limbo must be orphan, orphan_or_older, idle or never")
        }
    }
}
