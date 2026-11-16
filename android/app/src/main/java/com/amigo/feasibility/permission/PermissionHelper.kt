package com.amigo.feasibility.permission

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.content.ContextCompat
import com.amigo.feasibility.logger.Logger

/**
 * Handles permission status reporting and change logging per specification section 4 & 5.
 */
object PermissionHelper {

    private val cachedStates = mutableMapOf<String, Boolean>()

    fun checkAndLogPermission(context: Context, permission: String): Boolean {
        val current = ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
        val previous = cachedStates[permission]
        if (previous != null && previous != current) {
            Logger.logPermissionChange(
                permission = permission,
                oldState = previous,
                newState = current
            )
        }
        cachedStates[permission] = current
        return current
    }

    fun hasFineLocation(context: Context): Boolean =
        checkAndLogPermission(context, Manifest.permission.ACCESS_FINE_LOCATION)

    fun hasBackgroundLocation(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            checkAndLogPermission(context, Manifest.permission.ACCESS_BACKGROUND_LOCATION)
        } else {
            true
        }
    }

    fun hasPostNotifications(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            checkAndLogPermission(context, Manifest.permission.POST_NOTIFICATIONS)
        } else {
            true
        }
    }

    fun isIgnoringBatteryOptimizations(context: Context): Boolean {
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return false
        val current = powerManager.isIgnoringBatteryOptimizations(context.packageName)
        val previous = cachedStates["battery_optimizations_ignored"]
        if (previous != null && previous != current) {
            Logger.logPermissionChange(
                permission = "battery_optimizations_ignored",
                oldState = previous,
                newState = current
            )
        }
        cachedStates["battery_optimizations_ignored"] = current
        return current
    }

    fun createBatteryOptimizationIntent(context: Context): Intent {
        return Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = Uri.parse("package:${context.packageName}")
        }
    }

    fun createAppSettingsIntent(context: Context): Intent {
        return Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:${context.packageName}")
        }
    }
}

