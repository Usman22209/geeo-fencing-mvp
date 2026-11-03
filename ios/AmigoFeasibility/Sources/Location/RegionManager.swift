import Foundation
import CoreLocation

/// Manages CoreLocation circular region registration and removal per specification section 4.
final class RegionManager {
    static let shared = RegionManager()

    static let regionRequestId = "AMIGO_OUTER_FENCE"

    private let locationManager = CLLocationManager()

    private init() {
        locationManager.delegate = RegionDelegate.shared
    }

    /// Registers a circular geofence region for the configured target location and arm radius.
    func registerGeofence(
        onSuccess: (() -> Void)? = nil,
        onFailure: ((Error) -> Void)? = nil
    ) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            let error = NSError(
                domain: "com.amigo.feasibility",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Region monitoring is not available on this device"]
            )
            Logger.shared.logNote("Region monitoring NOT available on this device.")
            onFailure?(error)
            return
        }

        // Clean up any previously monitored regions first
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }

        let targetLat = Config.shared.targetLatitude
        let targetLng = Config.shared.targetLongitude
        let radius = Config.shared.activeArm.radiusMeters

        let center = CLLocationCoordinate2D(latitude: targetLat, longitude: targetLng)
        let region = CLCircularRegion(
            center: center,
            radius: radius,
            identifier: RegionManager.regionRequestId
        )
        region.notifyOnEntry = true
        region.notifyOnExit = true

        locationManager.startMonitoring(for: region)

        Logger.shared.logNote(
            "Geofence registered: arm=\(Config.shared.activeArm.rawValue), radius=\(radius)m, target=(\(targetLat), \(targetLng))"
        )

        // Query initial state
        locationManager.requestState(for: region)

        onSuccess?()
    }

    /// Removes all monitored geofence regions.
    func removeGeofences(onComplete: (() -> Void)? = nil) {
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        Logger.shared.logNote("Geofence removed.")
        onComplete?()
    }

    var isMonitoring: Bool {
        return locationManager.monitoredRegions.contains { $0.identifier == RegionManager.regionRequestId }
    }
}
