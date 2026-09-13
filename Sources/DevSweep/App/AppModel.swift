import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var system = SystemStats.snapshot()
    @Published private(set) var definitions = Definitions.empty
    @Published private(set) var groups: [ProcessGroup] = []
    @Published private(set) var targets: [StorageTarget] = []
    /// Measured size per target id; missing means "still measuring".
    @Published private(set) var sizes: [String: Int64] = [:]
    @Published private(set) var recommendations: [Recommendation] = []
    @Published private(set) var isScanningStorage = false
    @Published private(set) var isScanningProcesses = false
    @Published private(set) var isPerformingAll = false
    @Published private(set) var lastStorageScan: Date?
    @Published private(set) var busy: Set<String> = []
    @Published private(set) var banner: String?
    @Published private(set) var totalFreed: Int64
    /// Bumped when the language changes so every view re-renders its strings.
    @Published private(set) var languageRevision = 0

    private var timers: [Timer] = []
    private var bannerTask: Task<Void, Never>?

    private init() {
        Prefs.register()
        totalFreed = Int64(Prefs.defaults.double(forKey: Prefs.Key.totalFreedBytes))
    }

    // MARK: Scheduling

    func start() {
        guard timers.isEmpty else { return }
        schedule(every: 10) { $0.refreshSystem() }
        schedule(every: 120) { model in Task { await model.refreshProcesses() } }
        schedule(every: 900) { model in
            let hours = Prefs.defaults.double(forKey: Prefs.Key.storageScanHours)
            let stale = model.lastStorageScan.map { Date().timeIntervalSince($0) > hours * 3600 } ?? true
            if stale { Task { await model.scanStorage() } }
        }
        Task { await reloadEverything() }
    }

    private func schedule(every interval: TimeInterval, _ action: @escaping @MainActor (AppModel) -> Void) {
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                action(self)
            }
        }
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        timers.append(timer)
    }

    func popoverOpened() {
        refreshSystem()
        Task { await refreshProcesses() }
        if !isScanningStorage, lastStorageScan.map({ Date().timeIntervalSince($0) > 1800 }) ?? false {
            Task { await scanStorage() }
        }
    }

    func refreshAll() {
        refreshSystem()
        Task { await reloadEverything() }
    }

    func prefsChanged() {
        recompute()
        Task { await scanStorage() }
    }

    func setLanguage(_ code: String) {
        Prefs.defaults.set(code, forKey: Prefs.Key.language)
        L10n.shared.reload()
        Notifier.shared.registerCategories()
        languageRevision += 1
        Task {
            await reloadDefinitions()
            await refreshProcesses()
            // Names changed, sizes didn't: rebuild labels without re-running du.
            await scanStorage(remeasure: false)
        }
    }

    private func reloadEverything() async {
        await reloadDefinitions()
        await refreshProcesses()
        await scanStorage()
    }

    // MARK: Scanning

    func reloadDefinitions() async {
        let loaded = await Task.detached(priority: .utility) { DefinitionLoader.load() }.value
        definitions = loaded
        if !loaded.issues.isEmpty {
            showBanner(tr("banner.stack_issues", count: loaded.issues.count))
        }
    }

    func refreshSystem() {
        system = SystemStats.snapshot()
    }

    func refreshProcesses() async {
        guard !isScanningProcesses else { return }
        isScanningProcesses = true
        let rules = definitions.processRules
        groups = await Task.detached(priority: .utility) { ProcessScanner.scan(rules: rules) }.value
        isScanningProcesses = false
        recompute()
        notifyIfNeeded()
    }

    func scanStorage(remeasure: Bool = true) async {
        guard !isScanningStorage else { return }
        isScanningStorage = true
        let prefs = PrefsSnapshot.current()
        let definitions = definitions
        let catalog = await Task.detached(priority: .utility) {
            StorageCatalog.build(prefs: prefs, definitions: definitions)
        }.value
        targets = catalog
        let ids = Set(catalog.map(\.id))
        sizes = sizes.filter { ids.contains($0.key) }
        let toMeasure = catalog.filter { remeasure || sizes[$0.id] == nil }

        await withTaskGroup(of: (String, Int64).self) { group in
            var pending = toMeasure[...]
            // du hammers the disk; a few at a time keeps the Mac responsive.
            for _ in 0..<4 {
                guard let target = pending.popFirst() else { break }
                group.addTask(priority: .utility) { (target.id, SizeCalculator.size(of: target.paths)) }
            }
            while let result = await group.next() {
                sizes[result.0] = result.1
                recompute()
                if let target = pending.popFirst() {
                    group.addTask(priority: .utility) { (target.id, SizeCalculator.size(of: target.paths)) }
                }
            }
        }

        if remeasure { lastStorageScan = Date() }
        isScanningStorage = false
        refreshSystem()
        recompute()
        notifyIfNeeded()
    }

    private func recompute() {
        recommendations = Advisor.build(
            groups: groups, targets: targets, sizes: sizes, system: system, prefs: PrefsSnapshot.current()
        )
    }

    // MARK: Actions

    func isBusy(_ recommendation: Recommendation) -> Bool {
        if busy.contains(recommendation.id) { return true }
        if case .storage(let id) = recommendation.action { return busy.contains(id) }
        return false
    }

    func clean(targetIDs: [String]) async {
        let result = await cleanTargets(targetIDs)
        showBanner(cleanMessage(freed: result.freed, errors: result.errors))
        refreshSystem()
    }

    func stop(rule: ProcessRule, processes: [ProcInfo], key: String) async {
        let result = await stopProcesses(rule: rule, processes: processes, key: key)
        showBanner(result.count > 0
            ? tr("banner.stopped", count: result.count, ["ram": Fmt.memory(result.ram)])
            : tr("banner.nothing_to_stop"))
        await refreshProcesses()
        refreshSystem()
    }

    func perform(_ recommendation: Recommendation) async {
        switch recommendation.action {
        case .storage(let id):
            await clean(targetIDs: [id])
        case .processes(let rule, let processes):
            await stop(rule: rule, processes: processes, key: recommendation.id)
        }
    }

    func stopAllLimbo() async {
        var count = 0
        var ram: Int64 = 0
        for group in groups where !group.limboEntries.isEmpty {
            let result = await stopProcesses(rule: group.rule, processes: group.limboEntries.map(\.process), key: "limbo-all")
            count += result.count
            ram += result.ram
        }
        showBanner(count > 0 ? tr("banner.stopped", count: count, ["ram": Fmt.memory(ram)]) : tr("banner.no_limbo"))
        await refreshProcesses()
        refreshSystem()
    }

    func performAllRecommended() async {
        await performBatch(recommendations)
    }

    /// Called from the notification's "Clean now" button; rescans so nothing stale gets killed.
    func performRecommendations(ids: [String]) async {
        await refreshProcesses()
        if lastStorageScan == nil { await scanStorage() }
        await performBatch(recommendations.filter { ids.contains($0.id) })
    }

    private func performBatch(_ batch: [Recommendation]) async {
        // Anything that loses user data needs an explicit per-item confirmation.
        let batch = batch.filter { $0.risk != .dataLoss }
        guard !batch.isEmpty, !isPerformingAll else { return }
        isPerformingAll = true
        var killed = 0
        var ram: Int64 = 0
        var storageIDs: [String] = []
        for recommendation in batch {
            switch recommendation.action {
            case .processes(let rule, let processes):
                let result = await stopProcesses(rule: rule, processes: processes, key: recommendation.id)
                killed += result.count
                ram += result.ram
            case .storage(let id):
                storageIDs.append(id)
            }
        }
        let cleaned = await cleanTargets(storageIDs)
        isPerformingAll = false

        var parts: [String] = []
        if cleaned.freed > 0 { parts.append(tr("amount.disk", ["size": Fmt.disk(cleaned.freed)])) }
        if killed > 0 { parts.append(tr("amount.ram", ["size": "~" + Fmt.memory(ram)])) }
        var message = parts.isEmpty
            ? tr("banner.nothing_freed")
            : tr("banner.freed", ["parts": parts.joined(separator: tr("list.and_separator"))])
        if !cleaned.errors.isEmpty { message += " · " + tr("banner.errors", count: cleaned.errors.count) }
        showBanner(message)
        await refreshProcesses()
        refreshSystem()
    }

    private func cleanTargets(_ ids: [String]) async -> (freed: Int64, errors: [String]) {
        let selected = targets.filter { ids.contains($0.id) && !busy.contains($0.id) }
        busy.formUnion(selected.map(\.id))
        var freed: Int64 = 0
        var errors: [String] = []
        for target in selected {
            let before = sizes[target.id] ?? 0
            let (targetErrors, after) = await Task.detached(priority: .userInitiated) { () -> ([String], Int64) in
                let errors = Cleaner.clean(target)
                return (errors, SizeCalculator.size(of: target.paths))
            }.value
            sizes[target.id] = after
            freed += max(0, before - after)
            errors += targetErrors
            busy.remove(target.id)
            recompute()
        }
        if freed > 0 {
            totalFreed += freed
            Prefs.defaults.set(Double(totalFreed), forKey: Prefs.Key.totalFreedBytes)
        }
        return (freed, errors)
    }

    private func stopProcesses(rule: ProcessRule, processes: [ProcInfo], key: String) async -> (count: Int, ram: Int64) {
        busy.insert(key)
        defer { busy.remove(key) }
        let pids = Set(processes.map(\.pid))
        let ram = groups.flatMap(\.entries).filter { pids.contains($0.id) }.reduce(0) { $0 + $1.totalRSS }

        if case .quitApp(let bundlePath) = rule.stop, processes.contains(where: \.isAppMainExecutable) {
            // Quit politely so the app can save state; only leftover helpers get signals.
            let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.path == bundlePath }
            apps.forEach { $0.terminate() }
            let helpers = processes.filter { !$0.isAppMainExecutable }
            let killed = helpers.isEmpty ? 0 : await Task.detached { ProcessKiller.terminate(helpers) }.value
            return (apps.count + killed, ram)
        }

        let stop = rule.stop
        let count = await Task.detached(priority: .userInitiated) { () -> Int in
            if case .commandsThenSignal(let commands) = stop {
                for command in commands { Shell.run(command[0], Array(command.dropFirst()), timeout: 60) }
            }
            return ProcessKiller.terminate(processes)
        }.value
        return (count, ram)
    }

    // MARK: Feedback

    private func cleanMessage(freed: Int64, errors: [String]) -> String {
        let base = freed > 0
            ? tr("banner.freed", ["parts": tr("amount.disk", ["size": Fmt.disk(freed)])])
            : tr("banner.nothing_freed")
        guard let first = errors.first else { return base }
        return "\(base) · \(tr("banner.errors", count: errors.count)): \(first)"
    }

    private func showBanner(_ message: String) {
        banner = message
        bannerTask?.cancel()
        bannerTask = Task {
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { banner = nil }
        }
    }

    /// Proactive alerts, with a cooldown per recommendation so it doesn't nag.
    private func notifyIfNeeded() {
        let prefs = PrefsSnapshot.current()
        guard prefs.notifications, Notifier.shared.isAvailable else { return }

        let now = Date().timeIntervalSince1970
        var notifiedAt = Prefs.defaults.dictionary(forKey: Prefs.Key.notifiedAt) as? [String: Double] ?? [:]
        let lowDisk = system.diskFree > 0 && Double(system.diskFree) < prefs.lowDiskGB * 1e9

        let worthy = recommendations.filter { recommendation in
            if let rule = recommendation.rule {
                return recommendation.ramBytes >= Int64(prefs.notifyRAMMB * 1_048_576) || system.memoryTight
                    || rule.suggestEvenIfSmall
            }
            // Partial sizes mid-scan would produce misleading totals.
            return !isScanningStorage && (recommendation.diskBytes >= Int64(prefs.notifyStorageGB * 1e9) || recommendation.urgent)
        }
        let fresh = worthy.filter { recommendation in
            let cooldown: Double = recommendation.isProcess ? 3 * 3600 : 24 * 3600
            return now - (notifiedAt[recommendation.id] ?? 0) > cooldown
        }
        guard !fresh.isEmpty else { return }

        let title: String
        if lowDisk {
            title = tr("notification.title.low_disk", ["size": Fmt.disk(system.diskFree)])
        } else if system.memoryTight {
            title = tr("notification.title.memory", ["size": Fmt.memory(system.memUsed)])
        } else {
            title = tr("notification.title.cleanup")
        }
        let disk = fresh.reduce(0) { $0 + $1.diskBytes }
        let ram = fresh.reduce(0) { $0 + $1.ramBytes }
        var lines = fresh.prefix(3).map { "• \($0.title) — \($0.amountText)" }
        if fresh.count > 3 { lines.append(tr("notification.more", ["count": fresh.count - 3])) }
        var total: [String] = []
        if disk > 0 { total.append(tr("amount.disk", ["size": Fmt.disk(disk)])) }
        if ram > 0 { total.append(tr("amount.ram", ["size": Fmt.memory(ram)])) }
        lines.append(tr("notification.frees", ["parts": total.joined(separator: tr("list.and_separator"))]))

        Notifier.shared.post(
            title: title, body: lines.joined(separator: "\n"),
            recommendationIDs: fresh.filter { $0.risk != .dataLoss }.map(\.id)
        )
        for recommendation in fresh { notifiedAt[recommendation.id] = now }
        Prefs.defaults.set(notifiedAt, forKey: Prefs.Key.notifiedAt)
    }
}
