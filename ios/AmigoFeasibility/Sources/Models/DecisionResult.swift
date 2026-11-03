import Foundation

/// Result of evaluating a sliding window of fixes in DecisionEngine.
/// Pure Swift struct matching Android DecisionResult.kt.
struct DecisionResult: Codable, Equatable {
    let reasonCode: ReasonCode
    let isConfirmed: Bool
    let reasonDetails: String
    let windowCount: Int
    let validCount: Int
    let distanceTrend: String
    let netDisplacementM: Double
    let latestDistanceM: Double?
    let inputsUsed: [FixData]
}
