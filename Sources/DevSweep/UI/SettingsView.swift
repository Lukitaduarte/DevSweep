import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let close: () -> Void

    @EnvironmentObject private var model: AppModel

    @AppStorage(Prefs.Key.notifications) private var notifications = true
    @AppStorage(Prefs.Key.suggestStorageGB) private var suggestStorageGB = 2.0
    @AppStorage(Prefs.Key.notifyStorageGB) private var notifyStorageGB = 5.0
    @AppStorage(Prefs.Key.suggestLimboMB) private var suggestLimboMB = 150.0
    @AppStorage(Prefs.Key.notifyRAMMB) private var notifyRAMMB = 500.0
    @AppStorage(Prefs.Key.lowDiskGB) private var lowDiskGB = 30.0
    @AppStorage(Prefs.Key.inactiveProjectDays) private var inactiveProjectDays = 21
    @AppStorage(Prefs.Key.artifactAgeDays) private var artifactAgeDays = 7
    @AppStorage(Prefs.Key.artifactsToTrash) private var artifactsToTrash = true
    @AppStorage(Prefs.Key.storageScanHours) private var storageScanHours = 6.0
    @AppStorage(Prefs.Key.projectRoots) private var projectRoots = ""

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: close) {
                    Label(tr("settings.back"), systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                Spacer()
                Text(tr("settings.title")).font(.headline)
                Spacer()
                Color.clear.frame(width: 60, height: 1)
            }
            .padding(12)
            Divider()

            Form {
                Section(tr("settings.general")) {
                    Picker(tr("settings.language"), selection: languageBinding) {
                        Text(tr("settings.language_system")).tag("system")
                        ForEach(L10n.shared.availableLanguages, id: \.code) { language in
                            Text(language.name).tag(language.code)
                        }
                    }
                    Toggle(tr("settings.launch_at_login"), isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, enabled in
                            do {
                                if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                                loginError = nil
                            } catch {
                                loginError = tr("settings.launch_error", ["error": error.localizedDescription])
                            }
                        }
                    if let loginError {
                        Text(loginError).font(.caption).foregroundStyle(.red)
                    }
                    Toggle(tr("settings.notifications"), isOn: $notifications)
                    Stepper(value: $storageScanHours, in: 1...48, step: 1) {
                        Text(tr("settings.scan_every", ["hours": Int(storageScanHours)]))
                    }
                }

                Section(tr("settings.suggest_section")) {
                    Stepper(value: $suggestStorageGB, in: 0.5...100, step: 0.5) {
                        Text(tr("settings.suggest_cache", ["size": String(format: "%.1f", suggestStorageGB)]))
                    }
                    Stepper(value: $suggestLimboMB, in: 0...4000, step: 50) {
                        Text(tr("settings.suggest_limbo", ["size": Int(suggestLimboMB)]))
                    }
                    Stepper(value: $lowDiskGB, in: 5...500, step: 5) {
                        Text(tr("settings.low_disk", ["size": Int(lowDiskGB)]))
                    }
                }

                Section(tr("settings.notify_section")) {
                    Stepper(value: $notifyStorageGB, in: 1...200, step: 1) {
                        Text(tr("settings.notify_cache", ["size": Int(notifyStorageGB)]))
                    }
                    Stepper(value: $notifyRAMMB, in: 100...8000, step: 100) {
                        Text(tr("settings.notify_limbo", ["size": Int(notifyRAMMB)]))
                    }
                    Text(tr("settings.notify_note"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(tr("settings.projects_section")) {
                    Stepper(value: $inactiveProjectDays, in: 3...365, step: 1) {
                        Text(tr("settings.inactive_after", ["days": inactiveProjectDays]))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("settings.project_roots")).font(.caption)
                        TextEditor(text: $projectRoots)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(height: 64)
                            .scrollContentBackground(.hidden)
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                    }
                }

                Section(tr("settings.installers_section")) {
                    Stepper(value: $artifactAgeDays, in: 0...365, step: 1) {
                        Text(tr("settings.installers_age", ["days": artifactAgeDays]))
                    }
                    Toggle(tr("settings.installers_trash"), isOn: $artifactsToTrash)
                }

                Section(tr("settings.updates_section")) {
                    UpdateSettings()
                }

                Section(tr("settings.stacks_section")) {
                    stacksSection
                }
            }
            .formStyle(.grouped)
        }
    }

    private struct UpdateSettings: View {
        @ObservedObject private var updater = Updater.shared

        var body: some View {
            LabeledContent(tr("settings.version"), value: Updater.currentVersion)
            if updater.isEnabled {
                Toggle(tr("settings.auto_check"), isOn: Binding(
                    get: { updater.automaticallyChecks },
                    set: { updater.automaticallyChecks = $0 }
                ))
                Toggle(tr("settings.auto_install"), isOn: Binding(
                    get: { updater.automaticallyInstalls },
                    set: { updater.automaticallyInstalls = $0 }
                ))
            } else {
                Text(tr("settings.updates_unavailable"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                if updater.isEnabled {
                    Button(tr("settings.check_now")) { updater.checkForUpdates() }
                }
                Button(tr("settings.releases")) { NSWorkspace.shared.open(Updater.releasesURL) }
            }
        }
    }

    private var languageBinding: Binding<String> {
        Binding(
            get: { Prefs.languagePreference },
            set: { model.setLanguage($0) }
        )
    }

    @ViewBuilder
    private var stacksSection: some View {
        let definitions = model.definitions
        Text(tr("settings.stacks_loaded", [
            "files": definitions.fileCount,
            "processes": definitions.processRules.count,
            "storage": definitions.storage.count,
        ]))
        .font(.caption)
        if !definitions.issues.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(tr("settings.stacks_issues")).font(.caption.bold()).foregroundStyle(.red)
                ForEach(definitions.issues.prefix(10), id: \.self) { issue in
                    Text(issue)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        Text(tr("settings.stacks_note"))
            .font(.caption)
            .foregroundStyle(.secondary)
        HStack {
            Button(tr("settings.stacks_open_folder")) {
                let folder = ResourceLocator.userDirectory(named: "stacks")
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                NSWorkspace.shared.open(folder)
            }
            Button(tr("settings.stacks_reload")) {
                model.refreshAll()
            }
        }
    }
}
