package com.amigo.feasibility.engine

import com.amigo.feasibility.model.DecisionResult
import com.amigo.feasibility.model.FixData
import com.amigo.feasibility.model.ReasonCode
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Pure Kotlin decision engine per specification section 6.
 * Zero Android imports, completely unit-testable.
 */
class DecisionEngine(
    private val params: Params = Params()
) {

    data class Params(
        val maxFixAgeMs: Long = 10_000L,
        val maxAccuracyM: Float = 25.0f,
        val windowN: Int = 5,
        val minValidFixes: Int = 3,
        val proximityM: Double = 40.0,
        val stationaryM: Double = 5.0,
        val minDecreasingSteps: Int = 2,
        val noiseRatio: Double = 0.5
    )

    /**
     * Evaluates a list of recent location fixes against a target location.
     * Fixes should be in chronological order (oldest to newest).
     */
    fun evaluate(
        fixes: List<FixData>,
        targetLat: Double,
        targetLng: Double
    ): DecisionResult {
        // Take at most the most recent windowN fixes
        val window = if (fixes.size > params.windowN) {
            fixes.takeLast(params.windowN)
        } else {
            fixes
        }

        // 1. Check validity: age <= maxFixAgeMs && accuracy <= maxAccuracyM
        val validFixes = window.filter { it.isValid(params.maxFixAgeMs, params.maxAccuracyM) }

        if (validFixes.size < params.minValidFixes) {
            val invalidFixes = window.filter { !it.isValid(params.maxFixAgeMs, params.maxAccuracyM) }
            val staleCount = invalidFixes.count { it.ageMs > params.maxFixAgeMs }
            val lowAccuracyCount = invalidFixes.count { it.accuracyM > params.maxAccuracyM }

            val code = when {
                window.size < params.minValidFixes -> ReasonCode.INSUFFICIENT_FIXES
                staleCount > lowAccuracyCount -> ReasonCode.STALE_FIXES
                lowAccuracyCount > staleCount -> ReasonCode.LOW_ACCURACY
                else -> ReasonCode.INSUFFICIENT_FIXES
            }

            return DecisionResult(
                reasonCode = code,
                isConfirmed = false,
                reasonDetails = "Window has ${validFixes.size}/${window.size} valid fixes (need ${params.minValidFixes}). Stale: $staleCount, LowAcc: $lowAccuracyCount",
                windowCount = window.size,
                validCount = validFixes.size,
                distanceTrend = "unknown",
                netDisplacementM = 0.0,
                latestDistanceM = validFixes.lastOrNull()?.distanceToTargetM,
                inputsUsed = window
            )
        }

        val latestFix = validFixes.last()
        val earliestFix = validFixes.first()

        // 2. Latest valid distance must be within proximityM
        if (latestFix.distanceToTargetM > params.proximityM) {
            return DecisionResult(
                reasonCode = ReasonCode.OUTSIDE_PROXIMITY,
                isConfirmed = false,
                reasonDetails = "Latest distance ${String.format("%.1f", latestFix.distanceToTargetM)}m exceeds proximity threshold ${params.proximityM}m",
                windowCount = window.size,
                validCount = validFixes.size,
                distanceTrend = "outside_threshold",
                netDisplacementM = computeDistanceM(earliestFix.lat, earliestFix.lng, latestFix.lat, latestFix.lng),
                latestDistanceM = latestFix.distanceToTargetM,
                inputsUsed = window
            )
        }

        // 3. Net displacement across the window must exceed stationaryM
        val netDisplacement = computeDistanceM(
            earliestFix.lat,
            earliestFix.lng,
            latestFix.lat,
            latestFix.lng
        )

        if (netDisplacement < params.stationaryM) {
            return DecisionResult(
                reasonCode = ReasonCode.STATIONARY,
                isConfirmed = false,
                reasonDetails = "Net displacement ${String.format("%.2f", netDisplacement)}m is below stationary threshold ${params.stationaryM}m",
                windowCount = window.size,
                validCount = validFixes.size,
                distanceTrend = "stationary",
                netDisplacementM = netDisplacement,
                latestDistanceM = latestFix.distanceToTargetM,
                inputsUsed = window
            )
        }

        // 4. Distance trend: check decreasing steps & net slope
        var decreasingSteps = 0
        var increasingSteps = 0
        for (i in 1 until validFixes.size) {
            val delta = validFixes[i].distanceToTargetM - validFixes[i - 1].distanceToTargetM
            if (delta < -0.1) {
                decreasingSteps++
            } else if (delta > 0.1) {
                increasingSteps++
            }
        }

        val netDistanceChange = latestFix.distanceToTargetM - earliestFix.distanceToTargetM
        val trendDescription = "steps_dec=$decreasingSteps, steps_inc=$increasingSteps, net_delta=${String.format("%.1f", netDistanceChange)}m"

        // Rule 4: Must have at least minDecreasingSteps decreases and a negative net slope
        if (decreasingSteps < params.minDecreasingSteps || netDistanceChange >= 0.0) {
            return DecisionResult(
                reasonCode = ReasonCode.NOT_APPROACHING,
                isConfirmed = false,
                reasonDetails = "Distance trend not decreasing: $trendDescription (need >= ${params.minDecreasingSteps} decreasing steps and negative slope)",
                windowCount = window.size,
                validCount = validFixes.size,
                distanceTrend = trendDescription,
                netDisplacementM = netDisplacement,
                latestDistanceM = latestFix.distanceToTargetM,
                inputsUsed = window
            )
        }

        // 5. Conflicting checks:
        // - Distance changes smaller than accuracy noise
        // - Large conflicting oscillations
        val avgAccuracy = validFixes.map { it.accuracyM.toDouble() }.average()
        val approachMagnitude = -netDistanceChange // positive value of how much we approached

        if (approachMagnitude < (avgAccuracy * params.noiseRatio)) {
            return DecisionResult(
                reasonCode = ReasonCode.CONFLICTING,
                isConfirmed = false,
                reasonDetails = "Approach magnitude (${String.format("%.1f", approachMagnitude)}m) is smaller than accuracy noise threshold (${String.format("%.1f", avgAccuracy * params.noiseRatio)}m, avgAcc=${String.format("%.1f", avgAccuracy)}m)",
                windowCount = window.size,
                validCount = validFixes.size,
                distanceTrend = "noise_dominated",
                netDisplacementM = netDisplacement,
                latestDistanceM = latestFix.distanceToTargetM,
                inputsUsed = window
            )
        }

        if (increasingSteps > decreasingSteps) {
            return DecisionResult(
                reasonCode = ReasonCode.CONFLICTING,
                isConfirmed = false,
                reasonDetails = "Oscillating fixes disagree: $trendDescription",
                windowCount = window.size,
                validCount = validFixes.size,
                distanceTrend = "oscillating",
                netDisplacementM = netDisplacement,
                latestDistanceM = latestFix.distanceToTargetM,
                inputsUsed = window
            )
        }

        // 6. EVENT_CONFIRMED
        return DecisionResult(
            reasonCode = ReasonCode.EVENT_CONFIRMED,
            isConfirmed = true,
            reasonDetails = "Proximity and sustained approach confirmed: latest=${String.format("%.1f", latestFix.distanceToTargetM)}m, netDisplacement=${String.format("%.1f", netDisplacement)}m, $trendDescription",
            windowCount = window.size,
            validCount = validFixes.size,
            distanceTrend = trendDescription,
            netDisplacementM = netDisplacement,
            latestDistanceM = latestFix.distanceToTargetM,
            inputsUsed = window
        )
    }

    companion object {
        /**
         * Pure Kotlin Great-Circle Haversine distance calculation in meters.
         */
        fun computeDistanceM(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
            val r = 6371000.0 // Earth radius in meters
            val dLat = Math.toRadians(lat2 - lat1)
            val dLon = Math.toRadians(lon2 - lon1)
            val a = sin(dLat / 2).pow(2) +
                    cos(Math.toRadians(lat1)) * cos(Math.toRadians(lat2)) *
                    sin(dLon / 2).pow(2)
            val c = 2 * atan2(sqrt(a), sqrt(1 - a))
            return r * c
        }
    }
}

