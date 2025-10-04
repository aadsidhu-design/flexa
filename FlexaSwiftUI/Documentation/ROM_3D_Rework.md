# ROM 3D Rework Plan (Phone-only ARKit)

Goal: Fix Test ROM overestimation (e.g., ~120° when expected ~0° for “phone near chest → extend outward”) and make ROM immune to tilt/orientation/phone angle while using ARKit world tracking only (no external body tracking).

## 1) Problems Observed
- Overestimation: Arc-length summation includes radial reach (elbow/wrist) → inflates ROM.
- Baseline drift: No robust baseline; path noise and wobble accumulate.
- UI coupling: Live ROM pauses/doesn’t refresh when “Count Rep” is toggled.
- Service stop: ARKit/IMU/Vision sometimes continue after session end.
- Navigation: Results → Survey → Done/Continue sometimes returns into game.

## 2) Design Objectives
- Orientation-independent: use 3D positions (ignore attitude).
- Motion-centric ROM: measure angular change of motion direction, not path length.
- Robust to radial-only moves (e.g., extend outward): should remain ~0°.
- Phone-only ARKit world tracking (no skeleton), low-latency, stable.

## 3) New ROM Algorithm (Replace Arc-Length)
- Plane fit (PCA):
  - Use last N positions (e.g., 40–80) → covariance → smallest-eigenvector = plane normal n.
  - Project all positions to plane: p_proj = p - n * dot(p - p0, n) (p0 = first stable position).
- Baseline origin and direction:
  - Origin O = first stable position in session (after 0.5s stabilization).
  - Direction d0 = normalize(mean of small forward displacements from O over first K frames).
- Directional ROM (not distance-based):
  - For each frame t: vt = P_t_proj - O; if |vt| < ε, angle = last.
  - v̂t = normalize(vt). θ(t) = arccos(clamp(dot(v̂t, d0), -1, 1)) [degrees].
  - EMA smoothing on v̂t or θ(t), cap dθ/dt (e.g., ≤120°/s).
- Radial gating:
  - Δr = |vt| - |v(t-1)|; Δθ = |θ(t) - θ(t-1)|.
  - Ignore updates when Δθ < θ_min (e.g., 1–2°) even if Δr >> 0 (pure reach).
- Baseline resilience:
  - Stationary detection (speed < v_min & jerk < j_min for ≥1s) → allow one-time baseline refresh (O ← latest, d0 ← direction snapshot).
  - Otherwise, keep d0 fixed across a session to prevent drift.
- Output:
  - currentROM = θ_smooth(t); maxROM = max(maxROM, currentROM).
  - IMU-only fallback (ARKit unavailable): still run plane + directional angle on pseudo-positions; keep same gating.

Why this fixes the scenario:
- “Phone near chest → extend outward” is radial along the same direction (v̂t ≈ d0) → θ ≈ 0°, despite large path length. True abduction requires a change in direction, not mere reach.

## 4) Service Stop Unification (Reliability)
- Replace all `SimpleMotionService.stop()` usages with `stopSession()`.
- Add `StopAllMotionServices` notification:
  - Post on game ended, results onDone/onRetry, and aborts.
  - Observers: `SimpleMotionService.stopSession()`, `CoreMotionSensorService.stopSensorUpdates()`.
- Ensure `poseProvider.stop()` halts camera; `Universal3DROMEngine.stop()` pauses ARSession; stop deviceMotion and SPARC.
- Add logs confirming shutdown states.

## 5) Navigation Flow (Return to Home)
- Single coordinator:
  - Drive Analyzing/Results/Survey via `NavigationCoordinator` only (no local fullScreenCovers for these).
  - On Survey Continue/Done: `goHome()` → post `DismissAllModals` → post `NavigateToTab` { tabIndex: 0 }.
- Always post `StopAllMotionServices` before navigation changes.

## 6) Test ROM UX Improvements
- Baseline button (optional): “Set Baseline” to capture O and d0 explicitly.
- Live ROM independence: ROM updates must be independent of the “Count Rep” toggle (that toggle only enables rep detection).
- Diagnostics switch: overlay shows plane normal, |vt|, θ(t), Δr, Δθ, and gating state for QA.

## 7) Validation Matrix (On Device)
- Static: arm by side ~0°; shoulder level ~90°; slightly above ~120°.
- Radial-only moves (reach out) → ≈0°.
- Tilt-only (rotate phone in place) → ≈0°.
- Repeated abduction cycles → stable max ROM, no growth from wobble.
- End-of-session: all sensors/camera/ARKit stop, no further logs.
- Results→Survey→Done/Continue: instant Home tab, no residual modals.

## 8) Implementation Steps (PR sequence)
- PR1: StopAllMotionServices + migrate `.stop()` → `.stopSession()`; add shutdown logs.
- PR2: Navigation unification (Results/Survey via coordinator) + DismissAllModals; ensure Home tab switch.
- PR3: ROM algorithm switch to Plane+Directional Angle + radial gating; keep arc-length/chord fallback behind flag for A/B.
- PR4: Test ROM UX (Baseline button; decouple Count Rep; diagnostics overlay toggle).
- PR5: QA passes; tune thresholds (θ_min, rates, smoothing).
