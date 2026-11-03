import Foundation

/// Thread-safe Event Store per specification section 4.
/// Writes an event record (with UUID) ONLY when the decision is positive.
/// Strictly enforces one event per arming, with cooldown.
/// NEVER creates an event on recovery.
final class EventStore {
    static let shared = EventStore()

    private let lock = NSLock()
    private var hasFiredForCurrentArming: Bool = false
    private var lastEventTimeMs: Int64 = 0

    private init() {}

    /// Resets arming state for a fresh test cycle.
    func onArmed() {
        lock.lock()
        defer { lock.unlock() }
        hasFiredForCurrentArming = false
    }

    /// Called when device physically exits the geofence boundary.
    /// Re-arms the store so that the next entrance can trigger a fresh burst and notification.
    func onExited() {
        lock.lock()
        defer { lock.unlock() }
        hasFiredForCurrentArming = false
        lastEventTimeMs = 0
    }

    /// Disarms the store.
    func onDisarmed() {
        lock.lock()
        defer { lock.unlock() }
        hasFiredForCurrentArming = true
    }

    /// Evaluates whether to persist an event based on DecisionResult.
    /// Enforces:
    /// 1. Must be EVENT_CONFIRMED
    /// 2. Exactly one event per arming
    /// 3. Must respect cooldown period
    ///
    /// Returns eventId if created, nil otherwise.
    func recordEventIfConfirmed(result: DecisionResult) -> String? {
        lock.lock()
        defer { lock.unlock() }

        guard result.isConfirmed && result.reasonCode == .eventConfirmed else {
            return nil
        }

        if hasFiredForCurrentArming {
            Logger.shared.logNote("Event suppressed: event already fired for this arming.")
            return nil
        }

        let now = Int64(Date().timeIntervalSince1970 * 1000.0)
        let timeSinceLast = now - lastEventTimeMs
        if lastEventTimeMs > 0 && timeSinceLast < Config.cooldownMs {
            Logger.shared.logNote("Event suppressed: cooldown active (\(timeSinceLast) ms < \(Config.cooldownMs) ms).")
            return nil
        }

        let eventId = UUID().uuidString
        hasFiredForCurrentArming = true
        lastEventTimeMs = now

        let distance = result.latestDistanceM ?? 0.0
        let evidenceSummary = result.reasonDetails

        Logger.shared.logEvent(
            eventId: eventId,
            eventTimeMs: now,
            distanceM: distance,
            evidenceSummary: evidenceSummary
        )

        return eventId
    }

    func isArmed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !hasFiredForCurrentArming
    }
}
