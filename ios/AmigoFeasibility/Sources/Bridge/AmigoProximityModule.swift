//
//  AmigoProximityModule.swift
//  AmigoFeasibility
//
//  React Native Swift Bridge for AMIGO Proximity Engine
//

import Foundation
import React

@objc(AmigoProximity)
final class AmigoProximityModule: RCTEventEmitter {

    private var hasListeners = false

    override init() {
        super.init()
        // Wire Logger observer to emit events to React Native JavaScript layer
        Logger.shared.onLogAppended = { [weak self] rawLine in
            guard let self = self, self.hasListeners else { return }
            self.sendEvent(withName: "onLogAppended", body: ["raw": rawLine])
        }
    }

    override static func requiresMainQueueSetup() -> Bool {
        return true
    }

    override func supportedEvents() -> [String]! {
        return ["onLogAppended", "onStateChanged"]
    }

    override func startObserving() {
        hasListeners = true
    }

    override func stopObserving() {
        hasListeners = false
    }

    @objc(initConfig:rejecter:)
    func initConfig(
        _ resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        let targetLat = Config.shared.targetLatitude
        let targetLng = Config.shared.targetLongitude
        let activeArm = Config.shared.activeArm.rawValue
        let isArmed = Config.shared.isMonitoringArmed

        resolve([
            "targetLat": targetLat,
            "targetLng": targetLng,
            "activeArm": activeArm,
            "isArmed": isArmed
        ])
    }

    @objc(setTarget:lng:resolver:rejecter:)
    func setTarget(
        _ lat: Double,
        lng: Double,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        Config.shared.targetLatitude = lat
        Config.shared.targetLongitude = lng
        Logger.shared.logNote("Target updated from React Native: (\(lat), \(lng))")
        resolve(true)
    }

    @objc(setArmRadius:resolver:rejecter:)
    func setArmRadius(
        _ armName: String,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        if armName == "ARM_150M" {
            Config.shared.activeArm = .arm150m
        } else {
            Config.shared.activeArm = .arm50m
        }
        Logger.shared.logNote("Geofence arm updated from React Native: \(Config.shared.activeArm.label)")
        resolve(Double(Config.shared.activeArm.radiusMeters))
    }

    @objc(startMonitoring:rejecter:)
    func startMonitoring(
        _ resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        Logger.shared.startNewRun(
            scenario: Config.shared.currentScenario,
            arm: Config.shared.activeArm.label,
            movementMode: Config.shared.movementMode
        )
        EventStore.shared.onArmed()

        RegionManager.shared.registerGeofence(
            onSuccess: { [weak self] in
                Config.shared.isMonitoringArmed = true
                if let self = self, self.hasListeners {
                    self.sendEvent(withName: "onStateChanged", body: ["state": "ARMED"])
                }
                resolve(true)
            },
            onFailure: { error in
                reject("GEOFENCE_REGISTRATION_FAILED", error.localizedDescription, error)
            }
        )
    }

    @objc(stopMonitoring:rejecter:)
    func stopMonitoring(
        _ resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        RegionManager.shared.removeGeofences { [weak self] in
            EventStore.shared.onDisarmed()
            Config.shared.isMonitoringArmed = false
            if let self = self, self.hasListeners {
                self.sendEvent(withName: "onStateChanged", body: ["state": "IDLE"])
            }
            resolve(true)
        }
    }

    @objc(triggerManualBurst:rejecter:)
    func triggerManualBurst(
        _ resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        BurstManager.shared.startBurst(trigger: "rn_manual_test")
        Logger.shared.logWake(trigger: "rn_manual_test", geofenceRequestId: "manual", isColdStart: false)
        resolve(true)
    }

    @objc(checkPermissions:rejecter:)
    func checkPermissions(
        _ resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        let fineLocation = PermissionHelper.hasFineLocation()
        let backgroundLocation = PermissionHelper.hasAlwaysLocation()
        let postNotifications = PermissionHelper.hasNotificationPermission()
        let batteryExempt = !ProcessInfo.processInfo.isLowPowerModeEnabled

        resolve([
            "fineLocation": fineLocation,
            "backgroundLocation": backgroundLocation,
            "postNotifications": postNotifications,
            "batteryExempt": batteryExempt
        ])
    }

    @objc(computeDistance:lon1:lat2:lon2:resolver:rejecter:)
    func computeDistance(
        _ lat1: Double,
        lon1: Double,
        lat2: Double,
        lon2: Double,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        let distance = DecisionEngine.computeDistanceM(lat1: lat1, lon1: lon1, lat2: lat2, lon2: lon2)
        resolve(distance)
    }
}
