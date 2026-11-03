import Foundation

/// Standard reason codes for DecisionEngine per specification section 6.
/// Pure Swift enum — zero UIKit/CoreLocation imports.
enum ReasonCode: String, Codable, CaseIterable {
    case eventConfirmed = "EVENT_CONFIRMED"
    case insufficientFixes = "INSUFFICIENT_FIXES"
    case staleFixes = "STALE_FIXES"
    case lowAccuracy = "LOW_ACCURACY"
    case outsideProximity = "OUTSIDE_PROXIMITY"
    case stationary = "STATIONARY"
    case notApproaching = "NOT_APPROACHING"
    case conflicting = "CONFLICTING"
}
