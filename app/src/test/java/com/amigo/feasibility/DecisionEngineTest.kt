package com.amigo.feasibility

import com.amigo.feasibility.engine.DecisionEngine
import com.amigo.feasibility.model.FixData
import com.amigo.feasibility.model.ReasonCode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Pure Kotlin unit tests for DecisionEngine covering all reason codes per specification section 8.
 */
class DecisionEngineTest {

    private val targetLat = 51.507400
    private val targetLng = -0.127800

    private lateinit var engine: DecisionEngine
    private val defaultParams = DecisionEngine.Params(
        maxFixAgeMs = 10_000L,
        maxAccuracyM = 35.0f, // Raised from 25 based on Tecno KJ5 field data (14-35m accuracy)
        windowN = 5,
        minValidFixes = 3,
        proximityM = 40.0,
        stationaryM = 5.0,
        minDecreasingSteps = 2,
        noiseRatio = 0.5
    )

    @Before
    fun setup() {
        engine = DecisionEngine(defaultParams)
    }

    // Helper: 1 deg latitude is approx 111,320m.
    private fun createFix(
        distanceM: Double,
        ageMs: Long = 1000L,
        accuracyM: Float = 5.0f,
        latOffsetM: Double = 0.0
    ): FixData {
        // Place fix north of target by distanceM
        val latDelta = distanceM / 111320.0
        val fixLat = targetLat + latDelta
        val now = System.currentTimeMillis()
        return FixData(
            lat = fixLat,
            lng = targetLng + (latOffsetM / 111320.0),
            accuracyM = accuracyM,
            timestampMs = now - ageMs,
            receiptWallMs = now,
            ageMs = ageMs,
            provider = "gps",
            distanceToTargetM = distanceM
        )
    }

    @Test
    fun testEventConfirmed_ApproachingInProximity() {
        // 5 fresh, accurate fixes approaching target: 35m -> 30m -> 25m -> 20m -> 15m
        val fixes = listOf(
            createFix(distanceM = 35.0, ageMs = 1000L, accuracyM = 4.0f),
            createFix(distanceM = 30.0, ageMs = 1000L, accuracyM = 4.0f),
            createFix(distanceM = 25.0, ageMs = 1000L, accuracyM = 4.0f),
            createFix(distanceM = 20.0, ageMs = 1000L, accuracyM = 4.0f),
            createFix(distanceM = 15.0, ageMs = 1000L, accuracyM = 4.0f)
        )

        val result = engine.evaluate(fixes, targetLat, targetLng)

        assertTrue("Expected EVENT_CONFIRMED to be true", result.isConfirmed)
        assertEquals(ReasonCode.EVENT_CONFIRMED, result.reasonCode)
        assertEquals(5, result.validCount)
        assertTrue(result.netDisplacementM >= 5.0)
    }

    @Test
    fun testInsufficientFixes_TooFewFixesInWindow() {
        // Only 2 fixes provided, minValidFixes is 3
        val fixes = listOf(
            createFix(distanceM = 30.0),
            createFix(distanceM = 25.0)
        )

        val result = engine.evaluate(fixes, targetLat, targetLng)

        assertFalse(result.isConfirmed)
        assertEquals(ReasonCode.INSUFFICIENT_FIXES, result.reasonCode)
    }

    @Test
    fun testStaleFixes_DominatedByFixAge() {
        // 5 fixes, but 4 are older than maxFixAgeMs (10s)
        val fixes = listOf(
            createFix(distanceM = 35.0, ageMs = 25_000L),
            createFix(distanceM = 30.0, ageMs = 20_000L),
            createFix(distanceM = 25.0, ageMs = 18_000L),
            createFix(distanceM = 20.0, ageMs = 15_000L),
            createFix(distanceM = 15.0, ageMs = 1000L) // only 1 valid fix
        )

        val result = engine.evaluate(fixes, targetLat, targetLng)

        assertFalse(result.isConfirmed)
        assertEquals(ReasonCode.STALE_FIXES, result.reasonCode)
    }

    @Test
    fun testLowAccuracy_DominatedByHighUncertainty() {
        // 5 fixes, fresh, but 4 have accuracy > maxAccuracyM (35m)
        val fixes = listOf(
            createFix(distanceM = 35.0, ageMs = 1000L, accuracyM = 55.0f),
            createFix(distanceM = 30.0, ageMs = 1000L, accuracyM = 50.0f),
            createFix(distanceM = 25.0, ageMs = 1000L, accuracyM = 45.0f),
            createFix(distanceM = 20.0, ageMs = 1000L, accuracyM = 40.0f),
            createFix(distanceM = 15.0, ageMs = 1000L, accuracyM = 5.0f) // only 1 valid fix
        )

        val result = engine.evaluate(fixes, targetLat, targetLng)

        assertFalse(result.isConfirmed)
        assertEquals(ReasonCode.LOW_ACCURACY, result.reasonCode)
    }

    @Test
    fun testOutsideProximity_ApproachingButOutsideProximityRadius() {
        // 5 fresh, accurate fixes approaching, but outside proximity threshold (40m)
        val fixes = listOf(
            createFix(distanceM = 90.0),
            createFix(distanceM = 80.0),
            createFix(distanceM = 70.0),
            createFix(distanceM = 60.0),
            createFix(distanceM = 50.0) // 50m > 40m proximity threshold
        )

        val result = engine.evaluate(fixes, targetLat, targetLng)

        assertFalse(result.isConfirmed)
        assertEquals(ReasonCode.OUTSIDE_PROXIMITY, result.reasonCode)
    }

    @Test
    fun testStationary_InsideProximityButNotMoving() {
        // 5 fresh, accurate fixes all at 25m with virtually 0 net displacement
        val fixes = listOf(
            createFix(distanceM = 25.0, latOffsetM = 0.0),
            createFix(distanceM = 25.0, latOffsetM = 0.2),
            createFix(distanceM = 25.0, latOffsetM = 0.4),
            createFix(distanceM = 25.0, latOffsetM = 0.6),
            createFix(distanceM = 25.0, latOffsetM = 0.8) // net displacement < 5m
        )

        val result = engine.evaluate(fixes, targetLat, targetLng)

        assertFalse(result.isConfirmed)
        assertEquals(ReasonCode.STATIONARY, result.reasonCode)
    }

    @Test
    fun testNotApproaching_MovingAwayFromTarget() {
        // 5 fresh, accurate fixes in proximity but increasing distance (moving away)
        val fixes = listOf(
            createFix(distanceM = 15.0),
            createFix(distanceM = 20.0),
            createFix(distanceM = 25.0),
            createFix(distanceM = 30.0),
            createFix(distanceM = 35.0)
        )

        val result = engine.evaluate(fixes, targetLat, targetLng)

        assertFalse(result.isConfirmed)
        assertEquals(ReasonCode.NOT_APPROACHING, result.reasonCode)
    }

    @Test
    fun testConflicting_DistanceChangeSmallerThanAccuracyNoise() {
        // Displaced by 8 meters laterally (> 5m stationary threshold),
        // but approach magnitude toward target is only 1.0m (30.0m -> 29.0m)
        // with high GPS uncertainty (accuracy = 20.0m).
        // Approach magnitude 1.0m < avgAccuracy * 0.5 (10.0m) -> CONFLICTING (noise dominated)
        val fixes = listOf(
            createFix(distanceM = 30.0, accuracyM = 20.0f, latOffsetM = 0.0),
            createFix(distanceM = 29.8, accuracyM = 20.0f, latOffsetM = 2.0),
            createFix(distanceM = 29.5, accuracyM = 20.0f, latOffsetM = 4.0),
            createFix(distanceM = 29.2, accuracyM = 20.0f, latOffsetM = 6.0),
            createFix(distanceM = 29.0, accuracyM = 20.0f, latOffsetM = 8.0)
        )

        val result = engine.evaluate(fixes, targetLat, targetLng)

        assertFalse(result.isConfirmed)
        assertEquals(ReasonCode.CONFLICTING, result.reasonCode)
    }
}

