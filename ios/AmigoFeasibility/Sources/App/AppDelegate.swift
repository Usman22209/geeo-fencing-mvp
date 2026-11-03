import UIKit
import CoreLocation
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 1. Ensure UNUserNotificationCenter delegate is set early so banner alerts show in foreground
        UNUserNotificationCenter.current().delegate = NotificationSender.shared

        // 2. Ensure RegionManager and its delegate are initialized early
        _ = RegionManager.shared

        // 3. Track whether this is a cold launch via location event
        if let _ = launchOptions?[.location] {
            RegionDelegate.shared.isColdStart = true
            Logger.shared.logWake(
                trigger: "app_launch_location_event",
                geofenceRequestId: RegionManager.regionRequestId,
                isColdStart: true
            )
        }

        Logger.shared.currentAppState = "background"
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        Logger.shared.currentAppState = "foreground"
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        Logger.shared.currentAppState = "background"
    }
}
