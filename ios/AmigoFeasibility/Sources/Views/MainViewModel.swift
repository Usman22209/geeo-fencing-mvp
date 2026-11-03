import Foundation
import SwiftUI
import CoreLocation
import Combine

enum UiState {
    case idle
    case armed
    case burstActive
    case eventConfirmed

    var label: String {
        switch self {
        case .idle: return "IDLE"
        case .armed: return "ARMED"
        case .burstActive: return "BURSTING"
        case .eventConfirmed: return "CONFIRMED"
        }
    }

    var textColor: Color {
        switch self {
        case .idle: return AmigoColors.stateGray
        case .armed: return AmigoColors.stateBlue
        case .burstActive: return AmigoColors.stateAmber
        case .eventConfirmed: return AmigoColors.stateGreen
        }
    }

    var bgColor: Color {
        switch self {
        case .idle: return AmigoColors.stateGrayBg
        case .armed: return AmigoColors.stateBlueBg
        case .burstActive: return AmigoColors.stateAmberBg
        case .eventConfirmed: return AmigoColors.stateGreenBg
        }
    }

    var buttonTitle: String {
        switch self {
        case .idle: return "▶ START MONITORING (ARM GEOFENCE)"
        case .armed: return "⏹ STOP MONITORING (DISARM)"
        case .burstActive: return "⏹ STOP MONITORING (BURSTING...)"
        case .eventConfirmed: return "⏹ STOP MONITORING (EVENT CONFIRMED!)"
        }
    }

    var buttonColor: Color {
        switch self {
        case .idle: return AmigoColors.stateGreen
        case .armed: return AmigoColors.stateRed
        case .burstActive: return AmigoColors.stateAmber
        case .eventConfirmed: return AmigoColors.stateGreen
        }
    }
}

final class MainViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {

    @Published var uiState: UiState = .idle
    @Published var isMonitoringActive: Bool = false

    @Published var targetLatText: String = ""
    @Published var targetLngText: String = ""
    @Published var activeArm: Config.GeofenceArm = .arm50M
    @Published var selectedScenario: String = "Positive Approach"

    // Live Distance Card
    @Published var liveDistanceText: String = "-- m"
    @Published var liveDistanceColor: Color = AmigoColors.textPrimary
    @Published var liveStatusText: String = "Set target below to begin"
    @Published var liveStatusTextColor: Color = AmigoColors.textSecondary
    @Published var liveStatusBgColor: Color = AmigoColors.stateGrayBg
    @Published var liveProgress: Double = 0.0
    @Published var fenceIndicatorText: String = "Fence (50m)"

    @Published var batteryText: String = "🔋 --%"
    @Published var permissionWarningTitle: String? = nil
    @Published var permissionWarningDesc: String? = nil

    @Published var humanLogLines: [String] = []
    @Published var isGuideExpanded: Bool = true

    @Published var showNoteDialog: Bool = false
    @Published var noteInputText: String = ""

    @Published var showPermissionsDialog: Bool = false
    @Published var permissionsMessage: String = ""

    @Published var showShareSheet: Bool = false
    @Published var exportLogURL: URL? = nil

    @Published var alertMessage: String? = nil
    @Published var showAlert: Bool = false

    // Toast Notification
    @Published var toastMessage: String? = nil
    @Published var showToast: Bool = false
    private var toastTimer: Timer?

    private let passiveLocationManager = CLLocationManager()
    private var lastKnownLocation: CLLocation?
    private var pendingLocationAction: ((CLLocation) -> Void)?

    override init() {
        super.init()

        // Initialize state from Config
        targetLatText = String(format: "%.6f", Config.shared.targetLatitude)
        targetLngText = String(format: "%.6f", Config.shared.targetLongitude)
        activeArm = Config.shared.activeArm
        selectedScenario = Config.shared.currentScenario
        fenceIndicatorText = "Fence (\(Int(activeArm.radiusMeters))m)"

        if Config.shared.isMonitoringArmed {
            isMonitoringActive = true
            uiState = .armed
        } else {
            uiState = .idle
        }

        passiveLocationManager.delegate = self
        passiveLocationManager.desiredAccuracy = kCLLocationAccuracyBest
        passiveLocationManager.distanceFilter = 1.0

        setupLogObserver()
        setupBurstObserver()
        updateBatteryDisplay()
        checkPermissions()
        startLiveDistanceTracking()
    }

    // MARK: - Live Distance Tracking

    func startLiveDistanceTracking() {
        if PermissionHelper.hasFineLocation() {
            passiveLocationManager.startUpdatingLocation()
        }
    }

    func stopLiveDistanceTracking() {
        passiveLocationManager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        lastKnownLocation = loc
        updateDistanceDisplay(loc)

        if let pending = pendingLocationAction {
            pendingLocationAction = nil
            pending(loc)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        checkPermissions()
        if PermissionHelper.hasFineLocation() {
            passiveLocationManager.startUpdatingLocation()
        }
    }

    private func updateDistanceDisplay(_ loc: CLLocation?) {
        guard let loc = loc else {
            liveDistanceText = "-- m"
            liveDistanceColor = AmigoColors.textPrimary
            liveStatusText = "Waiting for GPS fix..."
            liveStatusTextColor = AmigoColors.textSecondary
            liveStatusBgColor = AmigoColors.stateGrayBg
            liveProgress = 0.0
            return
        }

        let distance = DecisionEngine.computeDistanceM(
            lat1: loc.coordinate.latitude,
            lon1: loc.coordinate.longitude,
            lat2: Config.shared.targetLatitude,
            lon2: Config.shared.targetLongitude
        )

        if distance > 1000.0 {
            liveDistanceText = String(format: "%.1f km", distance / 1000.0)
        } else {
            liveDistanceText = String(format: "%.0f m", distance)
        }

        let fenceRadius = activeArm.radiusMeters
        let proximity = Config.proximityM

        if distance <= proximity {
            liveDistanceColor = AmigoColors.stateGreen
            liveStatusText = String(format: "🎯 In Proximity (%.0fm ≤ %.0fm)!", distance, proximity)
            liveStatusTextColor = AmigoColors.stateGreen
            liveStatusBgColor = AmigoColors.stateGreenBg
            liveProgress = 1.0
        } else if distance <= fenceRadius {
            liveDistanceColor = AmigoColors.stateAmber
            liveStatusText = "Inside \(Int(fenceRadius))m Fence — Approaching Target"
            liveStatusTextColor = AmigoColors.stateAmber
            liveStatusBgColor = AmigoColors.stateAmberBg
            let pct = max(0.0, min(1.0, 1.0 - ((distance - proximity) / (fenceRadius - proximity))))
            liveProgress = pct
        } else {
            liveDistanceColor = AmigoColors.textPrimary
            liveStatusText = String(format: "Outside Fence (GPS ±%.0fm)", loc.horizontalAccuracy)
            liveStatusTextColor = AmigoColors.textSecondary
            liveStatusBgColor = AmigoColors.stateGrayBg
            liveProgress = 0.0
        }
    }

    // MARK: - Scenario & Target Setup

    func setScenario(_ scenario: String) {
        selectedScenario = scenario
        Config.shared.currentScenario = scenario
        addHumanLog("📋 Selected scenario: \(scenario)")
    }

    func setArm(_ arm: Config.GeofenceArm) {
        activeArm = arm
        Config.shared.activeArm = arm
        fenceIndicatorText = "Fence (\(Int(arm.radiusMeters))m)"
        addHumanLog("📏 Geofence arm set to \(arm.label)")
        updateDistanceDisplay(lastKnownLocation)
    }

    func saveTargetFromInputs() {
        guard let lat = Double(targetLatText.trimmingCharacters(in: .whitespaces)),
              let lng = Double(targetLngText.trimmingCharacters(in: .whitespaces)),
              lat >= -90.0 && lat <= 90.0,
              lng >= -180.0 && lng <= 180.0 else {
            presentAlert("Please enter valid decimal coordinates (-90 to 90 lat, -180 to 180 lng).")
            return
        }

        Config.shared.targetLatitude = lat
        Config.shared.targetLongitude = lng
        addHumanLog(String(format: "🎯 Target saved: (%.6f, %.6f)", lat, lng))
        updateDistanceDisplay(lastKnownLocation)
        presentAlert("Target saved!")
    }

    func setTargetToCurrentLocation() {
        acquireLocation { [weak self] loc in
            self?.applyCoordinates(
                lat: loc.coordinate.latitude,
                lng: loc.coordinate.longitude,
                msg: "Target set to your current spot (0m)!"
            )
        }
    }

    func setTargetAhead(meters: Double) {
        acquireLocation { [weak self] loc in
            let offsetLat = meters / 111320.0
            let newLat = loc.coordinate.latitude + offsetLat
            let newLng = loc.coordinate.longitude
            self?.applyCoordinates(
                lat: newLat,
                lng: newLng,
                msg: "Target set \(Int(meters))m Ahead! Walk North to approach."
            )
        }
    }

    private func acquireLocation(onReady: @escaping (CLLocation) -> Void) {
        if let loc = lastKnownLocation {
            onReady(loc)
            return
        }

        showToastNotification("Acquiring fresh GPS fix...")
        pendingLocationAction = onReady
        passiveLocationManager.requestWhenInUseAuthorization()
        passiveLocationManager.startUpdatingLocation()
    }

    private func applyCoordinates(lat: Double, lng: Double, msg: String) {
        Config.shared.targetLatitude = lat
        Config.shared.targetLongitude = lng
        targetLatText = String(format: "%.6f", lat)
        targetLngText = String(format: "%.6f", lng)
        addHumanLog(String(format: "🎯 %@ (%.6f, %.6f)", msg, lat, lng))
        updateDistanceDisplay(lastKnownLocation)
        presentAlert(msg)
    }

    // MARK: - Monitoring Controls

    func toggleMonitoring() {
        if isMonitoringActive {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }

    private func startMonitoring() {
        guard PermissionHelper.hasFineLocation() else {
            PermissionHelper.shared.requestPermissions()
            return
        }

        guard PermissionHelper.hasAlwaysLocation() else {
            PermissionHelper.shared.requestAlwaysLocation()
            return
        }

        saveTargetFromInputs()

        Logger.shared.startNewRun(
            scenario: Config.shared.currentScenario,
            arm: Config.shared.activeArm.label,
            movementMode: Config.shared.movementMode
        )
        EventStore.shared.onArmed()

        RegionManager.shared.registerGeofence(
            onSuccess: { [weak self] in
                DispatchQueue.main.async {
                    self?.isMonitoringActive = true
                    Config.shared.isMonitoringArmed = true
                    self?.uiState = .armed
                    self?.addHumanLog("✅ Geofence ARMED (\(Config.shared.activeArm.label)). Lock your phone and start walking.")
                    self?.presentAlert("Armed! Now lock your phone or switch apps.")
                }
            },
            onFailure: { [weak self] error in
                DispatchQueue.main.async {
                    self?.addHumanLog("❌ Geofence registration failed: \(error.localizedDescription)")
                    self?.presentAlert("Registration failed: \(error.localizedDescription)")
                }
            }
        )
    }

    private func stopMonitoring() {
        RegionManager.shared.removeGeofences { [weak self] in
            EventStore.shared.onDisarmed()
            DispatchQueue.main.async {
                self?.isMonitoringActive = false
                Config.shared.isMonitoringArmed = false
                self?.uiState = .idle
                self?.addHumanLog("🛑 Geofence DISARMED. Monitoring stopped.")
                self?.presentAlert("Monitoring stopped.")
            }
        }
    }

    // MARK: - Quick Actions

    func triggerManualBurstTest() {
        guard PermissionHelper.hasFineLocation() else {
            PermissionHelper.shared.requestPermissions()
            return
        }

        BurstManager.shared.startBurst(trigger: "ui_manual_test")
        Logger.shared.logWake(trigger: "ui_manual_test", geofenceRequestId: "manual", isColdStart: false)
        uiState = .burstActive
        addHumanLog("⚡ Test burst started (gathering 30s of high-accuracy 1Hz GPS fixes)")
    }

    func exportLogs() {
        if let file = Logger.shared.getCurrentLogFile(), FileManager.default.fileExists(atPath: file.path) {
            exportLogURL = file
            showShareSheet = true
        } else if let first = Logger.shared.getAllLogFiles().first {
            exportLogURL = first
            showShareSheet = true
        } else {
            presentAlert("No log files recorded yet.")
        }
    }

    func addNote() {
        let text = noteInputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        Logger.shared.logNote(text)
        addHumanLog("📝 Note: \(text)")
        noteInputText = ""
        showNoteDialog = false
    }

    func showPermissionsStatus() {
        let fine = PermissionHelper.hasFineLocation()
        let always = PermissionHelper.hasAlwaysLocation()
        let notif = PermissionHelper.hasNotificationPermission()

        var msg = ""
        msg += (fine ? "✅" : "❌") + " Fine Location: " + (fine ? "Granted\n" : "Missing\n")
        msg += (always ? "✅" : "⚠️") + " Background Location: " + (always ? "Granted ('Always')\n" : "Missing\n")
        msg += (notif ? "✅" : "❌") + " Notifications: " + (notif ? "Granted" : "Missing")

        permissionsMessage = msg
        showPermissionsDialog = true
    }

    // MARK: - Observers & Helpers

    private func setupLogObserver() {
        Logger.shared.onLogAppended = { [weak self] rawLine in
            DispatchQueue.main.async {
                if let formatted = self?.formatRawLogToReadable(rawLine) {
                    self?.addHumanLog(formatted)
                }

                if rawLine.contains("\"record_type\":\"wake\"") {
                    if self?.uiState == .armed {
                        self?.uiState = .burstActive
                    }
                }
                if rawLine.contains("\"record_type\":\"event\"") {
                    self?.uiState = .eventConfirmed
                }
                if rawLine.contains("Burst timeout") || rawLine.contains("Burst ended") {
                    if self?.uiState == .burstActive {
                        self?.uiState = (self?.isMonitoringActive == true) ? .armed : .idle
                    }
                }
            }
        }
    }

    private func setupBurstObserver() {
        BurstManager.shared.onBurstStatusChanged = { [weak self] isBursting in
            DispatchQueue.main.async {
                if isBursting {
                    self?.uiState = .burstActive
                } else if self?.isMonitoringActive == true {
                    self?.uiState = .armed
                } else {
                    self?.uiState = .idle
                }
            }
        }
    }

    func addHumanLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let line = "[\(formatter.string(from: Date()))] \(message)"
        humanLogLines.append(line)
        if humanLogLines.count > 100 {
            humanLogLines.removeFirst()
        }
    }

    private func formatRawLogToReadable(_ rawLine: String) -> String? {
        guard let data = rawLine.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["record_type"] as? String else {
            return nil
        }

        switch type {
        case "wake":
            let trigger = json["trigger"] as? String ?? "unknown"
            let isCold = json["is_cold_start"] as? Bool ?? false
            return "🔔 WAKE TRIGGER: \(trigger) (cold_start=\(isCold))"
        case "fix":
            let dist = json["distance_to_target_m"] as? Double ?? 0.0
            let acc = json["horizontal_accuracy_m"] as? Double ?? 0.0
            let distStr = dist > 1000 ? String(format: "%.1fkm", dist / 1000) : "\(Int(dist))m"
            return "📡 GPS FIX: dist=\(distStr), acc=±\(Int(acc))m"
        case "decision":
            let code = json["reason_code"] as? String ?? ""
            let icon: String
            switch code {
            case "EVENT_CONFIRMED": icon = "✅"
            case "OUTSIDE_PROXIMITY": icon = "📏"
            case "STATIONARY": icon = "🧍"
            case "NOT_APPROACHING": icon = "↗️"
            case "LOW_ACCURACY": icon = "⚠️"
            case "STALE_FIXES", "INSUFFICIENT_FIXES": icon = "⏳"
            default: icon = "ℹ️"
            }
            let details = json["reason_details"] as? String ?? ""
            return "\(icon) DECISION: \(code) (\(details))"
        case "event":
            let eventId = (json["event_id"] as? String ?? "").prefix(8)
            return "🎉 EVENT CONFIRMED! Stored event_id=\(eventId)..."
        case "notification":
            let outcome = json["outcome"] as? String ?? ""
            return outcome == "posted" ? "🔔 NOTIFICATION POSTED TO PHONE!" : "❌ Notification failed: \(outcome)"
        case "recovery":
            let situation = json["situation"] as? String ?? ""
            let result = json["result"] as? String ?? ""
            return "♻️ Recovery: \(situation) -> \(result)"
        case "battery":
            let level = json["battery_level"] as? Int ?? -1
            let note = json["note"] as? String ?? ""
            return "🔋 Battery record: \(level)% (\(note))"
        case "run_header":
            let model = json["device_model"] as? String ?? ""
            let scenario = json["scenario"] as? String ?? ""
            let arm = json["arm"] as? String ?? ""
            return "🏁 Run started on \(model) (\(scenario), \(arm))"
        case "note":
            let note = json["note"] as? String ?? ""
            return "ℹ️ \(note)"
        default:
            return nil
        }
    }

    func updateBatteryDisplay() {
        let (level, isCharging) = Logger.shared.getBatteryStatus()
        batteryText = "🔋 \(level)%\(isCharging ? " ⚡" : "")"
    }

    func checkPermissions() {
        let hasFine = PermissionHelper.hasFineLocation()
        let hasAlways = PermissionHelper.hasAlwaysLocation()
        let hasNotif = PermissionHelper.hasNotificationPermission()

        if !hasFine {
            permissionWarningTitle = "Location Permission Required"
            permissionWarningDesc = "Tap 'Fix Now' to grant location access needed for proximity testing."
        } else if !hasAlways {
            permissionWarningTitle = "Background Location Required"
            permissionWarningDesc = "Select 'Change to Always Allow' in Settings so iOS wakes the app when locked."
        } else if !hasNotif {
            permissionWarningTitle = "Notification Permission Required"
            permissionWarningDesc = "Tap 'Fix Now' to allow alerts when approach is confirmed."
        } else {
            permissionWarningTitle = nil
            permissionWarningDesc = nil
        }
    }

    func showToastNotification(_ message: String) {
        toastMessage = message
        withAnimation(.easeInOut(duration: 0.2)) {
            showToast = true
        }
        toastTimer?.invalidate()
        toastTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self?.showToast = false
                }
            }
        }
    }

    private func presentAlert(_ msg: String) {
        alertMessage = msg
        showAlert = true
    }
}
