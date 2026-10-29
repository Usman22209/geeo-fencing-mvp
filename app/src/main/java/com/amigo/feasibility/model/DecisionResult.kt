package com.amigo.feasibility.model

/**
 * Result of evaluating a sliding window of fixes in DecisionEngine.
 * Pure Kotlin data class.
 */
data class DecisionResult(
    val reasonCode: ReasonCode,
    val isConfirmed: Boolean,
    val reasonDetails: String,
    val windowCount: Int,
    val validCount: Int,
    val distanceTrend: String,
    val netDisplacementM: Double,
    val latestDistanceM: Double?,
    val inputsUsed: List<FixData>
)

