package com.amigo.feasibility.model

/**
 * Standard reason codes for DecisionEngine per specification section 6.
 * Pure Kotlin enum.
 */
enum class ReasonCode {
    EVENT_CONFIRMED,
    INSUFFICIENT_FIXES,
    STALE_FIXES,
    LOW_ACCURACY,
    OUTSIDE_PROXIMITY,
    STATIONARY,
    NOT_APPROACHING,
    CONFLICTING
}

