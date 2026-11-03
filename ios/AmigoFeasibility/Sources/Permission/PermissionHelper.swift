import Foundation
import CoreLocation
import UserNotifications
import UIKit

/// Permission management for Location and Notifications on iOS.
/// Handles two-tier location authorization flow (When In Use -> Always).
final class PermissionHelper: NSObject, CLLocationManagerDelegate {
    static let shared = PermissionHelper()

    private var locationManager: CLLocationManager?
    private var pendingAlwaysRequest = false

    override private init() {
        super.init()
    }

    // MARK: - Synchronous Checks

    static func hasFineLocation() -> Bool {
        let status = CLLocationManager().authorizationStatus
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }

    static func hasAlwaysLocation() -> Bool {
        return CLLocationManager().authorizationStatus == .authorizedAlways
    }

    static func hasNotificationPermission() -> Bool {
        var granted = false
        let semaphore = DispatchSemaphore(value: 0)
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            granted = (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 0.5)
        return granted
    }

    func checkNotificationSettings(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                completion(settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
            }
        }
    }

    // MARK: - Request Flow

    func requestPermissions() {
        if locationManager == nil {
            let manager = CLLocationManager()
            manager.delegate = self
            self.locationManager = manager
        }

        let status = locationManager?.authorizationStatus ?? .notDetermined

        switch status {
        case .notDetermined:
            locationManager?.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            locationManager?.requestAlwaysAuthorization()
        default:
            break
        }

        requestNotificationAuthorization()
    }

    func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                Logger.shared.logPermissionChange(
                    permission: "notifications",
                    oldState: false,
                    newState: granted
                )
            }
        }
    }

    func requestAlwaysLocation() {
        if locationManager == nil {
            let manager = CLLocationManager()
            manager.delegate = self
            self.locationManager = manager
        }
        locationManager?.requestAlwaysAuthorization()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let hasFine = (status == .authorizedWhenInUse || status == .authorizedAlways)
        let hasAlways = (status == .authorizedAlways)

        Logger.shared.logPermissionChange(
            permission: "fine_location",
            oldState: false,
            newState: hasFine
        )
        Logger.shared.logPermissionChange(
            permission: "background_location",
            oldState: false,
            newState: hasAlways
        )

        if status == .authorizedWhenInUse && pendingAlwaysRequest {
            pendingAlwaysRequest = false
            manager.requestAlwaysAuthorization()
        }
    }

    static func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
}
