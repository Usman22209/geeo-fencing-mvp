import Foundation
import UserNotifications

/// Handles dedicated notification delivery and logs notification records per specification.
final class NotificationSender: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationSender()

    static let categoryId = "AMIGO_APPROACH_CATEGORY"

    private override init() {
        super.init()
        setupCategories()
    }

    private func setupCategories() {
        let category = UNNotificationCategory(
            identifier: NotificationSender.categoryId,
            actions: [],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// Posts proximity reminder notification and logs a separate notification record.
    func postNotification(eventIdRef: String, distanceM: Double) {
        let attemptTime = Int64(Date().timeIntervalSince1970 * 1000.0)

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                Logger.shared.logNotification(
                    eventIdRef: eventIdRef,
                    attemptTimeMs: attemptTime,
                    outcome: "blocked_by_permission",
                    errorText: "Notifications not authorized"
                )
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "AMIGO Target Approached!"
            content.body = String(format: "Approached saved target! Distance: %.1fm", distanceM)
            content.sound = .default
            content.categoryIdentifier = NotificationSender.categoryId
            content.userInfo = ["event_id": eventIdRef]

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
            let request = UNNotificationRequest(
                identifier: "amigo_event_\(eventIdRef)",
                content: content,
                trigger: trigger
            )

            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    Logger.shared.logNotification(
                        eventIdRef: eventIdRef,
                        attemptTimeMs: attemptTime,
                        outcome: "exception",
                        errorText: error.localizedDescription
                    )
                } else {
                    Logger.shared.logNotification(
                        eventIdRef: eventIdRef,
                        attemptTimeMs: attemptTime,
                        outcome: "posted"
                    )
                }
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Display banner, play sound, update badge even when the app is in the foreground
        completionHandler([.banner, .sound, .badge])
    }
}
