import Foundation

struct Recommendation: Identifiable, Sendable {
    enum Action: Sendable {
        case storage(targetID: String)
        case processes(rule: ProcessRule, processes: [ProcInfo])
    }

    let id: String
    let title: String
    let detail: String
    let stack: StackInfo
    let risk: Risk
    let diskBytes: Int64
    let ramBytes: Int64
    let urgent: Bool
    let action: Action

    var isProcess: Bool { rule != nil }

    var rule: ProcessRule? {
        if case .processes(let rule, _) = action { return rule }
        return nil
    }

    var amountText: String {
        var parts: [String] = []
        if diskBytes > 0 { parts.append(tr("amount.disk", ["size": Fmt.disk(diskBytes)])) }
        if ramBytes > 0 { parts.append(tr("amount.ram", ["size": Fmt.memory(ramBytes)])) }
        return parts.joined(separator: " · ")
    }
}

/// Decides what is worth suggesting right now.
enum Advisor {
    static func build(
        groups: [ProcessGroup], targets: [StorageTarget], sizes: [String: Int64],
        system: SystemSnapshot, prefs: PrefsSnapshot
    ) -> [Recommendation] {
        // Which folders hold the user's projects decides which SDKs and build folders look
        // abandoned. Guess it wrong and the first recommendation is to delete something in use,
        // so nothing is recommended until the user has confirmed the list.
        guard prefs.workspacesConfirmed else { return [] }

        var processRecs: [Recommendation] = []
        let limboMin = Int64(prefs.suggestLimboMB * 1_048_576)

        for group in groups {
            let rule = group.rule
            let limbo = group.limboEntries
            if !limbo.isEmpty {
                let ram = limbo.reduce(0) { $0 + $1.totalRSS }
                if ram >= limboMin || limbo.count >= 2 || rule.suggestEvenIfSmall {
                    let age = Fmt.duration(limbo.map(\.process.elapsed).max() ?? 0)
                    let title: String
                    let detail: String
                    switch rule.limbo {
                    case .idle:
                        title = tr("advisor.idle.title", ["name": rule.title])
                        detail = tr("advisor.idle.detail", ["age": age, "detail": rule.detail])
                    case .orphanHelper:
                        title = tr("advisor.orphan_helpers.title", ["name": rule.title])
                        detail = tr("advisor.orphan_helpers.detail", count: limbo.count)
                    default:
                        title = tr("advisor.limbo.title", count: limbo.count, ["name": rule.title])
                        detail = tr("advisor.limbo.detail", ["age": age, "detail": rule.detail])
                    }
                    processRecs.append(Recommendation(
                        id: "proc-\(group.id)", title: title, detail: detail, stack: rule.stack,
                        risk: .safe, diskBytes: 0, ramBytes: ram, urgent: system.pressure == .critical,
                        action: .processes(rule: rule, processes: limbo.map(\.process))
                    ))
                }
            }

            // Heavy things that are in use: only worth mentioning when memory is actually tight.
            guard system.memoryTight else { continue }
            let active = group.entries.filter { !$0.isLimbo }
            let activeRAM = active.reduce(0) { $0 + $1.totalRSS }
            let isHeavyApp = rule.isApp && activeRAM >= 1_500 * 1_048_576
            guard !active.isEmpty, isHeavyApp || rule.suggestWhenMemoryTight else { continue }
            let count = active.reduce(0) { $0 + 1 + $1.descendantCount }
            processRecs.append(Recommendation(
                id: "heavy-\(group.id)",
                title: tr(rule.isApp ? "advisor.heavy_app.title" : "advisor.heavy.title", ["name": rule.title]),
                detail: tr(rule.isApp ? "advisor.heavy_app.detail" : "advisor.heavy.detail", ["count": count]),
                stack: rule.stack, risk: .dataLoss, diskBytes: 0, ramBytes: activeRAM,
                urgent: system.pressure == .critical,
                action: .processes(rule: rule, processes: active.map(\.process))
            ))
        }

        let lowDisk = system.diskFree > 0 && Double(system.diskFree) < prefs.lowDiskGB * 1e9
        let globalMin = lowDisk ? Int64(500_000_000) : Int64(prefs.suggestStorageGB * 1e9)
        var storageRecs: [Recommendation] = []
        for target in targets where target.autoRecommend {
            guard let size = sizes[target.id], size > 0 else { continue }
            let threshold = min(target.recommendMinBytes ?? globalMin, globalMin)
            guard size >= threshold else { continue }
            storageRecs.append(Recommendation(
                id: "storage-\(target.id)", title: target.title, detail: target.detail, stack: target.stack,
                risk: target.risk, diskBytes: size, ramBytes: 0, urgent: lowDisk,
                action: .storage(targetID: target.id)
            ))
        }

        return processRecs.sorted { $0.ramBytes > $1.ramBytes } + storageRecs.sorted { $0.diskBytes > $1.diskBytes }
    }
}
