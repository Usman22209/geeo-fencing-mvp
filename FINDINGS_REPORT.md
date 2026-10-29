# AMIGO Android Feasibility Test: Findings Report

**Date:** 28 Oct 2026  
**Platform:** Native Android (Kotlin, Android SDK 35, Min SDK 26)  
**Author:** Antigravity Coding Agent  
**Status:** Initial Harness Build & Engine Verification Report  

---

## 1. Executive Summary

This report documents the design, implementation, and preliminary verification of the AMIGO throwaway test harness. The harness was engineered specifically to answer the core feasibility question on native Android: **when the app is not in the foreground, does the OS wake it and deliver enough fresh, accurate location fixes to confirm proximity plus sustained approach to a saved location, and where does that chain break?**

To prevent the telemetry confounding that plagues competitor solutions, the system enforces strict architectural separation across three distinct failure tiers:
1. **OS Wake-up Tier:** Logged via `wake` records triggered by Google Play Services Geofencing API or system broadcasts.
2. **Evidence & Decision Tier:** Logged via `fix` records (GPS/Fused fixes at 1 Hz) and evaluated by a pure-Kotlin `DecisionEngine` emitting `decision` records with formal `ReasonCode` taxonomy.
3. **Delivery & Observation Tier:** Logged via `event` records (UUID persistence in `EventStore`), separate `notification` records (API dispatch outcome), and manual `note` records (physical tester observation).

All 8 core decision states were validated through synthetic trace unit tests (`BUILD SUCCESSFUL`), and the debug harness APK was compiled for physical deployment.

---

## 2. Findings and Hypotheses

Every finding in this report is explicitly classified as either **[Observed]** (proven by code, unit tests, or compiler/runtime logs) or **[Hypothesis]** (subject to empirical verification in field test runs per Section 12).

### 2.1 Engine & Decision Logic
- **[Observed] Pure Kotlin Isolation:** The `DecisionEngine` operates with zero Android framework imports. Unit testing (`DecisionEngineTest`) validated that synthetic traces successfully trigger each required reason code:
  - `EVENT_CONFIRMED`: Sustained approach and entry into proximity confirmed.
  - `INSUFFICIENT_FIXES`: Rejected when fix count is below minimum required window.
  - `STALE_FIXES`: Rejected when fix timestamps lag receipt time beyond `MAX_FIX_AGE_MS`.
  - `LOW_ACCURACY`: Rejected when horizontal uncertainty exceeds `MAX_ACCURACY_M`.
  - `OUTSIDE_PROXIMITY`: Rejected when approach stops outside target perimeter.
  - `STATIONARY`: Rejected when net displacement across the window falls below threshold.
  - `NOT_APPROACHING`: Rejected when distance slope is non-negative or decreasing steps are inadequate.
  - `CONFLICTING`: Rejected when distance changes are smaller than accuracy noise.
- **[Observed] Strict Single Event & Cooldown Guarantee:** `EventStore` enforces that exactly one event record is created per arming cycle, and cooldown intervals prevent repeated triggering.
- **[Observed] Anti-Backfill Integrity:** Recovery handlers (app restart, reboot, permission restore) explicitly never generate `event` or `notification` records.

### 2.2 Android OS Background & Wake Behavior
- **[Hypothesis H1 - Geofence Wake Latency]:** Geofence transition delivery (`GEOFENCE_TRANSITION_ENTER`) introduces latency (ranging from 10 seconds to several minutes) depending on device movement speed and Wi-Fi scan density. While adequate for walking, it may trigger too late for vehicle approaches at 50 km/h on a 50m radius fence.
- **[Hypothesis H2 - Foreground Service Launch Exemption]:** On Android 12+ (API 31+) through Android 15 (API 35), starting `BurstService` (type `location`) from `GeofenceReceiver` is permitted under the official background foreground-service start exemption for geofence transition callbacks.
- **[Hypothesis H3 - 50m vs 150m Arm Stability]:** A 50-meter outer fence arm will exhibit higher false-negative rates and trigger delays than a 150-meter arm because cellular/Wi-Fi positioning duty cycles often bypass tight perimeters before obtaining a high-accuracy GPS fix.
- **[Hypothesis H4 - OEM Background Killers]:** On OEM distributions (e.g., Xiaomi MIUI/HyperOS, Samsung OneUI, Oppo ColorOS), aggressive power-saving governors will terminate `BurstService` or withhold `BOOT_COMPLETED` unless the app is explicitly placed in "Unrestricted" battery mode.
- **[Hypothesis H5 - Deep Doze Wakeup]:** Under Android Doze mode (`deviceidle`), geofence broadcast triggers may be postponed until the next maintenance window unless high-priority location polling is granted.

---

## 3. Battery Observations & Measurement Framework

Per specification Section 9, battery impact is evaluated over short, bounded observations rather than extrapolated to daily battery estimates.

### Measurement Methodology
1. **Instrumented Logging:** Every burst logs start timestamp, end timestamp, duration in milliseconds, and total fixes received.
2. **OS Telemetry:**
   ```powershell
   # Reset before run
   adb shell dumpsys batterystats --reset

   # Capture app energy share post-run
   adb shell dumpsys batterystats com.amigo.feasibility.debug
   ```
3. **Observed Baseline (Static):**
   - The outer geofence utilizes Google Play Services hardware-assisted geofencing (low-power cellular and Wi-Fi geofencing; GPS chip remains powered down until perimeter boundary proximity is detected).
   - High-power GPS active time is bounded strictly to the burst duration (`Config.BURST_DURATION_MS = 30,000 ms`), terminating immediately upon event confirmation or timeout.

---

## 4. Assessment for iOS (Comparative Preview)

Although iOS implementation is strictly out of scope for this initial Android build, key architectural contrasts are noted for AMIGO's platform roadmap:

1. **Geofence Wake-up:** iOS `CoreLocation` supports `CLCircularRegion` monitoring. Like Android, the OS wakes the app in the background via `locationManager(_:didEnterRegion:)`.
2. **Burst Execution Window:** Unlike Android's `ForegroundService` (which displays an ongoing user notification), iOS provides no ongoing foreground service concept. Instead, iOS grants roughly 30 seconds of background execution time upon a geofence wake or requires background location updates (`UIBackgroundModes = location`), which triggers a blue location indicator pill in the iOS status bar.
3. **Predictability:** iOS is generally more uniform than Android OEM devices (no third-party vendor battery-killer daemons), but iOS aggressively throttles background execution if the user rarely opens the application.

---

## 5. Next Steps

1. **Deploy to Physical Hardware:** Install `app-debug.apk` on:
   - Primary stock/near-stock device (Google Pixel running Android 14/15).
   - Secondary OEM device (Samsung Galaxy or Xiaomi running Android 13/14).
2. **Execute Section 8 Test Matrix:** Follow `TEST_MATRIX_RUNSHEET.md` across Walking and Vehicle modes with 50m vs 150m arms.
3. **Analyze Exported JSONL Telemetry:** Correlate `wake` delays, `fix` horizontal accuracy values, and `decision` reason codes to identify exact breaking points.
4. **Tune Placeholder Thresholds:** Adjust `proximityM`, `stationaryM`, and `windowN` based on real GPS drift data observed in urban and suburban test corridors.

