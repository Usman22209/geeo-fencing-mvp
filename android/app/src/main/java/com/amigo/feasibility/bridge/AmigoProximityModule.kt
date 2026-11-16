package com.amigo.feasibility.bridge

import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.content.ContextCompat
import com.amigo.feasibility.Config
import com.amigo.feasibility.burst.BurstService
import com.amigo.feasibility.engine.DecisionEngine
import com.amigo.feasibility.geofence.GeofenceManager
import com.amigo.feasibility.logger.Logger
import com.amigo.feasibility.permission.PermissionHelper
import com.amigo.feasibility.store.EventStore
import com.facebook.react.bridge.*
import com.facebook.react.modules.core.DeviceEventManagerModule

class AmigoProximityModule(private val reactContext: ReactApplicationContext) :
    ReactContextBaseJavaModule(reactContext) {

    override fun getName(): String = "AmigoProximity"

    init {
        // Wire Logger observer to emit events to React Native JavaScript layer
        Logger.onLogAppended = { rawLine ->
            sendEvent("onLogAppended", Arguments.createMap().apply {
                putString("raw", rawLine)
            })
        }
    }

    private fun sendEvent(eventName: String, params: WritableMap?) {
        if (reactContext.hasActiveReactInstance()) {
            reactContext
                .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
                .emit(eventName, params)
        }
    }

    @ReactMethod
    fun initConfig(promise: Promise) {
        try {
            Config.init(reactContext)
            val map = Arguments.createMap().apply {
                putDouble("targetLat", Config.targetLatitude)
                putDouble("targetLng", Config.targetLongitude)
                putString("activeArm", Config.activeArm.name)
                putBoolean("isArmed", Config.isMonitoringArmed)
            }
            promise.resolve(map)
        } catch (e: Exception) {
            promise.reject("CONFIG_ERROR", e.message, e)
        }
    }

    @ReactMethod
    fun setTarget(lat: Double, lng: Double, promise: Promise) {
        try {
            Config.targetLatitude = lat
            Config.targetLongitude = lng
            Logger.logNote("Target updated from React Native: ($lat, $lng)")
            promise.resolve(true)
        } catch (e: Exception) {
            promise.reject("TARGET_ERROR", e.message, e)
        }
    }

    @ReactMethod
    fun setArmRadius(armName: String, promise: Promise) {
        try {
            Config.activeArm = if (armName == "ARM_150M") {
                Config.GeofenceArm.ARM_150M
            } else {
                Config.GeofenceArm.ARM_50M
            }
            Logger.logNote("Geofence arm updated from React Native: ${Config.activeArm.label}")
            promise.resolve(Config.activeArm.radiusMeters.toDouble())
        } catch (e: Exception) {
            promise.reject("ARM_ERROR", e.message, e)
        }
    }

    @ReactMethod
    fun startMonitoring(promise: Promise) {
        try {
            Config.batterySettingLabel = Logger.getBatteryOptimizationSetting(reactContext)
            Logger.startNewRun(
                scenario = Config.currentScenario,
                arm = Config.activeArm.label,
                movementMode = Config.movementMode
            )
            EventStore.onArmed()

            GeofenceManager.registerGeofence(
                context = reactContext,
                onSuccess = {
                    Config.isMonitoringArmed = true
                    sendEvent("onStateChanged", Arguments.createMap().apply {
                        putString("state", "ARMED")
                    })
                    promise.resolve(true)
                },
                onFailure = { e ->
                    promise.reject("GEOFENCE_REGISTRATION_FAILED", e.message, e)
                }
            )
        } catch (e: Exception) {
            promise.reject("START_ERROR", e.message, e)
        }
    }

    @ReactMethod
    fun stopMonitoring(promise: Promise) {
        try {
            GeofenceManager.removeGeofences(reactContext) {
                EventStore.onDisarmed()
                Config.isMonitoringArmed = false
                sendEvent("onStateChanged", Arguments.createMap().apply {
                    putString("state", "IDLE")
                })
                promise.resolve(true)
            }
        } catch (e: Exception) {
            promise.reject("STOP_ERROR", e.message, e)
        }
    }

    @ReactMethod
    fun triggerManualBurst(promise: Promise) {
        try {
            val intent = Intent(reactContext, BurstService::class.java).apply {
                putExtra(BurstService.EXTRA_TRIGGER, "rn_manual_test")
            }
            ContextCompat.startForegroundService(reactContext, intent)
            Logger.logWake(trigger = "rn_manual_test", geofenceRequestId = "manual", isColdStart = false)
            promise.resolve(true)
        } catch (e: Exception) {
            promise.reject("BURST_ERROR", e.message, e)
        }
    }

    @ReactMethod
    fun checkPermissions(promise: Promise) {
        val map = Arguments.createMap().apply {
            putBoolean("fineLocation", PermissionHelper.hasFineLocation(reactContext))
            putBoolean("backgroundLocation", PermissionHelper.hasBackgroundLocation(reactContext))
            putBoolean("postNotifications", PermissionHelper.hasPostNotifications(reactContext))
            putBoolean("batteryExempt", PermissionHelper.isIgnoringBatteryOptimizations(reactContext))
        }
        promise.resolve(map)
    }

    @ReactMethod
    fun computeDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double, promise: Promise) {
        val distance = DecisionEngine.computeDistanceM(lat1, lon1, lat2, lon2)
        promise.resolve(distance)
    }
}
