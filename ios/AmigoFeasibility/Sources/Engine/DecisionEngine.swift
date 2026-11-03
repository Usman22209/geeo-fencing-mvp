import Foundation

/// Pure Swift decision engine per specification section 6.
/// Zero UIKit or CoreLocation imports, completely unit-testable in isolation.
final class DecisionEngine {

    struct Params: Equatable {
        var maxFixAgeMs: Int64 = 10_000
        var maxAccuracyM: Float = 25.0
        var windowN: Int = 5
        var minValidFixes: Int = 3
        var proximityM: Double = 40.0
        var stationaryM: Double = 5.0
        var minDecreasingSteps: Int = 2
        var noiseRatio: Double = 0.5

        init(
            maxFixAgeMs: Int64 = 10_000,
            maxAccuracyM: Float = 25.0,
            windowN: Int = 5,
            minValidFixes: Int = 3,
            proximityM: Double = 40.0,
            stationaryM: Double = 5.0,
            minDecreasingSteps: Int = 2,
            noiseRatio: Double = 0.5
        ) {
            self.maxFixAgeMs = maxFixAgeMs
            self.maxAccuracyM = maxAccuracyM
            self.windowN = windowN
            self.minValidFixes = minValidFixes
            self.proximityM = proximityM
            self.stationaryM = stationaryM
            self.minDecreasingSteps = minDecreasingSteps
            self.noiseRatio = noiseRatio
        }
    }

    private let params: Params

    init(params: Params = Params()) {
        self.params = params
    }

    /// Evaluates a list of recent location fixes against a target location.
    /// Fixes should be in chronological order (oldest to newest).
    func evaluate(
        fixes: [FixData],
        targetLat: Double,
        targetLng: Double
    ) -> DecisionResult {
        // Take at most the most recent windowN fixes
        let window = fixes.count > params.windowN ? Array(fixes.suffix(params.windowN)) : fixes

        // 1. Check validity: age <= maxFixAgeMs && accuracy <= maxAccuracyM
        let validFixes = window.filter { $0.isValid(maxAgeMs: params.maxFixAgeMs, maxAccuracyM: params.maxAccuracyM) }

        if validFixes.count < params.minValidFixes {
            let invalidFixes = window.filter { !$0.isValid(maxAgeMs: params.maxFixAgeMs, maxAccuracyM: params.maxAccuracyM) }
            let staleCount = invalidFixes.filter { $0.ageMs > params.maxFixAgeMs }.count
            let lowAccuracyCount = invalidFixes.filter { $0.accuracyM > params.maxAccuracyM }.count

            let code: ReasonCode
            if window.count < params.minValidFixes {
                code = .insufficientFixes
            } else if staleCount > lowAccuracyCount {
                code = .staleFixes
            } else if lowAccuracyCount > staleCount {
                code = .lowAccuracy
            } else {
                code = .insufficientFixes
            }

            return DecisionResult(
                reasonCode: code,
                isConfirmed: false,
                reasonDetails: "Window has \(validFixes.count)/\(window.count) valid fixes (need \(params.minValidFixes)). Stale: \(staleCount), LowAcc: \(lowAccuracyCount)",
                windowCount: window.count,
                validCount: validFixes.count,
                distanceTrend: "unknown",
                netDisplacementM: 0.0,
                latestDistanceM: validFixes.last?.distanceToTargetM,
                inputsUsed: window
            )
        }

        guard let latestFix = validFixes.last, let earliestFix = validFixes.first else {
            return DecisionResult(
                reasonCode: .insufficientFixes,
                isConfirmed: false,
                reasonDetails: "No valid fixes found",
                windowCount: window.count,
                validCount: 0,
                distanceTrend: "unknown",
                netDisplacementM: 0.0,
                latestDistanceM: nil,
                inputsUsed: window
            )
        }

        // 2. Latest valid distance must be within proximityM
        if latestFix.distanceToTargetM > params.proximityM {
            let netDisplacement = DecisionEngine.computeDistanceM(
                lat1: earliestFix.lat,
                lon1: earliestFix.lng,
                lat2: latestFix.lat,
                lon2: latestFix.lng
            )
            return DecisionResult(
                reasonCode: .outsideProximity,
                isConfirmed: false,
                reasonDetails: String(format: "Latest distance %.1fm exceeds proximity threshold %.1fm", latestFix.distanceToTargetM, params.proximityM),
                windowCount: window.count,
                validCount: validFixes.count,
                distanceTrend: "outside_threshold",
                netDisplacementM: netDisplacement,
                latestDistanceM: latestFix.distanceToTargetM,
                inputsUsed: window
            )
        }

        // 3. Net displacement across the window must exceed stationaryM
        let netDisplacement = DecisionEngine.computeDistanceM(
            lat1: earliestFix.lat,
            lon1: earliestFix.lng,
            lat2: latestFix.lat,
            lon2: latestFix.lng
        )

        if netDisplacement < params.stationaryM {
            return DecisionResult(
                reasonCode: .stationary,
                isConfirmed: false,
                reasonDetails: String(format: "Net displacement %.2fm is below stationary threshold %.1fm", netDisplacement, params.stationaryM),
                windowCount: window.count,
                validCount: validFixes.count,
                distanceTrend: "stationary",
                netDisplacementM: netDisplacement,
                latestDistanceM: latestFix.distanceToTargetM,
                inputsUsed: window
            )
        }

        // 4. Distance trend: check decreasing steps & net slope
        var decreasingSteps = 0
        var increasingSteps = 0
        if validFixes.count > 1 {
            for i in 1..<validFixes.count {
                let delta = validFixes[i].distanceToTargetM - validFixes[i - 1].distanceToTargetM
                if delta < -0.1 {
                    decreasingSteps += 1
                } else if delta > 0.1 {
                    increasingSteps += 1
                }
            }
        }

        let netDistanceChange = latestFix.distanceToTargetM - earliestFix.distanceToTargetM
        let trendDescription = String(format: "steps_dec=%d, steps_inc=%d, net_delta=%.1fm", decreasingSteps, increasingSteps, netDistanceChange)

        // Rule 4: Must have at least minDecreasingSteps decreases and a negative net slope
        if decreasingSteps < params.minDecreasingSteps || netDistanceChange >= 0.0 {
            return DecisionResult(
                reasonCode: .notApproaching,
                isConfirmed: false,
                reasonDetails: "Distance trend not decreasing: \(trendDescription) (need >= \(params.minDecreasingSteps) decreasing steps and negative slope)",
                windowCount: window.count,
                validCount: validFixes.count,
                distanceTrend: trendDescription,
                netDisplacementM: netDisplacement,
                latestDistanceM: latestFix.distanceToTargetM,
                inputsUsed: window
            )
        }

        // 5. Conflicting checks:
        // - Distance changes smaller than accuracy noise
        // - Large conflicting oscillations
        let totalAccuracy = validFixes.reduce(0.0) { $0 + Double($1.accuracyM) }
        let avgAccuracy = totalAccuracy / Double(validFixes.count)
        let approachMagnitude = -netDistanceChange // positive value of how much we approached

        if approachMagnitude < (avgAccuracy * params.noiseRatio) {
            return DecisionResult(
                reasonCode: .conflicting,
                isConfirmed: false,
                reasonDetails: String(format: "Approach magnitude (%.1fm) is smaller than accuracy noise threshold (%.1fm, avgAcc=%.1fm)", approachMagnitude, avgAccuracy * params.noiseRatio, avgAccuracy),
                windowCount: window.count,
                validCount: validFixes.count,
                distanceTrend: "noise_dominated",
                netDisplacementM: netDisplacement,
                latestDistanceM: latestFix.distanceToTargetM,
                inputsUsed: window
            )
        }

        if increasingSteps > decreasingSteps {
            return DecisionResult(
                reasonCode: .conflicting,
                isConfirmed: false,
                reasonDetails: "Oscillating fixes disagree: \(trendDescription)",
                windowCount: window.count,
                validCount: validFixes.count,
                distanceTrend: "oscillating",
                netDisplacementM: netDisplacement,
                latestDistanceM: latestFix.distanceToTargetM,
                inputsUsed: window
            )
        }

        // 6. EVENT_CONFIRMED
        return DecisionResult(
            reasonCode: .eventConfirmed,
            isConfirmed: true,
            reasonDetails: String(format: "Proximity and sustained approach confirmed: latest=%.1fm, netDisplacement=%.1fm, %@", latestFix.distanceToTargetM, netDisplacement, trendDescription),
            windowCount: window.count,
            validCount: validFixes.count,
            distanceTrend: trendDescription,
            netDisplacementM: netDisplacement,
            latestDistanceM: latestFix.distanceToTargetM,
            inputsUsed: window
        )
    }

    /// Pure Swift Great-Circle Haversine distance calculation in meters.
    static func computeDistanceM(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let r = 6371000.0 // Earth radius in meters
        let dLat = (lat2 - lat1) * .pi / 180.0
        let dLon = (lon2 - lon1) * .pi / 180.0
        let lat1Rad = lat1 * .pi / 180.0
        let lat2Rad = lat2 * .pi / 180.0

        let sinHalfDLat = sin(dLat / 2.0)
        let sinHalfDLon = sin(dLon / 2.0)

        let a = sinHalfDLat * sinHalfDLat +
                cos(lat1Rad) * cos(lat2Rad) *
                sinHalfDLon * sinHalfDLon
        let c = 2.0 * atan2(sqrt(a), sqrt(max(0.0, 1.0 - a)))
        return r * c
    }
}
