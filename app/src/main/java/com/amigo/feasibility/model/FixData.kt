package com.amigo.feasibility.model

/**
 * Pure Kotlin representation of a location fix.
 * Free of Android framework dependencies so DecisionEngine can be unit-tested in isolation.
 */
data class FixData(
    val lat: Double,
    val lng: Double,
    val accuracyM: Float,
    val timestampMs: Long,
    val receiptWallMs: Long,
    val ageMs: Long,
    val provider: String,
    val distanceToTargetM: Double
) {
    fun isValid(maxAgeMs: Long, maxAccuracyM: Float): Boolean {
        return ageMs <= maxAgeMs && accuracyM <= maxAccuracyM
    }
}

