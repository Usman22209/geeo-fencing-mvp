import Foundation
import UIKit
import Network

/// Thread-safe append-only JSONL Logger per specification section 7.
/// Guarded by a dedicated serial DispatchQueue to guarantee serialization order.
final class Logger {
    static let shared = Logger()

    private let fileQueue = DispatchQueue(label: "com.amigo.feasibility.logger", qos: .utility)
    private var seqCounter: Int64 = 1

    private(set) var currentRunId: String = "RUN-INIT"
    private var runStartElapsedMs: Int64 = 0
    private var runStartWallMs: Int64 = 0
    private var currentLogURL: URL?

    // Circular buffer of recent log lines for UI display
    private var recentLogLines: [String] = []
    private let maxRecentLogs = 100
    private let bufferLock = NSLock()

    // Callback for UI updates
    var onLogAppended: ((String) -> Void)?

    // App state tracking
    var currentAppState: String = "unknown" // "foreground", "background", "unknown"

    private let pathMonitor = NWPathMonitor()
    private var currentNetworkState: String = "unknown"

    private init() {
        runStartElapsedMs = Int64(ProcessInfo.processInfo.systemUptime * 1000.0)
        runStartWallMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        ensureLogsDirectory()
        startNetworkMonitoring()
    }

    @discardableResult
    private func ensureLogsDirectory() -> URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let logsDir = docs.appendingPathComponent("logs", isDirectory: true)
        if !FileManager.default.fileExists(atPath: logsDir.path) {
            try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        }
        return logsDir
    }

    private func startNetworkMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            if path.usesInterfaceType(.wifi) {
                self?.currentNetworkState = "wifi"
            } else if path.usesInterfaceType(.cellular) {
                self?.currentNetworkState = "cellular"
            } else if path.usesInterfaceType(.wiredEthernet) {
                self?.currentNetworkState = "ethernet"
            } else if path.status == .satisfied {
                self?.currentNetworkState = "connected_other"
            } else {
                self?.currentNetworkState = "disconnected"
            }
        }
        let queue = DispatchQueue(label: "com.amigo.feasibility.networkMonitor")
        pathMonitor.start(queue: queue)
    }

    // MARK: - Run Lifecycle

    func startNewRun(
        scenario: String = Config.shared.currentScenario,
        arm: String = Config.shared.activeArm.label,
        movementMode: String = Config.shared.movementMode
    ) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let timestamp = formatter.string(from: Date())

        currentRunId = "RUN_\(timestamp)_\(Config.shared.currentRunLabel)"
        runStartElapsedMs = Int64(ProcessInfo.processInfo.systemUptime * 1000.0)
        runStartWallMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        seqCounter = 1

        if let logsDir = ensureLogsDirectory() {
            let fileURL = logsDir.appendingPathComponent("amigo_\(currentRunId).jsonl")
            currentLogURL = fileURL
        }

        // Build run_header record
        let batteryInfo = getBatteryStatus()
        let isBatterySaver = ProcessInfo.processInfo.isLowPowerModeEnabled
        let appBuild = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"

        let configParams: [String: Any] = [
            "target_lat": Config.shared.targetLatitude,
            "target_lng": Config.shared.targetLongitude,
            "geofence_arm": Config.shared.activeArm.rawValue,
            "geofence_radius_m": Config.shared.activeArm.radiusMeters,
            "burst_duration_ms": Config.burstDurationMs,
            "location_interval_ms": Config.locationIntervalMs,
            "max_fix_age_ms": Config.maxFixAgeMs,
            "max_accuracy_m": Config.maxAccuracyM,
            "window_n": Config.windowN,
            "min_valid_fixes": Config.minValidFixes,
            "proximity_m": Config.proximityM,
            "stationary_m": Config.stationaryM,
            "min_decreasing_steps": Config.minDecreasingSteps,
            "cooldown_ms": Config.cooldownMs
        ]

        let permissionStates: [String: Bool] = [
            "fine_location": PermissionHelper.hasFineLocation(),
            "background_location": PermissionHelper.hasAlwaysLocation(),
            "post_notifications": PermissionHelper.hasNotificationPermission()
        ]

        let headerRecord = RunHeaderRecord(
            runId: currentRunId,
            tsWallMs: Int64(Date().timeIntervalSince1970 * 1000.0),
            tsElapsedMs: Int64(ProcessInfo.processInfo.systemUptime * 1000.0),
            appState: currentAppState,
            seq: nextSeq(),
            deviceModel: UIDevice.current.model,
            manufacturer: "Apple",
            osVersion: UIDevice.current.systemVersion,
            appBuild: appBuild,
            configParams: configParams,
            permissionStates: permissionStates,
            batteryLevel: batteryInfo.0,
            isBatterySaverOn: isBatterySaver,
            networkState: currentNetworkState,
            scenario: scenario,
            arm: arm,
            movementMode: movementMode
        )

        appendRecord(headerRecord)
    }

    private func nextSeq() -> Int64 {
        let s = seqCounter
        seqCounter += 1
        return s
    }

    // MARK: - Logging APIs

    func logWake(
        trigger: String,
        geofenceRequestId: String = "",
        isColdStart: Bool = false
    ) {
        let delaySinceStart = Int64(ProcessInfo.processInfo.systemUptime * 1000.0) - runStartElapsedMs
        let record = WakeRecord(
            runId: currentRunId,
            tsWallMs: Int64(Date().timeIntervalSince1970 * 1000.0),
            tsElapsedMs: Int64(ProcessInfo.processInfo.systemUptime * 1000.0),
            appState: currentAppState,
            seq: nextSeq(),
            trigger: trigger,
            geofenceRequestId: geofenceRequestId,
            isColdStart: isColdStart,
            delaySinceStartMs: delaySinceStart
        )
        appendRecord(record)
    }

    func logFix(fix: FixData) {
        let record = FixRecord(
            runId: currentRunId,
            tsWallMs: fix.receiptWallMs,
            tsElapsedMs: Int64(ProcessInfo.processInfo.systemUptime * 1000.0),
            appState: currentAppState,
            seq: nextSeq(),
            lat: fix.lat,
            lng: fix.lng,
            horizontalAccuracyM: fix.accuracyM,
            fixTimestampMs: fix.timestampMs,
            fixAgeAtReceiptMs: fix.ageMs,
            provider: fix.provider,
            distanceToTargetM: fix.distanceToTargetM
        )
        appendRecord(record)
    }

    func logDecision(result: DecisionResult) {
        let record = DecisionRecord(
            runId: currentRunId,
            tsWallMs: Int64(Date().timeIntervalSince1970 * 1000.0),
            tsElapsedMs: Int64(ProcessInfo.processInfo.systemUptime * 1000.0),
            appState: currentAppState,
            seq: nextSeq(),
            reasonCode: result.reasonCode.rawValue,
            reasonDetails: result.reasonDetails,
            windowCount: result.windowCount,
            validCount: result.validCount,
            distanceTrend: result.distanceTrend,
            netDisplacementM: result.netDisplacementM,
            latestDistanceM: result.latestDistanceM,
            inputsCount: result.inputsUsed.count
        )
        appendRecord(record)
    }

    func logEvent(eventId: String, eventTimeMs: Int64, distanceM: Double, evidenceSummary: String) {
        let record = EventRecord(
            runId: currentRunId,
            tsWallMs: Int64(Date().timeIntervalSince1970 * 1000.0),
            tsElapsedMs: Int64(ProcessInfo.processInfo.systemUptime * 1000.0),
            appState: currentAppState,
            seq: nextSeq(),
            eventId: eventId,
            eventTimeMs: eventTimeMs,
            distanceM: distanceM,
            evidenceSummary: evidenceSummary
        )
        appendRecord(record)
    }

    func logNotification(eventIdRef: String, attemptTimeMs: Int64, outcome: String, errorText: String? = nil) {
        let record = NotificationRecord(
            runId: currentRunId,
            tsWallMs: Int64(Date().timeIntervalSince1970 * 1000.0),
            tsElapsedMs: Int64(ProcessInfo.processInfo.systemUptime * 1000.0),
            appState: currentAppState,
            seq: nextSeq(),
            eventIdRef: eventIdRef,
            attemptTimeMs: attemptTimeMs,
            outcome: outcome,
            errorText: errorText
        )
        appendRecord(record)
    }

    func logRecovery(situation: String, reArmedComponent: String, result: String, details: String) {
        let record = RecoveryRecord(
            runId: currentRunId,
            tsWallMs: Int64(Date().timeIntervalSince1970 * 1000.0),
            tsElapsedMs: Int64(ProcessInfo.processInfo.systemUptime * 1000.0),
            appState: currentAppState,
            seq: nextSeq(),
            situation: situation,
            reArmedComponent: reArmedComponent,
            result: result,
            details: details
        )
        appendRecord(record)
    }

    func logPermissionChange(permission: String, oldState: Bool, newState: Bool) {
        let record = PermissionChangeRecord(
            runId: currentRunId,
            tsWallMs: Int64(Date().timeIntervalSince1970 * 1000.0),
            tsElapsedMs: Int64(ProcessInfo.processInfo.systemUptime * 1000.0),
            appState: currentAppState,
            seq: nextSeq(),
            permission: permission,
            oldState: oldState,
            newState: newState
        )
        appendRecord(record)
    }

    func logBattery(note: String? = nil) {
        let batteryInfo = getBatteryStatus()
        let duration = Int64(ProcessInfo.processInfo.systemUptime * 1000.0) - runStartElapsedMs
        let record = BatteryRecord(
            runId: currentRunId,
            tsWallMs: Int64(Date().timeIntervalSince1970 * 1000.0),
            tsElapsedMs: Int64(ProcessInfo.processInfo.systemUptime * 1000.0),
            appState: currentAppState,
            seq: nextSeq(),
            level: batteryInfo.0,
            isCharging: batteryInfo.1,
            runDurationMs: duration,
            note: note
        )
        appendRecord(record)
    }

    func logNote(_ noteText: String) {
        let record = NoteRecord(
            runId: currentRunId,
            tsWallMs: Int64(Date().timeIntervalSince1970 * 1000.0),
            tsElapsedMs: Int64(ProcessInfo.processInfo.systemUptime * 1000.0),
            appState: currentAppState,
            seq: nextSeq(),
            noteText: noteText
        )
        appendRecord(record)
    }

    // MARK: - File Writing & Buffering

    private func appendRecord(_ record: LogRecord) {
        let jsonLine = record.toJsonString()

        fileQueue.async { [weak self] in
            guard let self = self else { return }
            guard let fileURL = self.currentLogURL ?? self.defaultLogURL() else { return }

            if let data = (jsonLine + "\n").data(using: .utf8) {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    if let handle = try? FileHandle(forWritingTo: fileURL) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        try? handle.close()
                    }
                } else {
                    try? data.write(to: fileURL, options: .atomic)
                }
            }
        }

        // Add to recent lines for UI display
        let displayLine = "[\(record.recordType.uppercased())] seq=\(record.seq) \(record.appState): \(jsonLine)"
        bufferLock.lock()
        recentLogLines.append(displayLine)
        if recentLogLines.count > maxRecentLogs {
            recentLogLines.removeFirst()
        }
        bufferLock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.onLogAppended?(displayLine)
        }
    }

    private func defaultLogURL() -> URL? {
        guard let dir = ensureLogsDirectory() else { return nil }
        let url = dir.appendingPathComponent("amigo_\(currentRunId).jsonl")
        currentLogURL = url
        return url
    }

    func getRecentLogLines(count: Int = 50) -> [String] {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        return Array(recentLogLines.suffix(count))
    }

    func getCurrentLogFile() -> URL? {
        return currentLogURL
    }

    func getAllLogFiles() -> [URL] {
        guard let logsDir = ensureLogsDirectory(),
              let files = try? FileManager.default.contentsOfDirectory(at: logsDir, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles) else {
            return []
        }
        return files.filter { $0.pathExtension == "jsonl" }.sorted { url1, url2 in
            let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            return date1 > date2
        }
    }

    // MARK: - Device Info Helpers

    func getBatteryStatus() -> (Int, Bool) {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let rawLevel = UIDevice.current.batteryLevel
        let level = rawLevel >= 0 ? Int(rawLevel * 100.0) : -1
        let isCharging = (UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full)
        return (level, isCharging)
    }
}
