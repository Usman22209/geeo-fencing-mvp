package com.amigo.feasibility.recovery

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.amigo.feasibility.logger.Logger

/**
 * BroadcastReceiver for BOOT_COMPLETED and MY_PACKAGE_REPLACED per specification section 4 & 5.
 * Logs wake record, triggers RecoveryManager to re-register geofences.
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        val trigger = when (action) {
            Intent.ACTION_BOOT_COMPLETED -> "boot"
            Intent.ACTION_MY_PACKAGE_REPLACED -> "package_replaced"
            else -> "boot_action_$action"
        }

        // 1. Write wake record
        Logger.logWake(
            trigger = trigger,
            geofenceRequestId = "system_boot",
            isColdStart = true
        )

        // 2. Delegate to RecoveryManager to re-arm geofence
        RecoveryManager.handleRecovery(
            context = context,
            situation = trigger,
            details = "Action received: $action"
        )
    }
}

