package com.amigo.feasibility.ui

import android.Manifest
import android.annotation.SuppressLint
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.Location
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.Looper
import android.view.View
import android.widget.EditText
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.amigo.feasibility.Config
import com.amigo.feasibility.R
import com.amigo.feasibility.burst.BurstService
import com.amigo.feasibility.databinding.ActivityMainBinding
import com.amigo.feasibility.engine.DecisionEngine
import com.amigo.feasibility.geofence.GeofenceManager
import com.amigo.feasibility.logger.Logger
import com.amigo.feasibility.permission.PermissionHelper
import com.amigo.feasibility.store.EventStore
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private var isMonitoringActive = false

    // Passive foreground live distance tracking
    private var liveLocationCallback: LocationCallback? = null
    private var lastKnownLocation: Location? = null

    // UI State Enum
    enum class UiState(val label: String, val colorRes: Int, val bgRes: Int) {
        IDLE("IDLE", R.color.state_gray, R.color.state_gray_bg),
        ARMED("ARMED", R.color.state_blue, R.color.state_blue_bg),
        BURST_ACTIVE("BURSTING", R.color.state_amber, R.color.state_amber_bg),
        EVENT_CONFIRMED("CONFIRMED", R.color.state_green, R.color.state_green_bg)
    }

    private var currentUiState = UiState.IDLE

    // Permissions Request Launcher
    private val locationPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        val fineGranted = permissions[Manifest.permission.ACCESS_FINE_LOCATION] ?: false
        if (fineGranted) {
            startLiveDistanceTracking()
            acquireCurrentLocationAndRefresh()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                checkBackgroundLocation()
            }
        } else {
            Toast.makeText(this, "Fine location permission is required", Toast.LENGTH_LONG).show()
        }
    }

    private val backgroundLocationLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { /* state refreshed in onResume */ }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        initCoordinateInputs()
        setupDemoGuideAndScenarios()
        setupTargetButtons()
        setupArmRadiusRadio()
        setupMonitoringToggle()
        setupQuickActions()
        setupLogObserver()
        updateBatteryDisplay()

        // Restore armed state if previously armed
        if (Config.isMonitoringArmed) {
            isMonitoringActive = true
            setUiState(UiState.ARMED)
        } else {
            setUiState(UiState.IDLE)
        }
    }

    override fun onResume() {
        super.onResume()
        updateBatteryDisplay()
        refreshLogView()
        checkAndShowPermissionBanner()
        if (PermissionHelper.hasFineLocation(this)) {
            startLiveDistanceTracking()
        }
    }

    override fun onPause() {
        super.onPause()
        stopLiveDistanceTracking()
    }

    // =========================================================================
    // 0. DEMO GUIDE & SCENARIOS
    // =========================================================================

    private fun setupDemoGuideAndScenarios() {
        // Collapsible Guide toggle
        var isGuideVisible = true
        binding.headerDemoGuide.setOnClickListener {
            isGuideVisible = !isGuideVisible
            binding.layoutGuideContent.visibility = if (isGuideVisible) View.VISIBLE else View.GONE
            binding.tvToggleGuide.text = if (isGuideVisible) "Hide ▲" else "Show ▼"
        }

        // Scenario selector buttons
        fun updateScenarioSelection(selected: String) {
            Config.currentScenario = selected
            addHumanLog("📋 Selected scenario: $selected")
            Toast.makeText(this, "Active test: $selected", Toast.LENGTH_SHORT).show()

            val primaryColor = ContextCompat.getColor(this, R.color.accent)
            val whiteColor = ContextCompat.getColor(this, R.color.text_white)
            val grayTextColor = ContextCompat.getColor(this, R.color.text_primary)

            binding.btnScenarioPositive.apply {
                if (selected.contains("Positive")) {
                    setBackgroundColor(primaryColor)
                    setTextColor(whiteColor)
                } else {
                    backgroundTintList = ContextCompat.getColorStateList(this@MainActivity, R.color.input_bg)
                    setTextColor(grayTextColor)
                }
            }
            binding.btnScenarioNegativeA.apply {
                if (selected.contains("Stationary")) {
                    setBackgroundColor(primaryColor)
                    setTextColor(whiteColor)
                } else {
                    backgroundTintList = ContextCompat.getColorStateList(this@MainActivity, R.color.input_bg)
                    setTextColor(grayTextColor)
                }
            }
            binding.btnScenarioNegativeB.apply {
                if (selected.contains("Outside")) {
                    setBackgroundColor(primaryColor)
                    setTextColor(whiteColor)
                } else {
                    backgroundTintList = ContextCompat.getColorStateList(this@MainActivity, R.color.input_bg)
                    setTextColor(grayTextColor)
                }
            }
        }

        binding.btnScenarioPositive.setOnClickListener {
            updateScenarioSelection("Positive Approach")
        }
        binding.btnScenarioNegativeA.setOnClickListener {
            updateScenarioSelection("Negative A (Stationary)")
        }
        binding.btnScenarioNegativeB.setOnClickListener {
            updateScenarioSelection("Negative B (Outside 40m)")
        }

        // Fix permission banner button
        binding.btnFixPermission.setOnClickListener {
            if (!PermissionHelper.hasFineLocation(this)) {
                ensureLocationPermission()
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && !PermissionHelper.hasBackgroundLocation(this)) {
                checkBackgroundLocation()
            } else {
                showPermissionsDialog()
            }
        }
    }

    private fun checkAndShowPermissionBanner() {
        val hasFine = PermissionHelper.hasFineLocation(this)
        val hasBg = PermissionHelper.hasBackgroundLocation(this)
        val hasNotif = PermissionHelper.hasPostNotifications(this)

        if (!hasFine) {
            binding.cardPermissionWarning.visibility = View.VISIBLE
            binding.tvPermissionWarningTitle.text = "Location Permission Required"
            binding.tvPermissionWarningDesc.text = "Tap 'Fix Now' to grant location access needed for proximity testing."
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && !hasBg) {
            binding.cardPermissionWarning.visibility = View.VISIBLE
            binding.tvPermissionWarningTitle.text = "Background Location Required"
            binding.tvPermissionWarningDesc.text = "Select 'Allow all the time' so Android wakes the app when locked."
        } else if (!hasNotif) {
            binding.cardPermissionWarning.visibility = View.VISIBLE
            binding.tvPermissionWarningTitle.text = "Notification Permission Required"
            binding.tvPermissionWarningDesc.text = "Tap 'Fix Now' to allow alerts when Opportunity is confirmed."
        } else {
            binding.cardPermissionWarning.visibility = View.GONE
        }
    }

    // =========================================================================
    // 1. COORDINATE INPUTS & QUICK SETTING
    // =========================================================================

    private fun initCoordinateInputs() {
        binding.etTargetLat.setText(String.format(Locale.US, "%.6f", Config.targetLatitude))
        binding.etTargetLng.setText(String.format(Locale.US, "%.6f", Config.targetLongitude))
        updateDistanceDisplay(null)
    }

    private fun setupTargetButtons() {
        // Save Target manually typed in fields
        binding.btnSaveTarget.setOnClickListener {
            saveCoordinatesFromInputs()
        }

        // Quick button: "📍 Here" (Current GPS)
        binding.btnQuickMyGps.setOnClickListener {
            acquireCurrentLocation { loc ->
                applyTargetCoordinates(loc.latitude, loc.longitude, "Target set to your current spot (0m)!")
            }
        }

        // Quick button: "🚶 60m Ahead"
        binding.btnQuick50mAhead.setOnClickListener {
            acquireCurrentLocation { loc ->
                val offsetLat = 60.0 / 111320.0
                applyTargetCoordinates(loc.latitude + offsetLat, loc.longitude, "Target set 60m Ahead! Walk North to approach.")
            }
        }

        // Quick button: "🚶 100m Ahead"
        binding.btnQuick100mAhead.setOnClickListener {
            acquireCurrentLocation { loc ->
                val offsetLat = 100.0 / 111320.0
                applyTargetCoordinates(loc.latitude + offsetLat, loc.longitude, "Target set 100m Ahead! Walk North to approach.")
            }
        }
    }

    private fun saveCoordinatesFromInputs() {
        val latStr = binding.etTargetLat.text?.toString()?.trim()
        val lngStr = binding.etTargetLng.text?.toString()?.trim()

        val lat = latStr?.toDoubleOrNull()
        val lng = lngStr?.toDoubleOrNull()

        if (lat != null && lng != null && lat in -90.0..90.0 && lng in -180.0..180.0) {
            Config.targetLatitude = lat
            Config.targetLongitude = lng
            addHumanLog("🎯 Target coordinates saved: (${String.format(Locale.US, "%.6f", lat)}, ${String.format(Locale.US, "%.6f", lng)})")
            Toast.makeText(this, "Target saved!", Toast.LENGTH_SHORT).show()
            lastKnownLocation?.let { updateDistanceDisplay(it) }
        } else {
            Toast.makeText(this, "Enter valid decimal latitude (-90 to 90) and longitude (-180 to 180)", Toast.LENGTH_LONG).show()
        }
    }

    private fun applyTargetCoordinates(lat: Double, lng: Double, confirmationMsg: String) {
        Config.targetLatitude = lat
        Config.targetLongitude = lng
        binding.etTargetLat.setText(String.format(Locale.US, "%.6f", lat))
        binding.etTargetLng.setText(String.format(Locale.US, "%.6f", lng))
        addHumanLog("🎯 $confirmationMsg (${String.format(Locale.US, "%.6f", lat)}, ${String.format(Locale.US, "%.6f", lng)})")
        Toast.makeText(this, confirmationMsg, Toast.LENGTH_LONG).show()
        lastKnownLocation?.let { updateDistanceDisplay(it) }
    }

    @SuppressLint("MissingPermission")
    private fun acquireCurrentLocation(onLocationReady: (Location) -> Unit) {
        if (!ensureLocationPermission()) return

        Toast.makeText(this, "Acquiring fresh GPS fix...", Toast.LENGTH_SHORT).show()
        val fused = LocationServices.getFusedLocationProviderClient(this)

        // Try getting fresh current location with timeout cancellation token
        val cts = CancellationTokenSource()
        fused.getCurrentLocation(Priority.PRIORITY_HIGH_ACCURACY, cts.token)
            .addOnSuccessListener { loc ->
                if (loc != null) {
                    lastKnownLocation = loc
                    onLocationReady(loc)
                } else {
                    // Fallback to lastLocation if current location returned null
                    fused.lastLocation.addOnSuccessListener { fallbackLoc ->
                        if (fallbackLoc != null) {
                            lastKnownLocation = fallbackLoc
                            onLocationReady(fallbackLoc)
                        } else {
                            Toast.makeText(this, "GPS fix not available. Please ensure Location is enabled in phone settings.", Toast.LENGTH_LONG).show()
                        }
                    }
                }
            }
            .addOnFailureListener {
                fused.lastLocation.addOnSuccessListener { fallbackLoc ->
                    if (fallbackLoc != null) {
                        lastKnownLocation = fallbackLoc
                        onLocationReady(fallbackLoc)
                    } else {
                        Toast.makeText(this, "Failed to get location: ${it.message}", Toast.LENGTH_LONG).show()
                    }
                }
            }
    }

    private fun acquireCurrentLocationAndRefresh() {
        acquireCurrentLocation { loc ->
            updateDistanceDisplay(loc)
        }
    }

    // =========================================================================
    // 2. ARM RADIUS SELECTION
    // =========================================================================

    private fun setupArmRadiusRadio() {
        if (Config.activeArm == Config.GeofenceArm.ARM_150M) {
            binding.rbArm150.isChecked = true
            binding.tvFenceIndicatorLabel.text = "Fence (150m)"
        } else {
            binding.rbArm50.isChecked = true
            binding.tvFenceIndicatorLabel.text = "Fence (50m)"
        }

        binding.rgArmRadius.setOnCheckedChangeListener { _, checkedId ->
            if (checkedId == R.id.rbArm150) {
                Config.activeArm = Config.GeofenceArm.ARM_150M
                binding.tvFenceIndicatorLabel.text = "Fence (150m)"
            } else {
                Config.activeArm = Config.GeofenceArm.ARM_50M
                binding.tvFenceIndicatorLabel.text = "Fence (50m)"
            }
            addHumanLog("📏 Geofence arm set to ${Config.activeArm.label}")
            lastKnownLocation?.let { updateDistanceDisplay(it) }
        }
    }

    // =========================================================================
    // 3. START / STOP MONITORING (ARM GEOFENCE)
    // =========================================================================

    private fun setupMonitoringToggle() {
        binding.btnToggleArm.setOnClickListener {
            if (isMonitoringActive) {
                stopMonitoring()
            } else {
                startMonitoring()
            }
        }
    }

    private fun startMonitoring() {
        if (!ensureLocationPermission()) return

        if (!PermissionHelper.hasBackgroundLocation(this)) {
            checkBackgroundLocation()
            return
        }

        // Save current input values
        saveCoordinatesFromInputs()

        Config.batterySettingLabel = Logger.getBatteryOptimizationSetting(this)
        Logger.startNewRun(
            scenario = Config.currentScenario,
            arm = Config.activeArm.label,
            movementMode = Config.movementMode
        )
        EventStore.onArmed()

        GeofenceManager.registerGeofence(
            context = this,
            onSuccess = {
                runOnUiThread {
                    isMonitoringActive = true
                    Config.isMonitoringArmed = true
                    setUiState(UiState.ARMED)
                    addHumanLog("✅ Geofence ARMED (${Config.activeArm.label}). Press Home or Lock phone and start walking.")
                    Toast.makeText(this, "Armed! Now background or lock your phone.", Toast.LENGTH_SHORT).show()
                }
            },
            onFailure = { e ->
                runOnUiThread {
                    addHumanLog("❌ Geofence registration failed: ${e.message}")
                    Toast.makeText(this, "Failed to arm geofence: ${e.message}", Toast.LENGTH_LONG).show()
                }
            }
        )
    }

    private fun stopMonitoring() {
        GeofenceManager.removeGeofences(this) {
            EventStore.onDisarmed()
            runOnUiThread {
                isMonitoringActive = false
                Config.isMonitoringArmed = false
                setUiState(UiState.IDLE)
                addHumanLog("🛑 Geofence DISARMED. Monitoring stopped.")
                Toast.makeText(this, "Monitoring stopped.", Toast.LENGTH_SHORT).show()
            }
        }
    }

    // =========================================================================
    // 4. UI STATE MACHINE
    // =========================================================================

    private fun setUiState(state: UiState) {
        currentUiState = state
        binding.tvStateBadge.text = state.label
        binding.tvStateBadge.setTextColor(ContextCompat.getColor(this, state.colorRes))
        binding.tvStateBadge.backgroundTintList = ContextCompat.getColorStateList(this, state.bgRes)

        when (state) {
            UiState.IDLE -> {
                binding.btnToggleArm.text = "▶ START MONITORING (ARM GEOFENCE)"
                binding.btnToggleArm.backgroundTintList = ContextCompat.getColorStateList(this, R.color.state_green)
            }
            UiState.ARMED -> {
                binding.btnToggleArm.text = "⏹ STOP MONITORING (DISARM)"
                binding.btnToggleArm.backgroundTintList = ContextCompat.getColorStateList(this, R.color.state_red)
            }
            UiState.BURST_ACTIVE -> {
                binding.btnToggleArm.text = "⏹ STOP MONITORING (BURSTING...)"
                binding.btnToggleArm.backgroundTintList = ContextCompat.getColorStateList(this, R.color.state_amber)
            }
            UiState.EVENT_CONFIRMED -> {
                binding.btnToggleArm.text = "⏹ STOP MONITORING (EVENT CONFIRMED!)"
                binding.btnToggleArm.backgroundTintList = ContextCompat.getColorStateList(this, R.color.state_green)
            }
        }
    }

    // =========================================================================
    // 5. LIVE DISTANCE DISPLAY (PASSIVE FOREGROUND)
    // =========================================================================

    @SuppressLint("MissingPermission")
    private fun startLiveDistanceTracking() {
        if (!PermissionHelper.hasFineLocation(this)) return
        stopLiveDistanceTracking()

        val fused = LocationServices.getFusedLocationProviderClient(this)
        val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 1500)
            .setMinUpdateIntervalMillis(1000)
            .build()

        liveLocationCallback = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                val loc = result.lastLocation ?: return
                lastKnownLocation = loc
                updateDistanceDisplay(loc)
            }
        }

        fused.requestLocationUpdates(request, liveLocationCallback!!, Looper.getMainLooper())
    }

    private fun stopLiveDistanceTracking() {
        liveLocationCallback?.let {
            LocationServices.getFusedLocationProviderClient(this).removeLocationUpdates(it)
        }
        liveLocationCallback = null
    }

    private fun updateDistanceDisplay(loc: Location?) {
        if (loc == null) {
            binding.tvDistanceValue.text = "-- m"
            binding.tvDistanceStatus.text = "Waiting for GPS fix..."
            binding.progressDistance.progress = 0
            return
        }

        val distance = DecisionEngine.computeDistanceM(
            loc.latitude,
            loc.longitude,
            Config.targetLatitude,
            Config.targetLongitude
        )

        val distanceStr = if (distance > 1000.0) {
            String.format(Locale.US, "%.1f km", distance / 1000.0)
        } else {
            String.format(Locale.US, "%.0f m", distance)
        }
        binding.tvDistanceValue.text = distanceStr

        val fenceRadius = Config.activeArm.radiusMeters.toDouble()
        val proximity = Config.PROXIMITY_M

        when {
            distance <= proximity -> {
                binding.tvDistanceValue.setTextColor(ContextCompat.getColor(this, R.color.state_green))
                binding.tvDistanceStatus.text = "🎯 In Proximity (${String.format(Locale.US, "%.0f", distance)}m ≤ ${proximity.toInt()}m)!"
                binding.tvDistanceStatus.setTextColor(ContextCompat.getColor(this, R.color.state_green))
                binding.tvDistanceStatus.setBackgroundColor(ContextCompat.getColor(this, R.color.state_green_bg))
                binding.progressDistance.progress = 100
            }
            distance <= fenceRadius -> {
                binding.tvDistanceValue.setTextColor(ContextCompat.getColor(this, R.color.state_amber))
                binding.tvDistanceStatus.text = "Inside ${fenceRadius.toInt()}m Fence — Approaching Target"
                binding.tvDistanceStatus.setTextColor(ContextCompat.getColor(this, R.color.state_amber))
                binding.tvDistanceStatus.setBackgroundColor(ContextCompat.getColor(this, R.color.state_amber_bg))
                val pct = ((1.0 - ((distance - proximity) / (fenceRadius - proximity))) * 100).toInt().coerceIn(0, 100)
                binding.progressDistance.progress = pct
            }
            else -> {
                binding.tvDistanceValue.setTextColor(ContextCompat.getColor(this, R.color.text_primary))
                binding.tvDistanceStatus.text = "Outside Fence (GPS ±${loc.accuracy.toInt()}m)"
                binding.tvDistanceStatus.setTextColor(ContextCompat.getColor(this, R.color.text_secondary))
                binding.tvDistanceStatus.setBackgroundColor(ContextCompat.getColor(this, R.color.state_gray_bg))
                binding.progressDistance.progress = 0
            }
        }
    }

    // =========================================================================
    // 6. QUICK ACTION BUTTONS
    // =========================================================================

    private fun setupQuickActions() {
        // Test 60s Burst (For instant outdoor/indoor calibration)
        binding.btnTriggerBurstTest.setOnClickListener {
            if (!ensureLocationPermission()) return@setOnClickListener
            val intent = Intent(this, BurstService::class.java).apply {
                putExtra(BurstService.EXTRA_TRIGGER, "ui_manual_test")
            }
            ContextCompat.startForegroundService(this, intent)
            Logger.logWake(trigger = "ui_manual_test", geofenceRequestId = "manual", isColdStart = false)
            setUiState(UiState.BURST_ACTIVE)
            addHumanLog("⚡ Test burst started (gathering 60s of high-accuracy 1Hz GPS fixes)")
            Toast.makeText(this, "Burst active for 60s", Toast.LENGTH_SHORT).show()
        }

        // Export Logs via Share Sheet
        binding.btnExportLogs.setOnClickListener {
            exportCurrentLog()
        }

        // Add Note
        binding.btnAddNote.setOnClickListener {
            val et = EditText(this).apply {
                hint = "e.g. notification seen on lock screen at 13:20"
                setSingleLine()
            }
            AlertDialog.Builder(this)
                .setTitle("Add Tester Note")
                .setMessage("Enter field observation to append to JSONL log:")
                .setView(et)
                .setPositiveButton("Add Note") { _, _ ->
                    val text = et.text.toString().trim()
                    if (text.isNotEmpty()) {
                        Logger.logNote(text)
                        addHumanLog("📝 Note: $text")
                        Toast.makeText(this, "Note saved to log", Toast.LENGTH_SHORT).show()
                    }
                }
                .setNegativeButton("Cancel", null)
                .show()
        }

        // Permissions Status & Dialog
        binding.btnPermissions.setOnClickListener {
            showPermissionsDialog()
        }
    }

    // =========================================================================
    // 7. PERMISSIONS & BATTERY
    // =========================================================================

    private fun ensureLocationPermission(): Boolean {
        if (PermissionHelper.hasFineLocation(this)) return true
        locationPermissionLauncher.launch(
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION,
                Manifest.permission.POST_NOTIFICATIONS
            )
        )
        return false
    }

    private fun checkBackgroundLocation() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && !PermissionHelper.hasBackgroundLocation(this)) {
            AlertDialog.Builder(this)
                .setTitle("Background Location Required")
                .setMessage("To wake the app when your screen is locked, Android requires 'Allow all the time' location access.\n\nPlease select 'Allow all the time' on the next screen.")
                .setPositiveButton("Continue") { _, _ ->
                    backgroundLocationLauncher.launch(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
                }
                .setNegativeButton("Cancel", null)
                .show()
        }
    }

    private fun showPermissionsDialog() {
        val fine = PermissionHelper.hasFineLocation(this)
        val bg = PermissionHelper.hasBackgroundLocation(this)
        val notif = PermissionHelper.hasPostNotifications(this)
        val battExempt = PermissionHelper.isIgnoringBatteryOptimizations(this)

        val message = buildString {
            append(if (fine) "✅" else "❌").append(" Fine Location: ").append(if (fine) "Granted\n" else "Missing\n")
            append(if (bg) "✅" else "⚠️").append(" Background Location: ").append(if (bg) "Granted ('All the time')\n" else "Missing\n")
            append(if (notif) "✅" else "❌").append(" Notifications: ").append(if (notif) "Granted\n" else "Missing\n")
            append(if (battExempt) "✅" else "⚠️").append(" Battery Optimization: ").append(if (battExempt) "Unrestricted\n" else "Optimized (May throttle)")
        }

        AlertDialog.Builder(this)
            .setTitle("Permission & Restriction Status")
            .setMessage(message)
            .setPositiveButton("Request Missing") { _, _ -> ensureLocationPermission() }
            .setNeutralButton("Battery Settings") { _, _ ->
                try {
                    startActivity(PermissionHelper.createBatteryOptimizationIntent(this))
                } catch (_: Exception) {
                    startActivity(PermissionHelper.createAppSettingsIntent(this))
                }
            }
            .setNegativeButton("Close", null)
            .show()
    }

    private fun updateBatteryDisplay() {
        val ifilter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        val battery = registerReceiver(null, ifilter)
        val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
        val pct = if (level >= 0 && scale > 0) (level * 100 / scale) else -1
        val status = battery?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val charging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL
        binding.tvBatteryInfo.text = "🔋 ${pct}%${if (charging) " ⚡" else ""}"
    }

    // =========================================================================
    // 8. LOGS & EVENT OBSERVER
    // =========================================================================

    private val humanLogLines = mutableListOf<String>()

    private fun addHumanLog(message: String) {
        val time = SimpleDateFormat("HH:mm:ss", Locale.US).format(Date())
        val line = "[$time] $message"
        humanLogLines.add(line)
        if (humanLogLines.size > 100) humanLogLines.removeAt(0)
        refreshLogView()
    }

    private fun setupLogObserver() {
        Logger.onLogAppended = { rawLine ->
            runOnUiThread {
                val formatted = formatRawLogToReadable(rawLine)
                if (formatted != null) {
                    addHumanLog(formatted)
                }

                if (rawLine.contains("\"record_type\":\"wake\"")) {
                    if (currentUiState == UiState.ARMED) setUiState(UiState.BURST_ACTIVE)
                }
                if (rawLine.contains("\"record_type\":\"event\"")) {
                    setUiState(UiState.EVENT_CONFIRMED)
                }
                if (rawLine.contains("Burst timeout") || rawLine.contains("Burst ended")) {
                    if (currentUiState == UiState.BURST_ACTIVE) {
                        if (isMonitoringActive) setUiState(UiState.ARMED) else setUiState(UiState.IDLE)
                    }
                }
            }
        }
    }

    private fun formatRawLogToReadable(rawLine: String): String? {
        return try {
            val jsonStr = rawLine.substringAfter(": ").takeIf { it.startsWith("{") } ?: rawLine
            val json = org.json.JSONObject(jsonStr)
            when (json.optString("record_type")) {
                "wake" -> "🔔 WAKE TRIGGER: ${json.optString("trigger")} (cold_start=${json.optBoolean("is_cold_start")})"
                "fix" -> {
                    val dist = json.optDouble("distance_to_target_m", -1.0)
                    val acc = json.optDouble("horizontal_accuracy_m", -1.0)
                    val distStr = if (dist > 1000) String.format(Locale.US, "%.1fkm", dist / 1000) else "${dist.toInt()}m"
                    "📡 GPS FIX: dist=$distStr, acc=±${acc.toInt()}m"
                }
                "decision" -> {
                    val code = json.optString("reason_code")
                    val icon = when (code) {
                        "EVENT_CONFIRMED" -> "✅"
                        "OUTSIDE_PROXIMITY" -> "📏"
                        "STATIONARY" -> "🧍"
                        "NOT_APPROACHING" -> "↗️"
                        "LOW_ACCURACY" -> "⚠️"
                        "STALE_FIXES", "INSUFFICIENT_FIXES" -> "⏳"
                        else -> "ℹ️"
                    }
                    "$icon DECISION: $code (${json.optString("reason_details")})"
                }
                "event" -> "🎉 EVENT CONFIRMED! Stored event_id=${json.optString("event_id").take(8)}..."
                "notification" -> {
                    val outcome = json.optString("outcome")
                    if (outcome == "posted") "🔔 NOTIFICATION POSTED TO PHONE!" else "❌ Notification failed: $outcome"
                }
                "recovery" -> "♻️ Recovery: ${json.optString("situation")} -> ${json.optString("result")}"
                "battery" -> "🔋 Battery record: ${json.optInt("battery_level")}% (${json.optString("note", "")})"
                "run_header" -> "🏁 Run started on ${json.optString("device_model")} (${json.optString("scenario")}, ${json.optString("arm")})"
                "note" -> {
                    val note = json.optString("note")
                    if (note.startsWith("Geofence") || note.startsWith("BurstService") || note.startsWith("RecoveryManager")) {
                        "ℹ️ $note"
                    } else null
                }
                else -> null
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun refreshLogView() {
        binding.tvLogCount.text = "${humanLogLines.size} events"
        if (humanLogLines.isEmpty()) {
            binding.tvLogs.text = "[READY] Ready. Set target and tap START."
        } else {
            binding.tvLogs.text = humanLogLines.joinToString("\n")
            binding.scrollLogs.post { binding.scrollLogs.fullScroll(View.FOCUS_DOWN) }
        }
    }

    private fun exportCurrentLog() {
        val file = Logger.getCurrentLogFile()
        if (file == null || !file.exists()) {
            Toast.makeText(this, "No logs recorded yet", Toast.LENGTH_SHORT).show()
            return
        }
        val uri: Uri = FileProvider.getUriForFile(this, "${packageName}.fileprovider", file)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(intent, "Share AMIGO Log"))
    }
}
