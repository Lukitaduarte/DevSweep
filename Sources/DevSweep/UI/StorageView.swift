import AppKit
import SwiftUI

struct StorageView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        // Unmeasured targets (nil size) stay visible with a spinner; empty ones are hidden.
        let visible = model.targets.filter { (model.sizes[$0.id] ?? 1) > 0 }
        let total = visible.reduce(0) { $0 + (model.sizes[$1.id] ?? 0) }
        let stacks = Array(Set(visible.map(\.stack)))
            .sorted { stackTotal($0, visible) > stackTotal($1, visible) }

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("storage.summary", ["size": Fmt.disk(total)]))
                            .font(.system(size: 12.5, weight: .semibold))
                        Text(scanCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(10)
                .card()

                if model.targets.isEmpty && model.isScanningStorage {
                    ProgressView(tr("storage.searching"))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }
                ForEach(stacks) { stack in
                    StorageSection(stack: stack, targets: visible.filter { $0.stack == stack })
                }
            }
            .padding(12)
            .padding(.bottom, 40)
        }
    }

    private var scanCaption: String {
        if model.isScanningStorage { return tr("storage.measuring") }
        guard let date = model.lastStorageScan else { return tr("storage.not_scanned") }
        return tr("storage.scanned", ["when": Fmt.relative(date)])
    }

    private func stackTotal(_ stack: StackInfo, _ targets: [StorageTarget]) -> Int64 {
        targets.filter { $0.stack == stack }.reduce(0) { $0 + (model.sizes[$1.id] ?? 0) }
    }
}

private struct StorageSection: View {
    @EnvironmentObject private var model: AppModel
    let stack: StackInfo
    let targets: [StorageTarget]

    var body: some View {
        let sorted = targets.sorted { (model.sizes[$0.id] ?? 0) > (model.sizes[$1.id] ?? 0) }
        let total = targets.reduce(0) { $0 + (model.sizes[$1.id] ?? 0) }
        let safeIDs = targets.filter { $0.risk == .safe && (model.sizes[$0.id] ?? 0) > 0 }.map(\.id)
        let nonDestructiveIDs = targets.filter { $0.risk != .dataLoss && (model.sizes[$0.id] ?? 0) > 0 }.map(\.id)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: stack.icon).foregroundStyle(.secondary)
                Text(stack.name).font(.system(size: 12.5, weight: .semibold))
                Text(Fmt.disk(total)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button(tr("storage.clean_non_destructive", ["count": nonDestructiveIDs.count])) {
                        Task { await model.clean(targetIDs: nonDestructiveIDs) }
                    }
                    .disabled(nonDestructiveIDs.isEmpty)
                } label: {
                    Text(tr("storage.clean_safe"))
                } primaryAction: {
                    Task { await model.clean(targetIDs: safeIDs) }
                }
                .menuStyle(.button)
                .controlSize(.small)
                .fixedSize()
                .disabled(nonDestructiveIDs.isEmpty)
                .help(tr("storage.clean_safe_help"))
            }
            VStack(spacing: 0) {
                ForEach(Array(sorted.enumerated()), id: \.element.id) { index, target in
                    if index > 0 { Divider().padding(.leading, 10) }
                    StorageRow(target: target)
                }
            }
            .card()
        }
    }
}

private struct StorageRow: View {
    @EnvironmentObject private var model: AppModel
    let target: StorageTarget

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(target.title).font(.system(size: 12, weight: .medium))
                    Tag(text: target.risk.label, color: target.risk.color)
                    if !target.autoRecommend { Tag(text: tr("storage.manual")) }
                }
                Text(target.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            if let size = model.sizes[target.id] {
                Text(Fmt.disk(size))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
            } else {
                ProgressView().controlSize(.mini)
            }
            ActionButton(
                symbol: target.method.isTrash ? "arrow.up.trash" : "trash",
                confirm: target.risk == .dataLoss,
                busy: model.busy.contains(target.id),
                help: tr("storage.clean_item_help", ["name": target.title])
            ) {
                Task { await model.clean(targetIDs: [target.id]) }
            }
            .disabled(model.sizes[target.id] == nil)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .help(pathsHelp)
        .contextMenu {
            Button(tr("storage.show_in_finder")) {
                NSWorkspace.shared.activateFileViewerSelecting(Array(target.paths.prefix(30)))
            }
        }
    }

    private var pathsHelp: String {
        var lines = target.paths.prefix(8).map { $0.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
        if target.paths.count > 8 { lines.append(tr("storage.more_paths", ["count": target.paths.count - 8])) }
        return lines.joined(separator: "\n")
    }
}

private extension CleanMethod {
    var isTrash: Bool {
        if case .trash = self { return true }
        return false
    }
}
