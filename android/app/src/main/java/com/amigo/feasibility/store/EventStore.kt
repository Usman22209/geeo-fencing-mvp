package com.amigo.feasibility.store

import com.amigo.feasibility.Config
import com.amigo.feasibility.logger.Logger
import com.amigo.feasibility.model.DecisionResult
import com.amigo.feasibility.model.ReasonCode
import java.util.UUID

/**
 * Thread-safe Event Store per specification section 4.
 * Writes an event record (with UUID) ONLY when the decision is positive.
 * Strictly enforces one event per arming, with cooldown.
 * NEVER creates an event on recovery.
 */
object EventStore {

    @Volatile
    private var hasFiredForCurrentArming: Boolean = false

    @Volatile
    private var lastEventTimeMs: Long = 0L

    /**
     * Resets arming state for a fresh test cycle.
     */
    @Synchronized
    fun onArmed() {
        hasFiredForCurrentArming = false
    }

    /**
     * Called when device physically exits the geofence boundary.
     * Re-arms the store so that the next entrance can trigger a fresh burst and notification.
     */
    @Synchronized
    fun onExited() {
        hasFiredForCurrentArming = false
        lastEventTimeMs = 0L
    }

    /**
     * Disarms the store.
     */
    @Synchronized
    fun onDisarmed() {
        hasFiredForCurrentArming = true
    }

    /**
     * Evaluates whether to persist an event based on DecisionResult.
     * Enforces:
     * 1. Must be EVENT_CONFIRMED
     * 2. Exactly one event per arming
     * 3. Must respect cooldown period
     *
     * Returns eventId if created, null otherwise.
     */
    @Synchronized
    fun recordEventIfConfirmed(result: DecisionResult): String? {
        if (!result.isConfirmed || result.reasonCode != ReasonCode.EVENT_CONFIRMED) {
            return null
        }

        if (hasFiredForCurrentArming) {
            Logger.logNote("Event suppressed: event already fired for this arming.")
            return null
        }

        val now = System.currentTimeMillis()
        val timeSinceLast = now - lastEventTimeMs
        if (lastEventTimeMs > 0 && timeSinceLast < Config.COOLDOWN_MS) {
            Logger.logNote("Event suppressed: cooldown active ($timeSinceLast ms < ${Config.COOLDOWN_MS} ms).")
            return null
        }

        val eventId = UUID.randomUUID().toString()
        hasFiredForCurrentArming = true
        lastEventTimeMs = now

        val distance = result.latestDistanceM ?: 0.0
        val evidenceSummary = result.reasonDetails

        Logger.logEvent(
            eventId = eventId,
            eventTimeMs = now,
            distanceM = distance,
            evidenceSummary = evidenceSummary
        )

        return eventId
    }

    fun isArmed(): Boolean = !hasFiredForCurrentArming
}

