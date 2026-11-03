import Foundation

/// Tunable test parameters for AMIGO iOS Feasibility Test harness.
/// All thresholds are labeled as placeholders per specification section 6.
/// Tunable test parameters, NOT final AMIGO requirements.
///
/// Target coordinates are persisted in UserDefaults as Strings to retain full Double precision.
final class Config {
    static let shared = Config()

    private let defaults = UserDefaults.standard

    // Keys for persistence
    private let keyTargetLat = "amigo_target_lat_str"
    private let keyTargetLng = "amigo_target_lng_str"
    private let keyActiveArm = "amigo_active_arm"
    private let keyMonitoringArmed = "amigo_monitoring_armed"

    // Default coordinates (near tester's active location: 31.4758, 74.4027)
    static let defaultLat: Double = 31.475800
    static let defaultLng: Double = 74.402700

    static let targetName = "Test Target Location"

    enum GeofenceArm: String, CaseIterable, Identifiable {
        case arm50M = "ARM_50M"
        case arm150M = "ARM_150M"

        var id: String { rawValue }

        var radiusMeters: Double {
            switch self {
            case .arm50M: return 50.0
            case .arm150M: return 150.0
            }
        }

        var label: String {
            switch self {
            case .arm50M: return "50m Arm"
            case .arm150M: return "150m Arm"
            }
        }
    }

    var targetLatitude: Double {
        get {
            if let str = defaults.string(forKey: keyTargetLat), let val = Double(str) {
                return val
            }
            return Config.defaultLat
        }
        set {
            defaults.set(String(newValue), forKey: keyTargetLat)
        }
    }

    var targetLongitude: Double {
        get {
            if let str = defaults.string(forKey: keyTargetLng), let val = Double(str) {
                return val
            }
            return Config.defaultLng
        }
        set {
            defaults.set(String(newValue), forKey: keyTargetLng)
        }
    }

    var isTargetSet: Bool {
        return targetLatitude != 0.0 || targetLongitude != 0.0
    }

    var activeArm: GeofenceArm {
        get {
            if let raw = defaults.string(forKey: keyActiveArm), let arm = GeofenceArm(rawValue: raw) {
                return arm
            }
            return .arm50M
        }
        set {
            defaults.set(newValue.rawValue, forKey: keyActiveArm)
        }
    }

    var isMonitoringArmed: Bool {
        get {
            return defaults.bool(forKey: keyMonitoringArmed)
        }
        set {
            defaults.set(newValue, forKey: keyMonitoringArmed)
        }
    }

    // Geofence & Burst Parameters
    static let geofenceDwellDelayMs: Int64 = 10_000
    static let burstDurationMs: Int64 = 60_000 // 60s bounded burst window matching Android
    static let locationIntervalMs: Int64 = 1_000
    static let locationMinIntervalMs: Int64 = 500

    // Decision Rule Thresholds (Tuned to 35m based on field data)
    static let maxFixAgeMs: Int64 = 10_000
    static let maxAccuracyM: Float = 35.0
    static let windowN: Int = 5
    static let minValidFixes: Int = 3
    static let proximityM: Double = 40.0
    static let stationaryM: Double = 5.0
    static let minDecreasingSteps: Int = 2
    static let noiseRatio: Double = 0.5

    // Arming & Cooldown
    static let cooldownMs: Int64 = 60_000

    // Operator Run Label & Scenario
    var currentRunLabel: String = "RUN-001"
    var currentScenario: String = "Positive Approach"
    var movementMode: String = "Walking"
    var batterySettingLabel: String = "Default"

    private init() {}
}
