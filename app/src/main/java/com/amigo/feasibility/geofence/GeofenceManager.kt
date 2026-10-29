package com.amigo.feasibility.geofence

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import com.amigo.feasibility.Config
import com.amigo.feasibility.logger.Logger
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingClient
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices

/**
 * Manages Google Play Services outer geofence registration and removal per specification section 4.
 */
object GeofenceManager {

    const val GEOFENCE_REQUEST_ID = "AMIGO_OUTER_FENCE"
    const val ACTION_GEOFENCE_EVENT = "com.amigo.feasibility.ACTION_GEOFENCE_EVENT"

    private var geofencingClient: GeofencingClient? = null

    private fun getClient(context: Context): GeofencingClient {
        return geofencingClient ?: LocationServices.getGeofencingClient(context.applicationContext).also {
            geofencingClient = it
        }
    }

    private fun getGeofencePendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, GeofenceReceiver::class.java).apply {
            action = ACTION_GEOFENCE_EVENT
        }
        // Section 5: Geofence PendingIntent requires FLAG_MUTABLE on Android 12+ (API 31+)
        // because Play Services injects geofence transition data into the Intent.
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        return PendingIntent.getBroadcast(context, 0, intent, flags)
    }

    @SuppressLint("MissingPermission")
    fun registerGeofence(
        context: Context,
        onSuccess: (() -> Unit)? = null,
        onFailure: ((Exception) -> Unit)? = null
    ) {
        val client = getClient(context)
        val radius = Config.activeArm.radiusMeters

        val geofence = Geofence.Builder()
            .setRequestId(GEOFENCE_REQUEST_ID)
            .setCircularRegion(
                Config.targetLatitude,
                Config.targetLongitude,
                radius
            )
            .setExpirationDuration(Geofence.NEVER_EXPIRE)
            .setTransitionTypes(
                Geofence.GEOFENCE_TRANSITION_ENTER or
                Geofence.GEOFENCE_TRANSITION_DWELL or
                Geofence.GEOFENCE_TRANSITION_EXIT
            )
            .setLoiteringDelay(Config.GEOFENCE_DWELL_DELAY_MS)
            .build()

        val request = GeofencingRequest.Builder()
            .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER)
            .addGeofence(geofence)
            .build()

        val pendingIntent = getGeofencePendingIntent(context)

        client.addGeofences(request, pendingIntent)
            .addOnSuccessListener {
                Logger.logNote("Geofence registered: arm=${Config.activeArm.name}, radius=${radius}m, target=(${Config.targetLatitude}, ${Config.targetLongitude})")
                onSuccess?.invoke()
            }
            .addOnFailureListener { e ->
                Logger.logNote("Geofence registration FAILED: ${e.javaClass.simpleName} - ${e.message}")
                onFailure?.invoke(e)
            }
    }

    fun removeGeofences(
        context: Context,
        onComplete: (() -> Unit)? = null
    ) {
        val client = getClient(context)
        val pendingIntent = getGeofencePendingIntent(context)
        client.removeGeofences(pendingIntent)
            .addOnCompleteListener {
                Logger.logNote("Geofence removed.")
                onComplete?.invoke()
            }
    }
}

