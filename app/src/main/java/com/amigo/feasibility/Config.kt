package com.amigo.feasibility

import android.content.Context
import android.content.SharedPreferences

/**
 * Tunable test parameters for AMIGO Android Feasibility Test harness.
 * All thresholds are labeled as placeholders per specification section 6.
 * Tunable test parameters, NOT final AMIGO requirements.
 *
 * Target coordinates are persisted in SharedPreferences as Strings to retain full Double precision.
 */
object Config {

    private const val PREFS_NAME = "amigo_config"
    private var prefs: SharedPreferences? = null

    // Default coordinates (near tester's active location from logs: 31.4758, 74.4027)
    private const val DEFAULT_LAT = 31.475800
    private const val DEFAULT_LNG = 74.402700

    fun init(context: Context) {
        prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        val savedLatStr = prefs!!.getString("target_lat_str", null)
        val savedLngStr = prefs!!.getString("target_lng_str", null)

        targetLatitude = savedLatStr?.toDoubleOrNull() ?: DEFAULT_LAT
        targetLongitude = savedLngStr?.toDoubleOrNull() ?: DEFAULT_LNG

        val armName = prefs!!.getString("active_arm", GeofenceArm.ARM_50M.name) ?: GeofenceArm.ARM_50M.name
        activeArm = try { GeofenceArm.valueOf(armName) } catch (_: Exception) { GeofenceArm.ARM_50M }
        isMonitoringArmed = prefs!!.getBoolean("monitoring_armed", false)
    }

    // -- Target Location (persisted with full double precision) --
    const val TARGET_NAME = "Test Target Location"
    var targetLatitude: Double = DEFAULT_LAT
        set(value) {
            field = value
            prefs?.edit()?.putString("target_lat_str", value.toString())?.apply()
        }

    var targetLongitude: Double = DEFAULT_LNG
        set(value) {
            field = value
            prefs?.edit()?.putString("target_lng_str", value.toString())?.apply()
        }

    val isTargetSet: Boolean
        get() = targetLatitude != 0.0 || targetLongitude != 0.0

    // -- Geofence Arms (Section 2 & 8) --
    enum class GeofenceArm(val radiusMeters: Float, val label: String) {
        ARM_50M(50.0f, "50m Arm"),
        ARM_150M(150.0f, "150m Arm")
    }

    var activeArm: GeofenceArm = GeofenceArm.ARM_50M
        set(value) {
            field = value
            prefs?.edit()?.putString("active_arm", value.name)?.apply()
        }

    const val GEOFENCE_DWELL_DELAY_MS: Int = 10_000 // 10s dwell delay

    // -- Monitoring state (persisted for recovery) --
    var isMonitoringArmed: Boolean = false
        set(value) {
            field = value
            prefs?.edit()?.putBoolean("monitoring_armed", value)?.apply()
        }

    // -- Burst Service Parameters (Section 4) --
    const val BURST_DURATION_MS: Long = 60_000L // 60s bounded burst window gives enough time for approach walk
    const val LOCATION_INTERVAL_MS: Long = 1_000L
    const val LOCATION_MIN_INTERVAL_MS: Long = 500L

    // -- Decision Rule Thresholds (Section 6 - Placeholders) --
    // Tuned to 35m based on Tecno KJ5 field logs showing 14-35m GPS horizontal accuracy
    const val MAX_FIX_AGE_MS: Long = 10_000L
    const val MAX_ACCURACY_M: Float = 35.0f
    const val WINDOW_N: Int = 5
    const val MIN_VALID_FIXES: Int = 3
    const val PROXIMITY_M: Double = 40.0
    const val STATIONARY_M: Double = 5.0
    const val MIN_DECREASING_STEPS: Int = 2

    // -- Arming & Cooldown --
    const val COOLDOWN_MS: Long = 60_000L

    // -- Operator Run Label & Scenario --
    var currentRunLabel: String = "RUN-001"
    var currentScenario: String = "Positive"
    var movementMode: String = "Walking"
    var batterySettingLabel: String = "Default"
}
