# AMIGO Android Feasibility Test: Run Sheet & Test Matrix

This run sheet accompanies the AMIGO Android Feasibility test harness logs. Every field test run must be logged with a unique `run_id` matching the exported JSONL log filename (`amigo_<run_id>.jsonl`).

---

## 1. Fixed Configuration Baseline

- **App Build:** `1.0.0-feasibility` (`com.amigo.feasibility.debug`)
- **Compile / Target SDK:** 35 (Android 15) | **Min SDK:** 26 (Android 8.0)
- **Target Coordinates:** Set in `Config.kt` (`targetLatitude`, `targetLongitude`)
- **Proximity Threshold ($proximityM$):** `40.0 m`
- **Stationary Threshold ($stationaryM$):** `5.0 m`
- **Burst Window Duration:** `30,000 ms` | **Fix Rate:** `1,000 ms` (1 Hz)

---

## 2. Test Matrix Execution Log

| Run ID | Scenario | Arm | Device Model & OEM | Android Version | Battery Setting | Movement Mode | OS Wake? (`wake`) | Engine Decision (`decision`) | Notification Posted? | Manually Seen? (`note`) | Pass / Fail / Blocked |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `RUN_001` | Positive | 50m | Pixel 8 (Google) | Android 15 | Default | Walking | [ ] Yes [ ] No | `EVENT_CONFIRMED` | [ ] Yes [ ] No | [ ] Yes [ ] No | |
| `RUN_002` | Positive | 150m | Pixel 8 (Google) | Android 15 | Default | Walking | [ ] Yes [ ] No | `EVENT_CONFIRMED` | [ ] Yes [ ] No | [ ] Yes [ ] No | |
| `RUN_003` | Positive | 50m | Pixel 8 (Google) | Android 15 | Default | Vehicle | [ ] Yes [ ] No | `EVENT_CONFIRMED` | [ ] Yes [ ] No | [ ] Yes [ ] No | |
| `RUN_004` | Positive | 150m | Pixel 8 (Google) | Android 15 | Default | Vehicle | [ ] Yes [ ] No | `EVENT_CONFIRMED` | [ ] Yes [ ] No | [ ] Yes [ ] No | |
| `RUN_005` | Negative A (Stationary) | 50m | Pixel 8 (Google) | Android 15 | Default | Stationary | [ ] Yes [ ] No | `STATIONARY` | [ ] Suppressed | [ ] None | |
| `RUN_006` | Negative B (Stop Outside) | 50m | Pixel 8 (Google) | Android 15 | Default | Walking | [ ] Yes [ ] No | `OUTSIDE_PROXIMITY` | [ ] Suppressed | [ ] None | |
| `RUN_007` | Negative C (Poor GPS/Stale) | 50m | Pixel 8 (Google) | Android 15 | Default | Walking | [ ] Yes [ ] No | `STALE_FIXES` | [ ] Suppressed | [ ] None | |
| `RUN_008` | Background Baseline | 50m | Pixel 8 (Google) | Android 15 | Default | Walking | [ ] Yes [ ] No | `EVENT_CONFIRMED` | [ ] Yes [ ] No | [ ] Yes [ ] No | |
| `RUN_009` | Ordinary Close (Swipe Recents)| 50m | Pixel 8 (Google) | Android 15 | Default | Walking | [ ] Yes [ ] No | `EVENT_CONFIRMED` | [ ] Yes [ ] No | [ ] Yes [ ] No | |
| `RUN_010` | OS Process Kill (`am kill`)| 50m | Pixel 8 (Google) | Android 15 | Default | Walking | [ ] Yes [ ] No | `EVENT_CONFIRMED` | [ ] Yes [ ] No | [ ] Yes [ ] No | |
| `RUN_011` | Force-Stop (`am force-stop`)| 50m | Pixel 8 (Google) | Android 15 | Default | Walking | [ ] Expected No | Expected None | Expected None | Expected None | |
| `RUN_012` | Device Reboot (`BOOT_COMPLETED`)| 50m | Pixel 8 (Google) | Android 15 | Default | Walking | [ ] Yes (`boot`) | `EVENT_CONFIRMED` (Post-reboot) | [ ] Yes [ ] No | [ ] Yes [ ] No | |
| `RUN_013` | Airplane Mode Restore | 50m | Pixel 8 (Google) | Android 15 | Default | Walking | [ ] Yes [ ] No | `EVENT_CONFIRMED` (On fresh fix) | [ ] Yes [ ] No | [ ] Yes [ ] No | |
| `RUN_014` | Permission Revoke / Restore | 50m | Pixel 8 (Google) | Android 15 | Default | Walking | [ ] Yes [ ] No | `EVENT_CONFIRMED` (Post-grant) | [ ] Yes [ ] No | [ ] Yes [ ] No | |
| `RUN_015` | Doze Mode (`force-idle`) | 50m | Pixel 8 (Google) | Android 15 | Default | Walking | [ ] Yes [ ] No | `EVENT_CONFIRMED` | [ ] Yes [ ] No | [ ] Yes [ ] No | |
| `RUN_016` | Positive (OEM Phone) | 50m | Galaxy S24 (Samsung) | Android 14 (OneUI) | Default | Walking | [ ] Yes [ ] No | `EVENT_CONFIRMED` | [ ] Yes [ ] No | [ ] Yes [ ] No | |
| `RUN_017` | Positive (OEM Phone) | 50m | Galaxy S24 (Samsung) | Android 14 (OneUI) | Unrestricted | Walking | [ ] Yes [ ] No | `EVENT_CONFIRMED` | [ ] Yes [ ] No | [ ] Yes [ ] No | |
| `RUN_018` | Ordinary Close (OEM Phone) | 50m | Galaxy S24 (Samsung) | Android 14 (OneUI) | Default | Walking | [ ] Yes [ ] No | `EVENT_CONFIRMED` | [ ] Yes [ ] No | [ ] Yes [ ] No | |

---

## 3. Execution Checklist for Each Run

1. **Verify State:** Confirm device network, battery level, battery-saving mode, and permission status.
2. **Set Scenario & Arm:** In the AMIGO app UI, select the scenario, arm (50m or 150m), movement mode, and run label.
3. **Start Monitoring:** Tap **START MONITORING (ARM GEOFENCE)**. Verify `run_header` is logged in the JSONL feed.
4. **Induce State:** Background the app, swipe from recents, execute `am kill`, or initiate transit.
5. **Observe Behavior:**
   - Check if geofence wakes the app (`wake` record).
   - Check if `BurstService` starts and collects 1s fixes (`fix` records).
   - Check engine evaluation (`decision` record).
   - Check whether notification is posted (`notification` record).
6. **Log Manual Note:** Use the in-app "Manual Observation Note" field to record physical observations (e.g., *"notification banner observed on lock screen at 17:42"*).
7. **Export Log:** Tap **Export Logs** or pull via `adb exec-out run-as com.amigo.feasibility.debug cat ... > amigo_<run_id>.jsonl`.

