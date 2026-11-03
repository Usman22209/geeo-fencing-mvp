import XCTest
@testable import AmigoFeasibility

/// Pure Swift unit tests for DecisionEngine covering all reason codes per specification section 8.
final class DecisionEngineTests: XCTestCase {

    private let targetLat = 51.507400
    private let targetLng = -0.127800

    private var engine: DecisionEngine!
    private let defaultParams = DecisionEngine.Params(
        maxFixAgeMs: 10_000,
        maxAccuracyM: 35.0, // Raised from 25 based on field data (14-35m accuracy)
        windowN: 5,
        minValidFixes: 3,
        proximityM: 40.0,
        stationaryM: 5.0,
        minDecreasingSteps: 2,
        noiseRatio: 0.5
    )

    override func setUp() {
        super.setUp()
        engine = DecisionEngine(params: defaultParams)
    }

    // Helper: 1 deg latitude is approx 111,320m.
    private func createFix(
        distanceM: Double,
        ageMs: Int64 = 1000,
        accuracyM: Float = 5.0,
        latOffsetM: Double = 0.0
    ) -> FixData {
        let latDelta = distanceM / 111320.0
        let fixLat = targetLat + latDelta
        let now = Int64(Date().timeIntervalSince1970 * 1000.0)
        return FixData(
            lat: fixLat,
            lng: targetLng + (latOffsetM / 111320.0),
            accuracyM: accuracyM,
            timestampMs: now - ageMs,
            receiptWallMs: now,
            ageMs: ageMs,
            provider: "gps",
            distanceToTargetM: distanceM
        )
    }

    func testEventConfirmed_ApproachingInProximity() {
        // 5 fresh, accurate fixes approaching target: 35m -> 30m -> 25m -> 20m -> 15m
        let fixes = [
            createFix(distanceM: 35.0, ageMs: 1000, accuracyM: 4.0),
            createFix(distanceM: 30.0, ageMs: 1000, accuracyM: 4.0),
            createFix(distanceM: 25.0, ageMs: 1000, accuracyM: 4.0),
            createFix(distanceM: 20.0, ageMs: 1000, accuracyM: 4.0),
            createFix(distanceM: 15.0, ageMs: 1000, accuracyM: 4.0)
        ]

        let result = engine.evaluate(fixes: fixes, targetLat: targetLat, targetLng: targetLng)

        XCTAssertTrue(result.isConfirmed, "Expected EVENT_CONFIRMED to be true")
        XCTAssertEqual(result.reasonCode, .eventConfirmed)
        XCTAssertEqual(result.validCount, 5)
        XCTAssertGreaterThanOrEqual(result.netDisplacementM, 5.0)
    }

    func testInsufficientFixes_TooFewFixesInWindow() {
        // Only 2 fixes provided, minValidFixes is 3
        let fixes = [
            createFix(distanceM: 30.0),
            createFix(distanceM: 25.0)
        ]

        let result = engine.evaluate(fixes: fixes, targetLat: targetLat, targetLng: targetLng)

        XCTAssertFalse(result.isConfirmed)
        XCTAssertEqual(result.reasonCode, .insufficientFixes)
    }

    func testStaleFixes_DominatedByFixAge() {
        // 5 fixes, but 4 are older than maxFixAgeMs (10s)
        let fixes = [
            createFix(distanceM: 35.0, ageMs: 25_000),
            createFix(distanceM: 30.0, ageMs: 20_000),
            createFix(distanceM: 25.0, ageMs: 18_000),
            createFix(distanceM: 20.0, ageMs: 15_000),
            createFix(distanceM: 15.0, ageMs: 1000) // only 1 valid fix
        ]

        let result = engine.evaluate(fixes: fixes, targetLat: targetLat, targetLng: targetLng)

        XCTAssertFalse(result.isConfirmed)
        XCTAssertEqual(result.reasonCode, .staleFixes)
    }

    func testLowAccuracy_DominatedByHighUncertainty() {
        // 5 fixes, fresh, but 4 have accuracy > maxAccuracyM (35m)
        let fixes = [
            createFix(distanceM: 35.0, ageMs: 1000, accuracyM: 55.0),
            createFix(distanceM: 30.0, ageMs: 1000, accuracyM: 50.0),
            createFix(distanceM: 25.0, ageMs: 1000, accuracyM: 45.0),
            createFix(distanceM: 20.0, ageMs: 1000, accuracyM: 40.0),
            createFix(distanceM: 15.0, ageMs: 1000, accuracyM: 5.0) // only 1 valid fix
        ]

        let result = engine.evaluate(fixes: fixes, targetLat: targetLat, targetLng: targetLng)

        XCTAssertFalse(result.isConfirmed)
        XCTAssertEqual(result.reasonCode, .lowAccuracy)
    }

    func testOutsideProximity_ApproachingButOutsideProximityRadius() {
        // 5 fresh, accurate fixes approaching, but outside proximity threshold (40m)
        let fixes = [
            createFix(distanceM: 90.0),
            createFix(distanceM: 80.0),
            createFix(distanceM: 70.0),
            createFix(distanceM: 60.0),
            createFix(distanceM: 50.0) // 50m > 40m proximity threshold
        ]

        let result = engine.evaluate(fixes: fixes, targetLat: targetLat, targetLng: targetLng)

        XCTAssertFalse(result.isConfirmed)
        XCTAssertEqual(result.reasonCode, .outsideProximity)
    }

    func testStationary_InsideProximityButNotMoving() {
        // 5 fresh, accurate fixes all at 25m with virtually 0 net displacement
        let fixes = [
            createFix(distanceM: 25.0, latOffsetM: 0.0),
            createFix(distanceM: 25.0, latOffsetM: 0.2),
            createFix(distanceM: 25.0, latOffsetM: 0.4),
            createFix(distanceM: 25.0, latOffsetM: 0.6),
            createFix(distanceM: 25.0, latOffsetM: 0.8) // net displacement < 5m
        ]

        let result = engine.evaluate(fixes: fixes, targetLat: targetLat, targetLng: targetLng)

        XCTAssertFalse(result.isConfirmed)
        XCTAssertEqual(result.reasonCode, .stationary)
    }

    func testNotApproaching_MovingAwayFromTarget() {
        // 5 fresh, accurate fixes in proximity but increasing distance (moving away)
        let fixes = [
            createFix(distanceM: 15.0),
            createFix(distanceM: 20.0),
            createFix(distanceM: 25.0),
            createFix(distanceM: 30.0),
            createFix(distanceM: 35.0)
        ]

        let result = engine.evaluate(fixes: fixes, targetLat: targetLat, targetLng: targetLng)

        XCTAssertFalse(result.isConfirmed)
        XCTAssertEqual(result.reasonCode, .notApproaching)
    }

    func testConflicting_DistanceChangeSmallerThanAccuracyNoise() {
        // Displaced by 8 meters laterally (> 5m stationary threshold),
        // but approach magnitude toward target is only 1.0m (30.0m -> 29.0m)
        // with high GPS uncertainty (accuracy = 20.0m).
        // Approach magnitude 1.0m < avgAccuracy * 0.5 (10.0m) -> CONFLICTING (noise dominated)
        let fixes = [
            createFix(distanceM: 30.0, accuracyM: 20.0, latOffsetM: 0.0),
            createFix(distanceM: 29.8, accuracyM: 20.0, latOffsetM: 2.0),
            createFix(distanceM: 29.5, accuracyM: 20.0, latOffsetM: 4.0),
            createFix(distanceM: 29.2, accuracyM: 20.0, latOffsetM: 6.0),
            createFix(distanceM: 29.0, accuracyM: 20.0, latOffsetM: 8.0)
        ]

        let result = engine.evaluate(fixes: fixes, targetLat: targetLat, targetLng: targetLng)

        XCTAssertFalse(result.isConfirmed)
        XCTAssertEqual(result.reasonCode, .conflicting)
    }
}
