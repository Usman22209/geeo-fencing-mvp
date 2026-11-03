import Foundation
import CoreLocation

/// Handles geofence region transitions per specification section 4 & 5.
/// First action on entry: write a wake record! Then start the bounded location burst.
final class RegionDelegate: NSObject, CLLocationManagerDelegate {
    static let shared = RegionDelegate()

    var isColdStart = false
    private var lastKnownState: CLRegionState = .unknown

    override private init() {
        super.init()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        let wasColdStart = isColdStart
        isColdStart = false

        lastKnownState = .inside

        // 1. FIRST ACTION: Write the wake record per specification section 4
        Logger.shared.logWake(
            trigger: "geofence_enter",
            geofenceRequestId: region.identifier,
            isColdStart: wasColdStart
        )

        // 2. Start high-accuracy burst
        BurstManager.shared.startBurst(trigger: "geofence_enter")
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        let wasColdStart = isColdStart
        isColdStart = false

        lastKnownState = .outside

        Logger.shared.logWake(
            trigger: "geofence_exit",
            geofenceRequestId: region.identifier,
            isColdStart: wasColdStart
        )

        // If a burst was active when leaving the geofence, stop it cleanly
        if BurstManager.shared.isActive {
            BurstManager.shared.stopBurst()
        }

        // Re-arm EventStore on physical exit
        EventStore.shared.onExited()
        Logger.shared.logNote("Device exited geofence (\(region.identifier)). EventStore re-armed! Next ENTER will trigger fresh burst and notification.")
    }

    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        let previousState = lastKnownState
        lastKnownState = state

        switch state {
        case .inside:
            Logger.shared.logNote("Region state determined: INSIDE (\(region.identifier))")

            // Mimic Android's INITIAL_TRIGGER_ENTER:
            // In Android, Google Play Services GeofencingRequest.Builder().setInitialTrigger(INITIAL_TRIGGER_ENTER)
            // immediately fires an ENTER event if the device is already inside the geofence on registration.
            // On iOS, CLCircularRegion does not call didEnterRegion if already inside.
            // Therefore, if the device is inside on arming or transitions to inside, immediately wake and start burst!
            if !BurstManager.shared.isActive && EventStore.shared.isArmed() {
                let wasCold = isColdStart
                isColdStart = false
                let triggerName = (previousState == .outside) ? "geofence_enter" : "geofence_initial_inside"
                Logger.shared.logWake(
                    trigger: triggerName,
                    geofenceRequestId: region.identifier,
                    isColdStart: wasCold
                )
                BurstManager.shared.startBurst(trigger: triggerName)
            }

        case .outside:
            Logger.shared.logNote("Region state determined: OUTSIDE (\(region.identifier))")
            if BurstManager.shared.isActive {
                BurstManager.shared.stopBurst()
            }
            if previousState == .inside {
                EventStore.shared.onExited()
                Logger.shared.logNote("Device moved outside geofence (\(region.identifier)). EventStore re-armed!")
            }

        case .unknown:
            Logger.shared.logNote("Region state determined: UNKNOWN (\(region.identifier))")
        }
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        Logger.shared.logNote("Region monitoring FAILED for \(region?.identifier ?? "unknown"): \(error.localizedDescription)")
    }
}
