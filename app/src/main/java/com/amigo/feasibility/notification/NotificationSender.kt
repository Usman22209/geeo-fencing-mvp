package com.amigo.feasibility.notification

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.amigo.feasibility.R
import com.amigo.feasibility.logger.Logger
import com.amigo.feasibility.ui.MainActivity

/**
 * Handles dedicated notification delivery and logs notification records per specification.
 */
object NotificationSender {

    const val REMINDER_CHANNEL_ID = "amigo_proximity_channel"
    const val BURST_CHANNEL_ID = "amigo_burst_channel"
    private const val NOTIFICATION_ID = 1001

    fun createChannels(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            // Proximity reminder channel (High importance with sound and vibration)
            val reminderChannel = NotificationChannel(
                REMINDER_CHANNEL_ID,
                context.getString(R.string.channel_name),
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = context.getString(R.string.channel_desc)
                enableVibration(true)
                setShowBadge(true)
            }

            // Burst service foreground channel (Low/Default importance to minimize spam)
            val burstChannel = NotificationChannel(
                BURST_CHANNEL_ID,
                context.getString(R.string.burst_channel_name),
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = context.getString(R.string.burst_channel_desc)
                setShowBadge(false)
            }

            notificationManager.createNotificationChannel(reminderChannel)
            notificationManager.createNotificationChannel(burstChannel)
        }
    }

    /**
     * Posts proximity reminder notification and logs a separate notification record.
     */
    fun postNotification(context: Context, eventIdRef: String, distanceM: Double) {
        val attemptTime = System.currentTimeMillis()

        // 1. Check POST_NOTIFICATIONS permission on Android 13+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val granted = ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED

            if (!granted) {
                Logger.logNotification(
                    eventIdRef = eventIdRef,
                    attemptTimeMs = attemptTime,
                    outcome = "blocked_by_permission",
                    errorText = "POST_NOTIFICATIONS permission not granted"
                )
                return
            }
        }

        val managerCompat = NotificationManagerCompat.from(context)

        // 2. Check if notifications are enabled globally for app
        if (!managerCompat.areNotificationsEnabled()) {
            Logger.logNotification(
                eventIdRef = eventIdRef,
                attemptTimeMs = attemptTime,
                outcome = "blocked_by_permission",
                errorText = "Notifications disabled in app settings"
            )
            return
        }

        // 3. Check if channel is blocked
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = notificationManager.getNotificationChannel(REMINDER_CHANNEL_ID)
            if (channel != null && channel.importance == NotificationManager.IMPORTANCE_NONE) {
                Logger.logNotification(
                    eventIdRef = eventIdRef,
                    attemptTimeMs = attemptTime,
                    outcome = "blocked_by_channel",
                    errorText = "Notification channel '$REMINDER_CHANNEL_ID' is disabled/blocked"
                )
                return
            }
        }

        // 4. Build and post notification
        try {
            val tapIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                0,
                tapIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val notification = NotificationCompat.Builder(context, REMINDER_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle("AMIGO Target Approached!")
                .setContentText("Approached saved target! Distance: ${String.format("%.1f", distanceM)}m")
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_REMINDER)
                .setAutoCancel(true)
                .setContentIntent(pendingIntent)
                .setDefaults(NotificationCompat.DEFAULT_ALL)
                .build()

            managerCompat.notify(NOTIFICATION_ID, notification)

            // Log successful post
            Logger.logNotification(
                eventIdRef = eventIdRef,
                attemptTimeMs = attemptTime,
                outcome = "posted"
            )
        } catch (e: SecurityException) {
            Logger.logNotification(
                eventIdRef = eventIdRef,
                attemptTimeMs = attemptTime,
                outcome = "blocked_by_permission",
                errorText = e.message
            )
        } catch (e: Exception) {
            Logger.logNotification(
                eventIdRef = eventIdRef,
                attemptTimeMs = attemptTime,
                outcome = "exception",
                errorText = "${e::class.java.simpleName}: ${e.message}"
            )
        }
    }
}

