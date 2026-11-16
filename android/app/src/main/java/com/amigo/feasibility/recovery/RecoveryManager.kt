package com.amigo.feasibility.recovery

import android.content.Context
import com.amigo.feasibility.geofence.GeofenceManager
import com.amigo.feasibility.logger.Logger

/**
 * Recovery Manager per specification section 4 & 12.
 * Re-registers outer geofence on app start, boot, or permission restoration.
 * Writes a recovery record.
 * STRICT ENFORCEMENT: Never creates an event or notification during recovery.
 */
object RecoveryManager {

    /**
     * Handles recovery scenario.
     * Re-registers geofence and logs recovery record.
     * STRICT SPEC RULE: Never creates an event or notification from recovery.
     */
    fun handleRecovery(context: Context, situation: String, details: String = "") {
        Logger.logNote("RecoveryManager initiated: situation=$situation")

        GeofenceManager.registerGeofence(
            context = context,
            onSuccess = {
                Logger.logRecovery(
                    situation = situation,
                    reArmedComponent = "outer_geofence",
                    result = "success",
                    details = details
                )
            },
            onFailure = { e ->
                Logger.logRecovery(
                    situation = situation,
                    reArmedComponent = "outer_geofence",
                    result = "failed: ${e.javaClass.simpleName} - ${e.message}",
                    details = details
                )
            }
        )
    }
}

