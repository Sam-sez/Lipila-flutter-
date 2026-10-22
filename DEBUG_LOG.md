# Lipila BLE Debug Log

Track every investigation iteration here. Newest entry at the top.

Format:
```
## Iteration N — YYYY-MM-DD
Build: run<CI_run_number>
Hypothesis tested: H?
Change made: <one line>
Evidence: <paste log excerpt or "none yet">
Outcome: pending | confirmed | refuted
Next: <one action>
```

## Iteration 2 — 2026-10-22
Build: (not yet run — push to main triggers CI)
Change: Full pivot from BLE to NFC (asymmetric HCE). Removed flutter_blue_plus + flutter_ble_peripheral. Added nfc_manager + flutter_nfc_hce. New bong_nfc_service.dart. Rewritten bong_screen.dart (Pay / Receive role picker). Updated diagnostics screen, manifest patch, CI aapt2 checks.
Evidence: none yet — need first CI run + device test
Outcome: pending
Next: Push to main. Wait for green CI. Install debug APK on Pixel 3. Open Bong > bug icon > Run diagnostics > Check NFC perms > Test emulate > Copy all. Paste log.

---

## Iteration 1 — 2026-10-12
Build: (not yet run — push to main triggers CI)
Hypothesis tested: none yet (instrumentation only)
Change made: Added AppLog ring buffer, diagnostics screen, per-step BLE logging. CI now builds debug+release, stamps BUILD_ID, prints versions, verifies permissions with aapt2. No BLE logic changed.
Evidence: none yet — need first CI run + device logs
Outcome: pending
Next: Push to main. Wait for green CI build. Install BOTH APKs on Pixel 3. Open Bong > bug icon > Run diagnostics > Request BLE perms > Test advertise > Test scan > Copy all. Paste the log.
