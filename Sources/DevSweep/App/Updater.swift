import AppKit
import Foundation
import Sparkle

/// Self-updates through Sparkle, reading the appcast attached to the latest GitHub release.
@MainActor
final class Updater: NSObject, ObservableObject {
    static let shared = Updater()

    /// Version offered by the appcast, shown as a card in Suggestions.
    @Published private(set) var availableVersion: String?
    /// False in builds without a signing key (local builds, forks): they only link to Releases.
    @Published private(set) var isEnabled = false

    private var controller: SPUStandardUpdaterController?

    static var repository: String {
        Bundle.main.object(forInfoDictionaryKey: "DevSweepRepository") as? String ?? "Lukitaduarte/DevSweep"
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    static var releasesURL: URL {
        URL(string: "https://github.com/\(repository)/releases")!
    }

    static func releaseURL(for version: String) -> URL {
        URL(string: "https://github.com/\(repository)/releases/tag/v\(version)") ?? releasesURL
    }

    func start() {
        let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        // Sparkle refuses updates it can't verify, so don't even start without a key.
        guard Bundle.main.bundleURL.pathExtension == "app", !publicKey.isEmpty, controller == nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        isEnabled = true
    }

    func checkForUpdates() {
        // Menu bar apps aren't frontmost; bring Sparkle's window forward.
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            objectWillChange.send()
            controller?.updater.automaticallyChecksForUpdates = newValue
        }
    }

    var automaticallyInstalls: Bool {
        get { controller?.updater.automaticallyDownloadsUpdates ?? false }
        set {
            objectWillChange.send()
            controller?.updater.automaticallyDownloadsUpdates = newValue
        }
    }
}

extension Updater: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        Task { @MainActor in self.availableVersion = version }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in self.availableVersion = nil }
    }
}

extension Updater: SPUStandardUserDriverDelegate {
    /// Scheduled checks surface as a card in DevSweep instead of stealing focus with a window.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }
}
