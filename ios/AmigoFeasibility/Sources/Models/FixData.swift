import Foundation

/// Pure Swift representation of a location fix.
/// Free of platform framework dependencies so DecisionEngine can be unit-tested in isolation.
struct FixData: Codable, Equatable {
    let lat: Double
    let lng: Double
    let accuracyM: Float
    let timestampMs: Int64
    let receiptWallMs: Int64
    let ageMs: Int64
    let provider: String
    let distanceToTargetM: Double

    func isValid(maxAgeMs: Int64, maxAccuracyM: Float) -> Bool {
        return ageMs <= maxAgeMs && accuracyM <= maxAccuracyM
    }
}
