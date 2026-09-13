import SwiftUI

struct ProcessesView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let tools = model.groups.filter { !$0.rule.isApp }
            .sorted { ($0.limboRSS, $0.totalRSS) > ($1.limboRSS, $1.totalRSS) }
        let apps = model.groups.filter(\.rule.isApp)
        let limboCount = model.groups.reduce(0) { $0 + $1.limboEntries.count }
        let limboRAM = model.groups.reduce(0) { $0 + $1.limboRSS }
        let toolRAM = tools.reduce(0) { $0 + $1.totalRSS }

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("processes.dev_tools")).font(.system(size: 12.5, weight: .semibold))
                        Text(tr("processes.summary", [
                            "ram": Fmt.memory(toolRAM),
                            "count": tools.reduce(0) { $0 + $1.processCount },
                            "limbo": limboCount,
                        ]))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if limboCount > 0 {
                        Button {
                            Task { await model.stopAllLimbo() }
                        } label: {
                            HStack(spacing: 5) {
                                if model.busy.contains("limbo-all") {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Image(systemName: "bolt.horizontal.circle")
                                }
                                Text(tr("processes.stop_limbo", ["ram": Fmt.memory(limboRAM)]))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .controlSize(.small)
                        .disabled(model.busy.contains("limbo-all"))
                    }
                }
                .padding(10)
                .card()

                if tools.isEmpty && !model.isScanningProcesses {
                    Text(tr("processes.none"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
                ForEach(tools) { ProcessGroupView(group: $0) }

                if !apps.isEmpty {
                    Text(tr("processes.apps_header"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 10)
                        .padding(.leading, 2)
                    ForEach(apps) { ProcessGroupView(group: $0) }
                }
            }
            .padding(12)
            .padding(.bottom, 40)
        }
    }
}

private struct ProcessGroupView: View {
    @EnvironmentObject private var model: AppModel
    let group: ProcessGroup
    @State private var expanded = false

    var body: some View {
        let limbo = group.limboEntries
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 12)
                Image(systemName: group.rule.stack.icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(group.rule.title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                        if !limbo.isEmpty {
                            Tag(text: tr("processes.in_limbo", ["count": limbo.count]), color: .orange)
                        }
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if !limbo.isEmpty {
                    ActionButton(
                        title: tr("processes.limbo_button"), symbol: "xmark.circle",
                        busy: model.busy.contains("limbo-\(group.id)"),
                        help: tr("processes.limbo_help")
                    ) {
                        Task { await model.stop(rule: group.rule, processes: limbo.map(\.process), key: "limbo-\(group.id)") }
                    }
                }
                ActionButton(
                    symbol: group.rule.isApp ? "power" : "stop.circle",
                    confirm: true,
                    busy: model.busy.contains("all-\(group.id)"),
                    help: group.rule.isApp ? tr("processes.quit_app_help") : tr("processes.stop_all_help")
                ) {
                    Task { await model.stop(rule: group.rule, processes: group.entries.map(\.process), key: "all-\(group.id)") }
                }
            }
            .padding(10)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } }

            if expanded {
                Divider().padding(.horizontal, 10)
                ForEach(group.entries) { entry in
                    ProcessEntryRow(group: group, entry: entry)
                }
            }
        }
        .card()
    }

    private var subtitle: String {
        var parts = [tr("processes.count", ["count": group.processCount]), Fmt.memory(group.totalRSS)]
        if !group.ports.isEmpty {
            parts.append(group.ports.prefix(4).map { ":\($0)" }.joined(separator: " "))
        }
        return parts.joined(separator: " · ")
    }
}

private struct ProcessEntryRow: View {
    @EnvironmentObject private var model: AppModel
    let group: ProcessGroup
    let entry: ProcEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("PID \(entry.process.pid)").font(.caption.monospaced())
                    if entry.isLimbo { Tag(text: tr("processes.tag_limbo"), color: .orange) }
                    if entry.process.isOrphan && !entry.isLimbo { Tag(text: tr("processes.tag_orphan")) }
                    ForEach(entry.ports.prefix(3), id: \.self) { Tag(text: ":\($0)", color: .blue) }
                    if entry.descendantCount > 0 {
                        Text(tr("processes.children", ["count": entry.descendantCount]))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(tr("processes.running_for", ["age": Fmt.duration(entry.process.elapsed)]))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text(entry.process.shortCommand)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                if let reason = entry.reason {
                    Text(reason).font(.caption2).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 6)
            Text(Fmt.memory(entry.totalRSS))
                .font(.caption.monospacedDigit())
                .padding(.top, 2)
            ActionButton(
                symbol: "xmark",
                confirm: !entry.isLimbo,
                busy: model.busy.contains("pid-\(entry.id)"),
                help: tr("processes.stop_one_help")
            ) {
                Task { await model.stop(rule: group.rule, processes: [entry.process], key: "pid-\(entry.id)") }
            }
        }
        .padding(.leading, 30)
        .padding(.trailing, 10)
        .padding(.vertical, 7)
    }
}
