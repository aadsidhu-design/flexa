# ARKit + IMU Shoulder ROM Plan (Forearm-Compensated, No Vision Landmarks at Runtime)

## 1) Goal
Accurately estimate glenohumeral (armpit) abduction angle from a phone held in hand while compensating for forearm/elbow motion. Primary path uses ARKit; fallback path uses IMU-only. No Apple Vision body landmarks at runtime.

## 2) Principles & Constraints
- Single active camera pipeline (ARSession or none). No AVCaptureSession when ARKit is active.
- Persist 0°/90°/180° orientation calibration across app launches and rooms (already implemented).
- Prefer ARKit Body Tracking when supported (rear camera) for ground-truth joints; otherwise ARKit World Tracking + IMU heuristics; final fallback IMU-only.
- No user taps during calibration: automatic wizard captures 0/90/180.

## 3) Calibration (Automatic)
- Orientation map: capture device pitch/roll at 0°, 90°, 180° → persist (UserDefaults). Used by both ARKit and IMU paths.
- Segment lengths: store upper-arm and forearm estimates.
  - Default from height: upperArm ≈ 0.186·H, forearm ≈ 0.146·H (literature averages).
  - Allow override if known or measured later; persist.
- Grip offset: learn a fixed device↔forearm rotation bias (phone not perfectly aligned with forearm). Estimate from small wrist flex/extend micro-motions during “Down” stage; persist.
- AR positional anchors: when ARKit relocalizes, drop anchors (not orientation map). Reacquire quietly.

## 4) Kinematics Model
Let S be shoulder, E elbow, W phone position. Phone is rigid with forearm. True shoulder abduction θ should reflect upper arm rotation relative to torso, not elbow flexion.

- Orientation estimator E_orient:
  - Map device pitch/roll via the persisted 0/90/180 calibration curve to degrees. Clamp [0,180]. Ignores yaw.
- Arc-length estimator E_arc:
  - From ARKit world translation: d = |W − W0|. If valid anchors and radius R_sh (S→W with elbow extended), θ_arc = 2·asin(min(d/(2R_sh),1)). If R_sh unknown, infer from 0→90 chord.
- Elbow-compensation estimator E_comp:
  - Detect elbow-dominant motion and subtract expected device rotation due to elbow.
  - Use forearm length R_fa and grip offset to estimate phone rotation around elbow axis when translation is low vs rotation high.

Detection features (per frame or short window):
- Δpos = |W − W_prev| (m), Δang = |Δpitchroll| (rad), ratio S = Δpos / (R_eff·Δang). If S < 0.5 → elbow-dominant; if S > 1.5 → shoulder/torso-dominant.
- Gyro axis analysis: project angular velocity onto world axes; elbow flexion often rotates about a local axis aligned with forearm; shoulder abduction rotates about near-anterior–posterior axis. Use simple axis heuristics to classify.

Fusion (per frame):
- Compute weights w_orient, w_arc from classification:
  - If anchors valid and S≈1, w_arc↑ (0.7), w_orient↓ (0.3).
  - If S≪1 (elbow), w_orient↓ aggressively (0.2), w_arc 0.8.
  - If anchors invalid, use w_orient=1.0 with elbow compensation.
- Estimate elbow angle surrogate φ_elbow from Δang and low Δpos, scaled by R_fa; subtract: θ = w_orient·(E_orient − k·φ_elbow) + w_arc·E_arc.
- EMA smoothing and hard clamp [0,180].

## 5) ARKit Body Tracking (Preferred When Available)
- Use `ARBodyAnchor` joints: get S (left/right shoulder), E (elbow), H (hip/torso). Compute upper-arm vector u = normalize(E−S), torso up t = normalize(midShoulders−midHips). Shoulder abduction = angle(u, t) projected to coronal plane.
- When active, treat as truth and learn online the mapping parameter k and grip offset for the elbow-compensation model (used when Body Tracking temporarily drops or in non-supported devices).

## 6) IMU-only Fallback
- Orientation map from calibration drives θ_orient.
- Integrate world-frame displacement (with ZUPT and bias removal) to get coarse Δpos for S ratio gating.
- Use forearm-compensation when S indicates elbow-dominant movement.

## 7) API & Components
- ShoulderROMEstimator
  - Input: device orientation (pitch/roll/yaw), angular velocity, world position (optional), anchor validity, segment lengths, grip offset, calib map.
  - Output: θ (deg), confidence, flags (elbow-dominant, anchorsValid).
- ElbowCompensator
  - Input: Δpos, Δang, R_fa, grip offset → φ_elbow estimate.
- MovementClassifier
  - Computes S ratio and axis features → class: shoulder, elbow, mixed.
- CalibrationService
  - Runs the 0/90/180 wizard (already added). Adds micro-gesture step to estimate grip offset. Persists segment lengths.
- Integration
  - `SimpleMotionService` owns estimator; ARKit path passes ARCamera transform (+ Body Tracking joints if available); IMU path passes DeviceMotion + integrated pos.

## 8) Persistence & Resets
- Persist: orientation map, segment lengths, grip offset, learned k, last good anchors’ metrics.
- On AR relocalization: clear only positional anchors; keep orientation map and learned parameters.

## 9) Telemetry & QA
- Log per-frame: θ, w_orient, w_arc, S ratio, anchorsValid, elbowDominant.
- Scenarios: straight-arm raises, bent-elbow raises, fast vs slow, room change, phone grips.
- Targets: MAE < 5–8° vs AR Body joints when available.

## 10) Implementation Tasks
- [ ] Add `ShoulderROMEstimator` and `ElbowCompensator` with S-ratio gating and fusion.
- [ ] Add optional `ARBodyTrackingProvider` (rear camera) to supply 3D joints when supported.
- [ ] Extend Calibration Wizard: micro-gesture for grip offset; segment length entry/estimate.
- [ ] Wire into `SimpleMotionService` for ARKit world-tracking, ARKit body-tracking, and IMU-only.
- [ ] Persist parameters; add telemetry.

## 11) Pseudocode (Estimator)
```swift
func update(meas: Meas) -> Double {
  let theta_orient = calib.map(pitchRoll: meas.pitch, meas.roll)
  var theta_arc: Double? = nil
  if meas.anchorsValid, let d = meas.displacement, let R = radius {
    theta_arc = 2.0 * asin(min(max(d/(2*R), 0), 1)) * rad2deg
  }
  let S = classifyRatio(displacement: meas.displacement, dAngle: meas.deltaPitchRoll, R: radius)
  let elbow = elbowCompensation(S: S, deltaAngle: meas.deltaPitchRoll, forearmLen: R_fa, gripOffset: grip)
  let (wO, wA) = weights(S: S, anchorsValid: meas.anchorsValid)
  let theta = wO * (theta_orient - k * elbow) + wA * (theta_arc ?? theta_orient)
  return ema(clamp(theta, 0, 180))
}
```
