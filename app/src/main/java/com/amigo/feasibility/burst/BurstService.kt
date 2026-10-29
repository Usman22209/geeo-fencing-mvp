package com.amigo.feasibility.burst

import android.annotation.SuppressLint
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.location.Location
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import com.amigo.feasibility.Config
import com.amigo.feasibility.R
import com.amigo.feasibility.engine.DecisionEngine
import com.amigo.feasibility.logger.Logger
import com.amigo.feasibility.model.FixData
import com.amigo.feasibility.notification.NotificationSender
import com.amigo.feasibility.store.EventStore
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority

/**
 * Bounded high-accuracy location burst foreground service per specification section 4.
 * Gathers fresh GPS fixes, evaluates proximity approach via DecisionEngine,
 * triggers EventStore and NotificationSender on confirmation, and cleanly terminates.
 */
class BurstService : Service() {

    companion object {
        const val EXTRA_TRIGGER = "extra_trigger"
        private const val FOREGROUND_NOTIFICATION_ID = 2001
    }

    private lateinit var fusedLocationClient: FusedLocationProviderClient
    private lateinit var locationCallback: LocationCallback
    private val handler = Handler(Looper.getMainLooper())
    private val stopBurstRunnable = Runnable {
        Logger.logNote("Burst timeout reached (${Config.BURST_DURATION_MS} ms). Stopping burst.")
        stopBurst()
    }

    private val collectedFixes = mutableListOf<FixData>()
    private val decisionEngine = DecisionEngine(
        DecisionEngine.Params(
            maxFixAgeMs = Config.MAX_FIX_AGE_MS,
            maxAccuracyM = Config.MAX_ACCURACY_M,
            windowN = Config.WINDOW_N,
            minValidFixes = Config.MIN_VALID_FIXES,
            proximityM = Config.PROXIMITY_M,
            stationaryM = Config.STATIONARY_M,
            minDecreasingSteps = Config.MIN_DECREASING_STEPS
        )
    )

    private var burstStartTimeElapsed: Long = 0L

    override fun onCreate() {
        super.onCreate()
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
        setupLocationCallback()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val trigger = intent?.getStringExtra(EXTRA_TRIGGER) ?: "manual"
        burstStartTimeElapsed = SystemClock.elapsedRealtime()

        // 1. Start foreground immediately with location type
        startForegroundWithNotification(trigger)
        Logger.logNote("BurstService active: bounded window of ${Config.BURST_DURATION_MS} ms started.")

        // 2. Schedule automatic timeout to guarantee bounded duration
        handler.removeCallbacks(stopBurstRunnable)
        handler.postDelayed(stopBurstRunnable, Config.BURST_DURATION_MS)

        // 3. Request high accuracy location updates
        requestHighAccuracyLocationUpdates()

        return START_NOT_STICKY
    }

    private fun startForegroundWithNotification(trigger: String) {
        val notification = NotificationCompat.Builder(this, NotificationSender.BURST_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle("AMIGO Location Burst Active")
            .setContentText("Gathering high-accuracy fixes (Trigger: $trigger)")
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                FOREGROUND_NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
            )
        } else {
            startForeground(FOREGROUND_NOTIFICATION_ID, notification)
        }
    }

    private fun setupLocationCallback() {
        locationCallback = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                for (location in result.locations) {
                    processLocationFix(location)
                }
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun requestHighAccuracyLocationUpdates() {
        val locationRequest = LocationRequest.Builder(
            Priority.PRIORITY_HIGH_ACCURACY,
            Config.LOCATION_INTERVAL_MS
        )
            .setMinUpdateIntervalMillis(Config.LOCATION_MIN_INTERVAL_MS)
            .setWaitForAccurateLocation(false)
            .build()

        try {
            fusedLocationClient.requestLocationUpdates(
                locationRequest,
                locationCallback,
                Looper.getMainLooper()
            ).addOnFailureListener { e ->
                Logger.logNote("Location updates request FAILED: ${e.message}")
                stopBurst()
            }
        } catch (e: Exception) {
            Logger.logNote("Exception requesting location updates: ${e.message}")
            stopBurst()
        }
    }

    private fun processLocationFix(loc: Location) {
        val nowWall = System.currentTimeMillis()
        val fixTimestamp = loc.time
        val ageMs = (nowWall - fixTimestamp).coerceAtLeast(0)

        val distanceToTarget = DecisionEngine.computeDistanceM(
            loc.latitude,
            loc.longitude,
            Config.targetLatitude,
            Config.targetLongitude
        )

        val fixData = FixData(
            lat = loc.latitude,
            lng = loc.longitude,
            accuracyM = loc.accuracy,
            timestampMs = fixTimestamp,
            receiptWallMs = nowWall,
            ageMs = ageMs,
            provider = loc.provider ?: "fused",
            distanceToTargetM = distanceToTarget
        )

        // 1. Log fix record
        Logger.logFix(fixData)
        collectedFixes.add(fixData)

        // 2. Evaluate decision engine over sliding window
        val decision = decisionEngine.evaluate(
            fixes = collectedFixes,
            targetLat = Config.targetLatitude,
            targetLng = Config.targetLongitude
        )

        // 3. Log decision record
        Logger.logDecision(decision)

        // 4. Handle positive decision
        if (decision.isConfirmed) {
            Logger.logNote("Positive approach confirmed by engine! Proceeding to EventStore.")
            val eventId = EventStore.recordEventIfConfirmed(decision)
            if (eventId != null) {
                // Step 5: Post notification separately after event is stored
                NotificationSender.postNotification(
                    context = applicationContext,
                    eventIdRef = eventId,
                    distanceM = distanceToTarget
                )
                // Stop burst early upon confirmed event
                stopBurst()
            }
        }
    }

    private fun stopBurst() {
        handler.removeCallbacks(stopBurstRunnable)
        try {
            fusedLocationClient.removeLocationUpdates(locationCallback)
        } catch (e: Exception) {
            Logger.logNote("Error removing location updates: ${e.message}")
        }

        val duration = SystemClock.elapsedRealtime() - burstStartTimeElapsed
        Logger.logBattery("Burst ended: duration=${duration}ms, total_fixes=${collectedFixes.size}")

        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        super.onDestroy()
        handler.removeCallbacks(stopBurstRunnable)
    }

    override fun onBind(intent: Intent?): IBinder? = null
}

