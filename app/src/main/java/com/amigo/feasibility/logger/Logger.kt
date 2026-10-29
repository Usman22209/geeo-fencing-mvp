package com.amigo.feasibility.logger

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.os.SystemClock
import com.amigo.feasibility.BuildConfig
import com.amigo.feasibility.Config
import com.amigo.feasibility.model.BatteryRecord
import com.amigo.feasibility.model.DecisionRecord
import com.amigo.feasibility.model.DecisionResult
import com.amigo.feasibility.model.EventRecord
import com.amigo.feasibility.model.FixData
import com.amigo.feasibility.model.FixRecord
import com.amigo.feasibility.model.LogRecord
import com.amigo.feasibility.model.NoteRecord
import com.amigo.feasibility.model.NotificationRecord
import com.amigo.feasibility.model.PermissionChangeRecord
import com.amigo.feasibility.model.RecoveryRecord
import com.amigo.feasibility.model.RunHeaderRecord
import com.amigo.feasibility.model.WakeRecord
import java.io.File
import java.io.FileWriter
import java.io.PrintWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.ConcurrentLinkedDeque
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

/**
 * Thread-safe append-only JSONL Logger per specification section 7.
 * Guarded by a single-thread executor to guarantee serialization order.
 */
object Logger {

    private val executor = Executors.newSingleThreadExecutor()
    private val seqCounter = AtomicLong(1)
    private var appContext: Context? = null

    private var currentRunId: String = "RUN-INIT"
    private var runStartElapsedMs: Long = SystemClock.elapsedRealtime()
    private var runStartWallMs: Long = System.currentTimeMillis()
    private var currentLogFile: File? = null

    // In-memory circular buffer of recent formatted log strings for UI display (last 50+)
    private val recentLogLines = ConcurrentLinkedDeque<String>()
    private const val MAX_RECENT_LOGS = 100

    // Callback for UI updates
    var onLogAppended: ((String) -> Unit)? = null

    // App state tracking
    @Volatile
    var currentAppState: String = "unknown" // "foreground", "background", "unknown"

    fun init(context: Context) {
        appContext = context.applicationContext
        val logsDir = File(context.filesDir, "logs")
        if (!logsDir.exists()) {
            logsDir.mkdirs()
        }
    }

    val runId: String
        get() = currentRunId

    /**
     * Starts a new test run, creates a new log file, and logs the run_header record.
     */
    fun startNewRun(
        scenario: String = Config.currentScenario,
        arm: String = Config.activeArm.label,
        movementMode: String = Config.movementMode
    ) {
        val context = appContext ?: return
        val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
        currentRunId = "RUN_${timestamp}_${Config.currentRunLabel}"
        runStartElapsedMs = SystemClock.elapsedRealtime()
        runStartWallMs = System.currentTimeMillis()
        seqCounter.set(1)

        val logsDir = File(context.filesDir, "logs")
        if (!logsDir.exists()) logsDir.mkdirs()
        val file = File(logsDir, "amigo_${currentRunId}.jsonl")
        currentLogFile = file

        // Build run_header record
        val batteryInfo = getBatteryStatus(context)
        val isBatterySaver = isBatterySaverOn(context)
        val networkState = getNetworkState(context)
        val batteryOpt = getBatteryOptimizationSetting(context)

        val configParams = mapOf(
            "target_lat" to Config.targetLatitude,
            "target_lng" to Config.targetLongitude,
            "geofence_arm" to Config.activeArm.name,
            "geofence_radius_m" to Config.activeArm.radiusMeters,
            "burst_duration_ms" to Config.BURST_DURATION_MS,
            "location_interval_ms" to Config.LOCATION_INTERVAL_MS,
            "max_fix_age_ms" to Config.MAX_FIX_AGE_MS,
            "max_accuracy_m" to Config.MAX_ACCURACY_M,
            "window_n" to Config.WINDOW_N,
            "min_valid_fixes" to Config.MIN_VALID_FIXES,
            "proximity_m" to Config.PROXIMITY_M,
            "stationary_m" to Config.STATIONARY_M,
            "min_decreasing_steps" to Config.MIN_DECREASING_STEPS,
            "cooldown_ms" to Config.COOLDOWN_MS
        )

        val permissionStates = mapOf(
            "fine_location" to hasPermission(context, android.Manifest.permission.ACCESS_FINE_LOCATION),
            "background_location" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                hasPermission(context, android.Manifest.permission.ACCESS_BACKGROUND_LOCATION)
            } else true,
            "post_notifications" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                hasPermission(context, android.Manifest.permission.POST_NOTIFICATIONS)
            } else true
        )

        val headerRecord = RunHeaderRecord(
            runId = currentRunId,
            tsWallMs = System.currentTimeMillis(),
            tsElapsedMs = SystemClock.elapsedRealtime(),
            appState = currentAppState,
            seq = seqCounter.getAndIncrement(),
            deviceModel = Build.MODEL,
            manufacturer = Build.MANUFACTURER,
            androidVersion = Build.VERSION.RELEASE,
            sdkInt = Build.VERSION.SDK_INT,
            appBuild = BuildConfig.VERSION_NAME,
            configParams = configParams,
            permissionStates = permissionStates,
            batteryLevel = batteryInfo.first,
            isBatterySaverOn = isBatterySaver,
            networkState = networkState,
            batteryOptimizationSetting = batteryOpt,
            scenario = scenario,
            arm = arm,
            movementMode = movementMode
        )

        appendRecord(headerRecord)
    }

    fun logWake(
        trigger: String,
        geofenceRequestId: String = "",
        isColdStart: Boolean = false
    ) {
        val delaySinceStart = SystemClock.elapsedRealtime() - runStartElapsedMs
        val record = WakeRecord(
            runId = currentRunId,
            tsWallMs = System.currentTimeMillis(),
            tsElapsedMs = SystemClock.elapsedRealtime(),
            appState = currentAppState,
            seq = seqCounter.getAndIncrement(),
            trigger = trigger,
            geofenceRequestId = geofenceRequestId,
            isColdStart = isColdStart,
            delaySinceStartMs = delaySinceStart
        )
        appendRecord(record)
    }

    fun logFix(fix: FixData) {
        val record = FixRecord(
            runId = currentRunId,
            tsWallMs = fix.receiptWallMs,
            tsElapsedMs = SystemClock.elapsedRealtime(),
            appState = currentAppState,
            seq = seqCounter.getAndIncrement(),
            lat = fix.lat,
            lng = fix.lng,
            horizontalAccuracyM = fix.accuracyM,
            fixTimestampMs = fix.timestampMs,
            fixAgeAtReceiptMs = fix.ageMs,
            provider = fix.provider,
            distanceToTargetM = fix.distanceToTargetM
        )
        appendRecord(record)
    }

    fun logDecision(result: DecisionResult) {
        val record = DecisionRecord(
            runId = currentRunId,
            tsWallMs = System.currentTimeMillis(),
            tsElapsedMs = SystemClock.elapsedRealtime(),
            appState = currentAppState,
            seq = seqCounter.getAndIncrement(),
            reasonCode = result.reasonCode.name,
            reasonDetails = result.reasonDetails,
            windowCount = result.windowCount,
            validCount = result.validCount,
            distanceTrend = result.distanceTrend,
            netDisplacementM = result.netDisplacementM,
            latestDistanceM = result.latestDistanceM,
            inputsCount = result.inputsUsed.size
        )
        appendRecord(record)
    }

    fun logEvent(eventId: String, eventTimeMs: Long, distanceM: Double, evidenceSummary: String) {
        val record = EventRecord(
            runId = currentRunId,
            tsWallMs = System.currentTimeMillis(),
            tsElapsedMs = SystemClock.elapsedRealtime(),
            appState = currentAppState,
            seq = seqCounter.getAndIncrement(),
            eventId = eventId,
            eventTimeMs = eventTimeMs,
            distanceM = distanceM,
            evidenceSummary = evidenceSummary
        )
        appendRecord(record)
    }

    fun logNotification(eventIdRef: String, attemptTimeMs: Long, outcome: String, errorText: String? = null) {
        val record = NotificationRecord(
            runId = currentRunId,
            tsWallMs = System.currentTimeMillis(),
            tsElapsedMs = SystemClock.elapsedRealtime(),
            appState = currentAppState,
            seq = seqCounter.getAndIncrement(),
            eventIdRef = eventIdRef,
            attemptTimeMs = attemptTimeMs,
            outcome = outcome,
            errorText = errorText
        )
        appendRecord(record)
    }

    fun logRecovery(situation: String, reArmedComponent: String, result: String, details: String) {
        val record = RecoveryRecord(
            runId = currentRunId,
            tsWallMs = System.currentTimeMillis(),
            tsElapsedMs = SystemClock.elapsedRealtime(),
            appState = currentAppState,
            seq = seqCounter.getAndIncrement(),
            situation = situation,
            reArmedComponent = reArmedComponent,
            result = result,
            details = details
        )
        appendRecord(record)
    }

    fun logPermissionChange(permission: String, oldState: Boolean, newState: Boolean) {
        val record = PermissionChangeRecord(
            runId = currentRunId,
            tsWallMs = System.currentTimeMillis(),
            tsElapsedMs = SystemClock.elapsedRealtime(),
            appState = currentAppState,
            seq = seqCounter.getAndIncrement(),
            permission = permission,
            oldState = oldState,
            newState = newState
        )
        appendRecord(record)
    }

    fun logBattery(note: String? = null) {
        val context = appContext ?: return
        val batteryInfo = getBatteryStatus(context)
        val duration = SystemClock.elapsedRealtime() - runStartElapsedMs
        val record = BatteryRecord(
            runId = currentRunId,
            tsWallMs = System.currentTimeMillis(),
            tsElapsedMs = SystemClock.elapsedRealtime(),
            appState = currentAppState,
            seq = seqCounter.getAndIncrement(),
            level = batteryInfo.first,
            isCharging = batteryInfo.second,
            runDurationMs = duration,
            note = note
        )
        appendRecord(record)
    }

    fun logNote(noteText: String) {
        val record = NoteRecord(
            runId = currentRunId,
            tsWallMs = System.currentTimeMillis(),
            tsElapsedMs = SystemClock.elapsedRealtime(),
            appState = currentAppState,
            seq = seqCounter.getAndIncrement(),
            noteText = noteText
        )
        appendRecord(record)
    }

    private fun appendRecord(record: LogRecord) {
        val jsonLine = record.toJsonString()
        executor.execute {
            try {
                val file = currentLogFile ?: run {
                    val context = appContext ?: return@execute
                    val logsDir = File(context.filesDir, "logs")
                    if (!logsDir.exists()) logsDir.mkdirs()
                    val f = File(logsDir, "amigo_${currentRunId}.jsonl")
                    currentLogFile = f
                    f
                }
                val writer = PrintWriter(FileWriter(file, true))
                writer.println(jsonLine)
                writer.flush()
                writer.close()
            } catch (e: Exception) {
                android.util.Log.e("AMIGO_LOGGER", "Failed to write log record", e)
            }
        }

        // Add to recent lines for UI display
        val displayLine = "[${record.recordType.uppercase()}] seq=${record.seq} ${record.appState}: $jsonLine"
        recentLogLines.addLast(displayLine)
        while (recentLogLines.size > MAX_RECENT_LOGS) {
            recentLogLines.pollFirst()
        }

        onLogAppended?.invoke(displayLine)
    }

    fun getRecentLogLines(count: Int = 50): List<String> {
        return recentLogLines.toList().takeLast(count)
    }

    fun getCurrentLogFile(): File? = currentLogFile

    fun getAllLogFiles(): List<File> {
        val context = appContext ?: return emptyList()
        val logsDir = File(context.filesDir, "logs")
        if (!logsDir.exists()) return emptyList()
        return logsDir.listFiles()?.filter { it.extension == "jsonl" }?.sortedByDescending { it.lastModified() } ?: emptyList()
    }

    // --- System Status Helpers ---

    private fun hasPermission(context: Context, permission: String): Boolean {
        return androidx.core.content.ContextCompat.checkSelfPermission(
            context,
            permission
        ) == android.content.pm.PackageManager.PERMISSION_GRANTED
    }

    private fun getBatteryStatus(context: Context): Pair<Int, Boolean> {
        val ifilter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        val batteryStatus: Intent? = context.registerReceiver(null, ifilter)
        val level: Int = batteryStatus?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale: Int = batteryStatus?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val batteryPct = if (level != -1 && scale != -1) (level * 100 / scale.toFloat()).toInt() else -1
        val status: Int = batteryStatus?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL
        return Pair(batteryPct, isCharging)
    }

    private fun isBatterySaverOn(context: Context): Boolean {
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        return powerManager?.isPowerSaveMode ?: false
    }

    fun getBatteryOptimizationSetting(context: Context): String {
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        val packageName = context.packageName
        return if (powerManager?.isIgnoringBatteryOptimizations(packageName) == true) {
            "unrestricted"
        } else {
            "optimized"
        }
    }

    private fun getNetworkState(context: Context): String {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return "unknown"
        val activeNetwork = cm.activeNetwork ?: return "disconnected"
        val caps = cm.getNetworkCapabilities(activeNetwork) ?: return "disconnected"
        return when {
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            else -> "connected_other"
        }
    }
}

