package com.amigo.feasibility.model

import org.json.JSONArray
import org.json.JSONObject

/**
 * Common base representation for JSONL log records matching specification Section 7.
 */
sealed class LogRecord(
    val runId: String,
    val recordType: String,
    val tsWallMs: Long,
    val tsElapsedMs: Long,
    val appState: String, // "foreground", "background", "unknown"
    val seq: Long
) {
    abstract fun toJsonObject(): JSONObject

    fun toJsonString(): String = toJsonObject().toString()

    protected fun createBaseJson(): JSONObject {
        val json = JSONObject()
        json.put("run_id", runId)
        json.put("record_type", recordType)
        json.put("ts_wall_ms", tsWallMs)
        json.put("ts_elapsed_ms", tsElapsedMs)
        json.put("app_state", appState)
        json.put("seq", seq)
        return json
    }
}

class RunHeaderRecord(
    runId: String,
    tsWallMs: Long,
    tsElapsedMs: Long,
    appState: String,
    seq: Long,
    val deviceModel: String,
    val manufacturer: String,
    val androidVersion: String,
    val sdkInt: Int,
    val appBuild: String,
    val configParams: Map<String, Any>,
    val permissionStates: Map<String, Boolean>,
    val batteryLevel: Int,
    val isBatterySaverOn: Boolean,
    val networkState: String,
    val batteryOptimizationSetting: String,
    val scenario: String,
    val arm: String,
    val movementMode: String
) : LogRecord(runId, "run_header", tsWallMs, tsElapsedMs, appState, seq) {
    override fun toJsonObject(): JSONObject {
        val json = createBaseJson()
        json.put("device_model", deviceModel)
        json.put("manufacturer", manufacturer)
        json.put("android_version", androidVersion)
        json.put("sdk_int", sdkInt)
        json.put("app_build", appBuild)
        json.put("config_params", JSONObject(configParams))
        json.put("permission_states", JSONObject(permissionStates))
        json.put("battery_level", batteryLevel)
        json.put("battery_saver_on", isBatterySaverOn)
        json.put("network_state", networkState)
        json.put("battery_optimization_setting", batteryOptimizationSetting)
        json.put("scenario", scenario)
        json.put("arm", arm)
        json.put("movement_mode", movementMode)
        return json
    }
}

class WakeRecord(
    runId: String,
    tsWallMs: Long,
    tsElapsedMs: Long,
    appState: String,
    seq: Long,
    val trigger: String, // "geofence_enter", "geofence_dwell", "boot", "app_start", "manual"
    val geofenceRequestId: String,
    val isColdStart: Boolean,
    val delaySinceStartMs: Long
) : LogRecord(runId, "wake", tsWallMs, tsElapsedMs, appState, seq) {
    override fun toJsonObject(): JSONObject {
        val json = createBaseJson()
        json.put("trigger", trigger)
        json.put("geofence_request_id", geofenceRequestId)
        json.put("is_cold_start", isColdStart)
        json.put("delay_since_start_ms", delaySinceStartMs)
        return json
    }
}

class FixRecord(
    runId: String,
    tsWallMs: Long,
    tsElapsedMs: Long,
    appState: String,
    seq: Long,
    val lat: Double,
    val lng: Double,
    val horizontalAccuracyM: Float,
    val fixTimestampMs: Long,
    val fixAgeAtReceiptMs: Long,
    val provider: String,
    val distanceToTargetM: Double
) : LogRecord(runId, "fix", tsWallMs, tsElapsedMs, appState, seq) {
    override fun toJsonObject(): JSONObject {
        val json = createBaseJson()
        json.put("lat", lat)
        json.put("lng", lng)
        json.put("horizontal_accuracy_m", horizontalAccuracyM)
        json.put("fix_timestamp_ms", fixTimestampMs)
        json.put("fix_age_at_receipt_ms", fixAgeAtReceiptMs)
        json.put("provider", provider)
        json.put("distance_to_target_m", distanceToTargetM)
        return json
    }
}

class DecisionRecord(
    runId: String,
    tsWallMs: Long,
    tsElapsedMs: Long,
    appState: String,
    seq: Long,
    val reasonCode: String,
    val reasonDetails: String,
    val windowCount: Int,
    val validCount: Int,
    val distanceTrend: String,
    val netDisplacementM: Double,
    val latestDistanceM: Double?,
    val inputsCount: Int
) : LogRecord(runId, "decision", tsWallMs, tsElapsedMs, appState, seq) {
    override fun toJsonObject(): JSONObject {
        val json = createBaseJson()
        json.put("reason_code", reasonCode)
        json.put("reason_details", reasonDetails)
        val windowSummary = JSONObject()
        windowSummary.put("window_count", windowCount)
        windowSummary.put("valid_count", validCount)
        windowSummary.put("distance_trend", distanceTrend)
        windowSummary.put("net_displacement_m", netDisplacementM)
        if (latestDistanceM != null) {
            windowSummary.put("latest_distance_m", latestDistanceM)
        }
        json.put("window_summary", windowSummary)
        json.put("inputs_count", inputsCount)
        return json
    }
}

class EventRecord(
    runId: String,
    tsWallMs: Long,
    tsElapsedMs: Long,
    appState: String,
    seq: Long,
    val eventId: String,
    val eventTimeMs: Long,
    val distanceM: Double,
    val evidenceSummary: String
) : LogRecord(runId, "event", tsWallMs, tsElapsedMs, appState, seq) {
    override fun toJsonObject(): JSONObject {
        val json = createBaseJson()
        json.put("event_id", eventId)
        json.put("event_time_ms", eventTimeMs)
        json.put("distance_m", distanceM)
        json.put("evidence_summary", evidenceSummary)
        return json
    }
}

class NotificationRecord(
    runId: String,
    tsWallMs: Long,
    tsElapsedMs: Long,
    appState: String,
    seq: Long,
    val eventIdRef: String,
    val attemptTimeMs: Long,
    val outcome: String, // "posted", "blocked_by_permission", "blocked_by_channel", "exception"
    val errorText: String?
) : LogRecord(runId, "notification", tsWallMs, tsElapsedMs, appState, seq) {
    override fun toJsonObject(): JSONObject {
        val json = createBaseJson()
        json.put("event_id_ref", eventIdRef)
        json.put("attempt_time_ms", attemptTimeMs)
        json.put("outcome", outcome)
        if (errorText != null) {
            json.put("error_text", errorText)
        }
        return json
    }
}

class RecoveryRecord(
    runId: String,
    tsWallMs: Long,
    tsElapsedMs: Long,
    appState: String,
    seq: Long,
    val situation: String, // "reboot", "permission_restored", "app_restart", "network_restored"
    val reArmedComponent: String,
    val result: String,
    val details: String
) : LogRecord(runId, "recovery", tsWallMs, tsElapsedMs, appState, seq) {
    override fun toJsonObject(): JSONObject {
        val json = createBaseJson()
        json.put("situation", situation)
        json.put("re_armed_component", reArmedComponent)
        json.put("result", result)
        json.put("details", details)
        return json
    }
}

class PermissionChangeRecord(
    runId: String,
    tsWallMs: Long,
    tsElapsedMs: Long,
    appState: String,
    seq: Long,
    val permission: String,
    val oldState: Boolean,
    val newState: Boolean
) : LogRecord(runId, "permission_change", tsWallMs, tsElapsedMs, appState, seq) {
    override fun toJsonObject(): JSONObject {
        val json = createBaseJson()
        json.put("permission", permission)
        json.put("old_state", oldState)
        json.put("new_state", newState)
        return json
    }
}

class BatteryRecord(
    runId: String,
    tsWallMs: Long,
    tsElapsedMs: Long,
    appState: String,
    seq: Long,
    val level: Int,
    val isCharging: Boolean,
    val runDurationMs: Long,
    val note: String?
) : LogRecord(runId, "battery", tsWallMs, tsElapsedMs, appState, seq) {
    override fun toJsonObject(): JSONObject {
        val json = createBaseJson()
        json.put("battery_level", level)
        json.put("is_charging", isCharging)
        json.put("run_duration_ms", runDurationMs)
        if (note != null) json.put("note", note)
        return json
    }
}

class NoteRecord(
    runId: String,
    tsWallMs: Long,
    tsElapsedMs: Long,
    appState: String,
    seq: Long,
    val noteText: String
) : LogRecord(runId, "note", tsWallMs, tsElapsedMs, appState, seq) {
    override fun toJsonObject(): JSONObject {
        val json = createBaseJson()
        json.put("note", noteText)
        return json
    }
}

