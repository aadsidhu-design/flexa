# Summary Context: ARKit + IMU Shoulder ROM Calibration and Robustness

Date: 2025-09-05
Owner: SimpleMotionService / ARKitROMTracker / IMU3DROMTracker / ShoulderROMEstimator

## What changed

- Auto-anchoring and persistence (ARKit)
  - Auto-anchors 0° and 90° after relocalization when the device is steady near those poses.
  - Infers and persists shoulder radius from 0→90 chord; reused on relaunch and after relocalization.
  - Files: `Services/ARKitROMTracker.swift` (auto-anchors, radius save/load, deltaYaw/Δpos to estimator)

- Elbow compensation v2 + Freeze gating
  - Estimator now uses:
    - S-ratio (displacement vs rotation) when available.
    - Yaw dominance (forearm/wrist twist) and low translation per-frame.
    - Freeze gating: if yaw-dominant with ~0 translation, hold last-good ROM for 0.5s.
    - Grip offset gain to strengthen compensation when phone grip is farther from elbow.
  - Files: `Services/ShoulderROMEstimator.swift`

- IMU parity and updates
  - IMU path also calculates `deltaYawDeg`, `deltaPosMeters`, and does best-effort auto-anchoring for 0°/90° (not persisted).
  - IMU now publishes live ROM updates via `onAngleUpdate` so UI reflects IMU mode immediately.
  - Files: `Services/IMU3DROMTracker.swift`

- Service wiring and mode switching
  - `SimpleMotionService.setROMTrackingMode(_:)` now correctly starts/stops ARKit, Vision camera, and IMU trackers.
  - `startSession(gameType:)` re-applies the current ROM mode instead of forcing camera.
  - Added `setGripOffsetMeters(_:)`, forward to both trackers.
  - Files: `Services/SimpleMotionService.swift`

- Calibration Wizard improvements
  - After auto 0/90/180 capture completes, UI now includes Arm length, Forearm length, and Grip offset inputs; saved back to service/trackers.
  - Buttons made easier to tap.
  - Files: `Views/CalibrationWizardView.swift`

- Micro‑gesture Grip Offset Auto‑Estimator
  - New micro‑gesture step appears after 0° capture: user keeps arm down and gently wiggles wrist for ~3s; estimator infers grip offset (0.02–0.06m typical) from yaw‑dominant vs elevation micro‑motions.
  - Value is applied immediately via `SimpleMotionService.setGripOffsetMeters(_)` and persisted via trackers.
  - Files: `Views/CalibrationWizardView.swift` (UI + `MicroGripEstimator`), `Services/ShoulderROMEstimator.swift` (offset use).

- Optional AR Body Tracking Provider (rear camera)
  - When `.arkit` mode is active and body tracking is supported, switches to `ARBodyTrackingConfiguration` and computes shoulder abduction directly from `ARBodyAnchor` joints.
  - Falls back to ARKit world tracking provider when not supported.
  - Files: `Services/ARBodyTrackingProvider.swift` (new), `Services/SimpleMotionService.swift` (integration, start/stop, onAngleUpdate).

- Tap‑Target Utility and Initial Audit
  - Added `tapTarget(_:)` ViewModifier to standardize minimum 44–60pt hit areas; applied to key Wizard buttons (Start/Skip/Save/Done/Cancel).
  - Files: `Views/Components/TapTarget.swift`, `Views/CalibrationWizardView.swift`.

- Test ROM UI safety
  - Manual calibration buttons moved under collapsed “Manual Calibration (Advanced)”.
  - Larger tap targets; Done button also expanded.
  - Files: `Games/TestROMGameView.swift`

## How it behaves now

- Calibrate once via Wizard; values persist (IMU & ARKit). In new places, AR auto-anchors 0°/90° on steady poses and reuses inferred radius.
- During elbow/wrist-only motion (yaw-dominant, low translation), estimator compensates and can freeze short-term to avoid false ROM changes.
- Test ROM mode toggle to IMU/ARKit correctly switches pipelines. IMU publishes angle updates through service.
- In ARKit mode on supported devices, rear camera body tracking is used; otherwise ARKit world tracking is used.
- Wizard auto-estimates grip offset after 0° stage to improve elbow compensation.

## Key APIs & knobs

- Service
  - `SimpleMotionService.setROMTrackingMode(_:)`
  - `setArmLengthMeters(_:)`, `setForearmLengthMeters(_:)`, `setGripOffsetMeters(_:)`

- Estimator
  - `ShoulderROMEstimator.freezeHoldSeconds` (default 0.5)
  - `ShoulderROMEstimator.setGripOffsetMeters(_:)` (0–0.2 m)

- ARKit
  - Persists: `arkit_inferred_radius`
  - Auto-anchors when steady near 0°/90°

## Telemetry to watch

- ARKit: `🧠 [ARKitROM] θ=.. wO=.. wA=.. S=.. anchors=..`
- Auto-anchors: `🔧 [ARKitROM] Auto-anchored 0°/90° ...`
- Radius: `💾 [ARKitROM] Saved/Loaded inferred radius ...`
- IMU-only: `🧠 [IMU3D] ...` and `🔧 [IMU3D] Auto-anchored ...`

## Next steps

- Expand tap-target audit app-wide (apply `tapTarget(_:)` to primary buttons and critical controls across views).
- Refine micro‑gesture mapping function with more robust feature extraction and per‑user learning.
- Add a setting to prefer AR Body vs AR World fallback, and in‑UI indicator of active AR provider.
