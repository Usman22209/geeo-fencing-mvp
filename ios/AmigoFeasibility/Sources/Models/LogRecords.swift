import Foundation

/// Common base protocol for JSONL log records matching specification Section 7.
protocol LogRecord {
    var runId: String { get }
    var recordType: String { get }
    var tsWallMs: Int64 { get }
    var tsElapsedMs: Int64 { get }
    var appState: String { get } // "foreground", "background", "unknown"
    var seq: Int64 { get }

    func toJsonObject() -> [String: Any]
    func toJsonString() -> String
}

extension LogRecord {
    func toJsonString() -> String {
        let dict = toJsonObject()
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }

    func createBaseJson() -> [String: Any] {
        return [
            "run_id": runId,
            "record_type": recordType,
            "ts_wall_ms": tsWallMs,
            "ts_elapsed_ms": tsElapsedMs,
            "app_state": appState,
            "seq": seq
        ]
    }
}

// 1. RunHeaderRecord
struct RunHeaderRecord: LogRecord {
    let runId: String
    let recordType: String = "run_header"
    let tsWallMs: Int64
    let tsElapsedMs: Int64
    let appState: String
    let seq: Int64

    let deviceModel: String
    let manufacturer: String
    let osVersion: String
    let appBuild: String
    let configParams: [String: Any]
    let permissionStates: [String: Bool]
    let batteryLevel: Int
    let isBatterySaverOn: Bool
    let networkState: String
    let scenario: String
    let arm: String
    let movementMode: String

    func toJsonObject() -> [String: Any] {
        var json = createBaseJson()
        json["device_model"] = deviceModel
        json["manufacturer"] = manufacturer
        json["os_version"] = osVersion
        json["app_build"] = appBuild
        json["config_params"] = configParams
        json["permission_states"] = permissionStates
        json["battery_level"] = batteryLevel
        json["battery_saver_on"] = isBatterySaverOn
        json["network_state"] = networkState
        json["scenario"] = scenario
        json["arm"] = arm
        json["movement_mode"] = movementMode
        return json
    }
}

// 2. WakeRecord
struct WakeRecord: LogRecord {
    let runId: String
    let recordType: String = "wake"
    let tsWallMs: Int64
    let tsElapsedMs: Int64
    let appState: String
    let seq: Int64

    let trigger: String // "geofence_enter", "geofence_exit", "app_start", "manual"
    let geofenceRequestId: String
    let isColdStart: Bool
    let delaySinceStartMs: Int64

    func toJsonObject() -> [String: Any] {
        var json = createBaseJson()
        json["trigger"] = trigger
        json["geofence_request_id"] = geofenceRequestId
        json["is_cold_start"] = isColdStart
        json["delay_since_start_ms"] = delaySinceStartMs
        return json
    }
}

// 3. FixRecord
struct FixRecord: LogRecord {
    let runId: String
    let recordType: String = "fix"
    let tsWallMs: Int64
    let tsElapsedMs: Int64
    let appState: String
    let seq: Int64

    let lat: Double
    let lng: Double
    let horizontalAccuracyM: Float
    let fixTimestampMs: Int64
    let fixAgeAtReceiptMs: Int64
    let provider: String
    let distanceToTargetM: Double

    func toJsonObject() -> [String: Any] {
        var json = createBaseJson()
        json["lat"] = lat
        json["lng"] = lng
        json["horizontal_accuracy_m"] = horizontalAccuracyM
        json["fix_timestamp_ms"] = fixTimestampMs
        json["fix_age_at_receipt_ms"] = fixAgeAtReceiptMs
        json["provider"] = provider
        json["distance_to_target_m"] = distanceToTargetM
        return json
    }
}

// 4. DecisionRecord
struct DecisionRecord: LogRecord {
    let runId: String
    let recordType: String = "decision"
    let tsWallMs: Int64
    let tsElapsedMs: Int64
    let appState: String
    let seq: Int64

    let reasonCode: String
    let reasonDetails: String
    let windowCount: Int
    let validCount: Int
    let distanceTrend: String
    let netDisplacementM: Double
    let latestDistanceM: Double?
    let inputsCount: Int

    func toJsonObject() -> [String: Any] {
        var json = createBaseJson()
        json["reason_code"] = reasonCode
        json["reason_details"] = reasonDetails
        var windowSummary: [String: Any] = [
            "window_count": windowCount,
            "valid_count": validCount,
            "distance_trend": distanceTrend,
            "net_displacement_m": netDisplacementM
        ]
        if let latest = latestDistanceM {
            windowSummary["latest_distance_m"] = latest
        }
        json["window_summary"] = windowSummary
        json["inputs_count"] = inputsCount
        return json
    }
}

// 5. EventRecord
struct EventRecord: LogRecord {
    let runId: String
    let recordType: String = "event"
    let tsWallMs: Int64
    let tsElapsedMs: Int64
    let appState: String
    let seq: Int64

    let eventId: String
    let eventTimeMs: Int64
    let distanceM: Double
    let evidenceSummary: String

    func toJsonObject() -> [String: Any] {
        var json = createBaseJson()
        json["event_id"] = eventId
        json["event_time_ms"] = eventTimeMs
        json["distance_m"] = distanceM
        json["evidence_summary"] = evidenceSummary
        return json
    }
}

// 6. NotificationRecord
struct NotificationRecord: LogRecord {
    let runId: String
    let recordType: String = "notification"
    let tsWallMs: Int64
    let tsElapsedMs: Int64
    let appState: String
    let seq: Int64

    let eventIdRef: String
    let attemptTimeMs: Int64
    let outcome: String // "posted", "blocked_by_permission", "exception"
    let errorText: String?

    func toJsonObject() -> [String: Any] {
        var json = createBaseJson()
        json["event_id_ref"] = eventIdRef
        json["attempt_time_ms"] = attemptTimeMs
        json["outcome"] = outcome
        if let err = errorText {
            json["error_text"] = err
        }
        return json
    }
}

// 7. RecoveryRecord
struct RecoveryRecord: LogRecord {
    let runId: String
    let recordType: String = "recovery"
    let tsWallMs: Int64
    let tsElapsedMs: Int64
    let appState: String
    let seq: Int64

    let situation: String // "reboot", "permission_restored", "app_restart"
    let reArmedComponent: String
    let result: String
    let details: String

    func toJsonObject() -> [String: Any] {
        var json = createBaseJson()
        json["situation"] = situation
        json["re_armed_component"] = reArmedComponent
        json["result"] = result
        json["details"] = details
        return json
    }
}

// 8. PermissionChangeRecord
struct PermissionChangeRecord: LogRecord {
    let runId: String
    let recordType: String = "permission_change"
    let tsWallMs: Int64
    let tsElapsedMs: Int64
    let appState: String
    let seq: Int64

    let permission: String
    let oldState: Bool
    let newState: Bool

    func toJsonObject() -> [String: Any] {
        var json = createBaseJson()
        json["permission"] = permission
        json["old_state"] = oldState
        json["new_state"] = newState
        return json
    }
}

// 9. BatteryRecord
struct BatteryRecord: LogRecord {
    let runId: String
    let recordType: String = "battery"
    let tsWallMs: Int64
    let tsElapsedMs: Int64
    let appState: String
    let seq: Int64

    let level: Int
    let isCharging: Bool
    let runDurationMs: Int64
    let note: String?

    func toJsonObject() -> [String: Any] {
        var json = createBaseJson()
        json["battery_level"] = level
        json["is_charging"] = isCharging
        json["run_duration_ms"] = runDurationMs
        if let n = note {
            json["note"] = n
        }
        return json
    }
}

// 10. NoteRecord
struct NoteRecord: LogRecord {
    let runId: String
    let recordType: String = "note"
    let tsWallMs: Int64
    let tsElapsedMs: Int64
    let appState: String
    let seq: Int64

    let noteText: String

    func toJsonObject() -> [String: Any] {
        var json = createBaseJson()
        json["note"] = noteText
        return json
    }
}
