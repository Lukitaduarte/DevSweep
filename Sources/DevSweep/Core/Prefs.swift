import Foundation

enum Prefs {
    static let defaults = UserDefaults.standard

    enum Key {
        static let language = "language"
        static let notifications = "notificationsEnabled"
        static let suggestStorageGB = "suggestStorageGB"
        static let notifyStorageGB = "notifyStorageGB"
        static let suggestLimboMB = "suggestLimboMB"
        static let notifyRAMMB = "notifyRAMMB"
        static let lowDiskGB = "lowDiskGB"
        static let inactiveProjectDays = "inactiveProjectDays"
        static let artifactAgeDays = "artifactAgeDays"
        static let artifactsToTrash = "artifactsToTrash"
        static let projectRoots = "projectRoots"
        static let storageScanHours = "storageScanHours"
        static let totalFreedBytes = "totalFreedBytes"
        static let notifiedAt = "notifiedAt"
    }

    static func register() {
        defaults.register(defaults: [
            Key.language: "system",
            Key.notifications: true,
            Key.suggestStorageGB: 2.0,
            Key.notifyStorageGB: 5.0,
            Key.suggestLimboMB: 150.0,
            Key.notifyRAMMB: 500.0,
            Key.lowDiskGB: 30.0,
            Key.inactiveProjectDays: 21,
            Key.artifactAgeDays: 7,
            Key.artifactsToTrash: true,
            Key.projectRoots: defaultProjectRoots.joined(separator: "\n"),
            Key.storageScanHours: 6.0,
        ])
    }

    /// "system" or a locale code such as "pt-BR".
    static var languagePreference: String {
        defaults.string(forKey: Key.language) ?? "system"
    }

    static var defaultProjectRoots: [String] {
        let candidates = [
            "~/Project", "~/Projects", "~/Developer", "~/dev", "~/code",
            "~/workspace", "~/src", "~/StudioProjects", "~/git", "~/repos",
        ]
        let existing = candidates.filter { FileManager.default.fileExists(atPath: expandTilde($0)) }
        return existing.isEmpty ? ["~/Projects"] : existing
    }
}

/// Immutable copy of the preferences, safe to hand to background scans.
struct PrefsSnapshot: Sendable {
    var notifications: Bool
    var suggestStorageGB: Double
    var notifyStorageGB: Double
    var suggestLimboMB: Double
    var notifyRAMMB: Double
    var lowDiskGB: Double
    var inactiveProjectDays: Int
    var artifactAgeDays: Int
    var artifactsToTrash: Bool
    var projectRoots: [String]

    static func current() -> PrefsSnapshot {
        let d = Prefs.defaults
        return PrefsSnapshot(
            notifications: d.bool(forKey: Prefs.Key.notifications),
            suggestStorageGB: d.double(forKey: Prefs.Key.suggestStorageGB),
            notifyStorageGB: d.double(forKey: Prefs.Key.notifyStorageGB),
            suggestLimboMB: d.double(forKey: Prefs.Key.suggestLimboMB),
            notifyRAMMB: d.double(forKey: Prefs.Key.notifyRAMMB),
            lowDiskGB: d.double(forKey: Prefs.Key.lowDiskGB),
            inactiveProjectDays: d.integer(forKey: Prefs.Key.inactiveProjectDays),
            artifactAgeDays: d.integer(forKey: Prefs.Key.artifactAgeDays),
            artifactsToTrash: d.bool(forKey: Prefs.Key.artifactsToTrash),
            projectRoots: (d.string(forKey: Prefs.Key.projectRoots) ?? "")
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )
    }
}
