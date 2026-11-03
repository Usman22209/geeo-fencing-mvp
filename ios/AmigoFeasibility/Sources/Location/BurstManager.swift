import Foundation
import CoreLocation
import UIKit

/// Bounded high-accuracy location burst manager per specification section 4.
/// Gathers fresh GPS fixes, evaluates proximity approach via DecisionEngine,
/// triggers EventStore and NotificationSender on confirmation, and cleanly terminates.
final class BurstManager: NSObject, CLLocationManagerDelegate {
    static let shared = BurstManager()

    private let locationManager = CLLocationManager()
    private var isBursting = false
    private var burstStartTime: TimeInterval = 0
    private var burstTimer: Timer?
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid

    private var collectedFixes: [FixData] = []
    private let decisionEngine = DecisionEngine(
        params: DecisionEngine.Params(
            maxFixAgeMs: Config.maxFixAgeMs,
            maxAccuracyM: Config.maxAccuracyM,
            windowN: Config.windowN,
            minValidFixes: Config.minValidFixes,
            proximityM: Config.proximityM,
            stationaryM: Config.stationaryM,
            minDecreasingSteps: Config.minDecreasingSteps,
            noiseRatio: Config.noiseRatio
        )
    )

    var onBurstStatusChanged: ((Bool) -> Void)?

    override private init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = true
    }

    /// Starts a high-accuracy GPS burst.
    func startBurst(trigger: String) {
        guard !isBursting else {
            Logger.shared.logNote("Burst already active. Ignoring new trigger: \(trigger)")
            return
        }

        isBursting = true
        collectedFixes.removeAll()
        burstStartTime = ProcessInfo.processInfo.systemUptime

        // Begin background task to guarantee execution time even if screen is locked
        beginBackgroundTask()

        Logger.shared.logNote("BurstManager active: bounded window of \(Config.burstDurationMs)ms started. Trigger: \(trigger)")
        DispatchQueue.main.async { [weak self] in
            self?.onBurstStatusChanged?(true)
        }

        // Schedule timeout
        let timeoutSeconds = Double(Config.burstDurationMs) / 1000.0
        DispatchQueue.main.async { [weak self] in
            self?.burstTimer?.invalidate()
            self?.burstTimer = Timer.scheduledTimer(withTimeInterval: timeoutSeconds, repeats: false) { [weak self] _ in
                Logger.shared.logNote("Burst timeout reached (\(Config.burstDurationMs)ms). Stopping burst.")
                self?.stopBurst()
            }
        }

        locationManager.startUpdatingLocation()
    }

    /// Stops the location burst cleanly.
    func stopBurst() {
        guard isBursting else { return }
        isBursting = false

        DispatchQueue.main.async { [weak self] in
            self?.burstTimer?.invalidate()
            self?.burstTimer = nil
            self?.onBurstStatusChanged?(false)
        }

        locationManager.stopUpdatingLocation()

        let durationMs = Int64((ProcessInfo.processInfo.systemUptime - burstStartTime) * 1000.0)
        Logger.shared.logBattery(note: "Burst ended: duration=\(durationMs)ms, total_fixes=\(collectedFixes.count)")

        endBackgroundTask()
    }

    // MARK: - Background Task Management

    private func beginBackgroundTask() {
        endBackgroundTask()
        backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "AMIGOLocationBurst") { [weak self] in
            Logger.shared.logNote("Background task time expired by iOS. Stopping burst.")
            self?.stopBurst()
        }
    }

    private func endBackgroundTask() {
        if backgroundTaskId != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskId)
            backgroundTaskId = .invalid
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            processLocationFix(location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Logger.shared.logNote("Location updates error: \(error.localizedDescription)")
    }

    private func processLocationFix(_ loc: CLLocation) {
        let nowWall = Int64(Date().timeIntervalSince1970 * 1000.0)
        let fixTimestamp = Int64(loc.timestamp.timeIntervalSince1970 * 1000.0)
        let ageMs = max(0, nowWall - fixTimestamp)

        let targetLat = Config.shared.targetLatitude
        let targetLng = Config.shared.targetLongitude

        let distanceToTarget = DecisionEngine.computeDistanceM(
            lat1: loc.coordinate.latitude,
            lon1: loc.coordinate.longitude,
            lat2: targetLat,
            lon2: targetLng
        )

        let fixData = FixData(
            lat: loc.coordinate.latitude,
            lng: loc.coordinate.longitude,
            accuracyM: Float(loc.horizontalAccuracy),
            timestampMs: fixTimestamp,
            receiptWallMs: nowWall,
            ageMs: ageMs,
            provider: "corelocation",
            distanceToTargetM: distanceToTarget
        )

        // 1. Log fix record
        Logger.shared.logFix(fix: fixData)
        collectedFixes.append(fixData)

        // 2. Evaluate decision engine over sliding window
        let decision = decisionEngine.evaluate(
            fixes: collectedFixes,
            targetLat: targetLat,
            targetLng: targetLng
        )

        // 3. Log decision record
        Logger.shared.logDecision(result: decision)

        // 4. Handle positive decision
        if decision.isConfirmed {
            Logger.shared.logNote("Positive approach confirmed by engine! Proceeding to EventStore.")
            if let eventId = EventStore.shared.recordEventIfConfirmed(result: decision) {
                NotificationSender.shared.postNotification(
                    eventIdRef: eventId,
                    distanceM: distanceToTarget
                )
                // Stop burst early upon confirmed event
                stopBurst()
            }
        }
    }

    var isActive: Bool {
        return isBursting
    }
}
