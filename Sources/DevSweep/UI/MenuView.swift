import SwiftUI

enum MenuTab: String, CaseIterable, Identifiable {
    case suggestions, processes, storage

    var id: String { rawValue }
}

struct MenuView: View {
    @EnvironmentObject private var model: AppModel
    @State private var tab: MenuTab = .suggestions
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            if showingSettings {
                SettingsView {
                    showingSettings = false
                    model.prefsChanged()
                }
            } else {
                HeaderView { showingSettings = true }
                Picker("", selection: $tab) {
                    ForEach(MenuTab.allCases) { tab in
                        Text(label(for: tab)).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                Divider()
                ZStack(alignment: .bottom) {
                    switch tab {
                    case .suggestions: SuggestionsView()
                    case .processes: ProcessesView()
                    case .storage: StorageView()
                    }
                    if let banner = model.banner {
                        BannerView(text: banner)
                            .padding(10)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.2), value: model.banner)
                Divider()
                FooterView()
            }
        }
        .frame(width: 470, height: 640)
        .id(model.languageRevision)
        .onAppear { model.popoverOpened() }
    }

    private func label(for tab: MenuTab) -> String {
        switch tab {
        case .suggestions:
            let count = model.recommendations.count
            return count > 0 ? tr("tab.suggestions_count", ["count": count]) : tr("tab.suggestions")
        case .processes:
            return tr("tab.processes")
        case .storage:
            return tr("tab.storage")
        }
    }
}

private struct HeaderView: View {
    @EnvironmentObject private var model: AppModel
    let openSettings: () -> Void

    var body: some View {
        let system = model.system
        let lowDisk = Double(system.diskFree) < Prefs.defaults.double(forKey: Prefs.Key.lowDiskGB) * 1e9
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(.tint)
                Text("DevSweep").font(.headline)
                Spacer()
                if model.isScanningStorage || model.isScanningProcesses {
                    ProgressView().controlSize(.mini)
                }
                Button(action: model.refreshAll) { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help(tr("header.scan_now"))
                Button(action: openSettings) { Image(systemName: "gearshape") }
                    .buttonStyle(.borderless)
                    .help(tr("header.settings"))
            }
            HStack(spacing: 16) {
                MeterView(
                    title: tr("header.ram", ["pressure": system.pressure.label]),
                    fraction: system.memFraction,
                    caption: "\(Fmt.memory(system.memUsed)) / \(Fmt.memory(system.memTotal))",
                    tint: system.memoryTight ? system.pressure == .critical ? .red : .orange : .green
                )
                MeterView(
                    title: tr("header.disk"),
                    fraction: system.diskTotal > 0 ? 1 - Double(system.diskFree) / Double(system.diskTotal) : 0,
                    caption: tr("header.disk_free", ["size": Fmt.disk(system.diskFree)]),
                    tint: lowDisk ? .red : .blue
                )
            }
        }
        .padding(12)
    }
}

private struct FooterView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let actionable = model.recommendations.filter { $0.risk != .dataLoss }
        let disk = actionable.reduce(0) { $0 + $1.diskBytes }
        let ram = actionable.reduce(0) { $0 + $1.ramBytes }
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(tr("footer.total_freed")).font(.caption2).foregroundStyle(.secondary)
                Text(Fmt.disk(model.totalFreed)).font(.caption.monospacedDigit().weight(.medium))
            }
            Spacer()
            if !actionable.isEmpty {
                Button {
                    Task { await model.performAllRecommended() }
                } label: {
                    HStack(spacing: 6) {
                        if model.isPerformingAll {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "wand.and.stars")
                        }
                        Text(tr("footer.clean_recommended"))
                        Text([disk > 0 ? Fmt.disk(disk) : nil, ram > 0 ? tr("footer.ram", ["size": Fmt.memory(ram)]) : nil]
                            .compactMap { $0 }.joined(separator: " + "))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isPerformingAll)
                .help(tr("footer.clean_recommended_help"))
            }
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help(tr("footer.quit"))
        }
        .padding(12)
    }
}
