import Foundation
import UserNotifications

final class Notifier: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = Notifier()

    private static let category = "DEVSWEEP_CLEANUP"
    private static let cleanAction = "CLEAN_NOW"

    /// UserNotifications only works from a bundled .app, not from `swift run`.
    var isAvailable: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    func setup() {
        guard isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        registerCategories()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Re-run after a language change so the action button is translated.
    func registerCategories() {
        guard isAvailable else { return }
        let clean = UNNotificationAction(identifier: Self.cleanAction, title: tr("notification.action.clean"), options: [])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: [clean], intentIdentifiers: []),
        ])
    }

    func post(title: String, body: String, recommendationIDs: [String]) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Self.category
        content.userInfo = ["recommendations": recommendationIDs]
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let ids = response.notification.request.content.userInfo["recommendations"] as? [String] ?? []
        if response.actionIdentifier == Self.cleanAction {
            Task { @MainActor in await AppModel.shared.performRecommendations(ids: ids) }
        }
        completionHandler()
    }
}
