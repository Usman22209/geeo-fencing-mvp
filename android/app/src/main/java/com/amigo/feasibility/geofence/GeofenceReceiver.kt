package com.amigo.feasibility.geofence

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
import com.amigo.feasibility.AmigoApplication
import com.amigo.feasibility.burst.BurstService
import com.amigo.feasibility.logger.Logger
import com.amigo.feasibility.store.EventStore
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent

/**
 * BroadcastReceiver for geofence transition PendingIntent per specification section 4 & 5.
 * First action: write a wake record! Then start the bounded location burst service.
 */
class GeofenceReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        val wasColdStart = AmigoApplication.isColdStart
        AmigoApplication.markColdStartHandled()

        if (intent == null) {
            Logger.logWake(
                trigger = "geofence_null_intent",
                geofenceRequestId = "unknown",
                isColdStart = wasColdStart
            )
            return
        }

        val geofencingEvent = GeofencingEvent.fromIntent(intent)
        if (geofencingEvent == null) {
            Logger.logWake(
                trigger = "geofence_null_event",
                geofenceRequestId = "unknown",
                isColdStart = wasColdStart
            )
            return
        }

        if (geofencingEvent.hasError()) {
            val errorCode = geofencingEvent.errorCode
            Logger.logWake(
                trigger = "geofence_error_$errorCode",
                geofenceRequestId = "error",
                isColdStart = wasColdStart
            )
            return
        }

        val transitionType = geofencingEvent.geofenceTransition
        val triggerStr = when (transitionType) {
            Geofence.GEOFENCE_TRANSITION_ENTER -> "geofence_enter"
            Geofence.GEOFENCE_TRANSITION_DWELL -> "geofence_dwell"
            Geofence.GEOFENCE_TRANSITION_EXIT -> "geofence_exit"
            else -> "geofence_other_$transitionType"
        }

        val triggeringGeofences = geofencingEvent.triggeringGeofences
        val requestId = triggeringGeofences?.firstOrNull()?.requestId ?: "unknown"

        // 1. FIRST ACTION: Write the wake record per specification section 4
        Logger.logWake(
            trigger = triggerStr,
            geofenceRequestId = requestId,
            isColdStart = wasColdStart
        )

        // Only start burst on ENTER or DWELL
        if (transitionType == Geofence.GEOFENCE_TRANSITION_ENTER || transitionType == Geofence.GEOFENCE_TRANSITION_DWELL) {
            startBurstService(context, triggerStr)
        } else if (transitionType == Geofence.GEOFENCE_TRANSITION_EXIT) {
            EventStore.onExited()
            Logger.logNote("Device exited geofence ($requestId). EventStore re-armed! Next ENTER will trigger fresh burst and notification.")
        }
    }

    private fun startBurstService(context: Context, trigger: String) {
        val serviceIntent = Intent(context, BurstService::class.java).apply {
            putExtra(BurstService.EXTRA_TRIGGER, trigger)
        }
        try {
            // Android 12+ restricts starting foreground services from background,
            // but geofence transition broadcast is documented as an exempt case.
            // Log outcome or exact exception per specification section 5.
            ContextCompat.startForegroundService(context, serviceIntent)
            Logger.logNote("BurstService started successfully via ContextCompat.startForegroundService from $trigger")
        } catch (e: Exception) {
            Logger.logNote("BurstService start FAILED from background: ${e.javaClass.simpleName}: ${e.message}")
        }
    }
}

