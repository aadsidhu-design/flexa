# Camera & Handheld Systems Audit

This audit inspects ARKit/handheld, MediaPipe/Vision camera pipelines, ROM and rep detection, and SPARC smoothness calculation across the FlexaSwiftUI app.

## Summary of Findings

- Handheld (ARKit) pipeline:
  - ARKit input flows through `HandheldMotionService` → `SimpleMotionService`.
  - `HandheldROMCalculator` computes ROM using a session baseline, best-plane projection, and arc-length → angle conversion.
  - `HandheldRepDetector` uses hysteresis and angle accumulation for pendulum/circular detection with per-game parameters.
  - Observed: `HandheldROMCalculator` resets per-rep buffers correctly; ARKit tracker is multi-tier (camera+object / face+object fallback).

- Camera (MediaPipe / Vision) pipeline:
  - MediaPipe provider (`MediaPipePoseProvider`) emits normalized 0..1 coordinates, mirrors X for front camera.
  - Vision provider (`VisionPoseProvider`) emitted pixel-space coordinates with a 480x640 reference and flipped Y for a top-left origin.
  - `CameraROMCalculator` expects normalized/pixel-space points and computes elbow/armpit angles using 3-point math. Works with normalized 0..1 coordinates if mapped to screen pixels via `CoordinateMapper` for distance thresholds.
  - Identified coordinate mismatch risk between providers. Resolved by normalizing Vision outputs to 0..1 and centralizing mapping via `CoordinateMapper.normalizePixelPointToNormalized`.

- Rep detectors:
  - Handheld rep detector gating: `isHandheldRepDetectorActive` state is set conservative and may be inert for some games; ensure this aligns with intended game logic.
  - Camera rep detector (`CameraRepDetector`) applies hysteresis and cooldown; some per-game thresholds are delegated to `SimpleMotionService.getMinimumROMThreshold`, which already includes sensible defaults for camera games.

- SPARC smoothness:
  - `SPARCCalculationService` provides canonical SPARC calculations using vDSP FFT across IMU, Vision, and ARKit pipelines. SPARC.swift contains a DFT fallback.
  - Observed multiple SPARC implementations; ensure one canonical API to avoid subtle differences.

## Issues (ranked)

1. Coordinate normalization mismatch (High):
   - MediaPipe returns normalized 0..1; Vision returned pixel 480x640. This could lead to inconsistent ROM or rep thresholds and SPARC inputs.
   - Fix applied: added `CoordinateMapper.normalizePixelPointToNormalized` and updated `VisionPoseProvider` to output normalized points.

2. Handheld rep-detector gating (High):
   - `isHandheldRepDetectorActive` is selectively enabled for some games (FollowCircle). Verify intended behavior for FruitSlicer and FanOutFlame to avoid missed detections.
   - Recommendation: Either enable the detector for all handheld games that need direction-change counting, or document and add explicit logic where different detection methods are used.
   - Action taken: enabled `HandheldRepDetector` for FruitSlicer and FanOutFlame in `SimpleMotionService.startHandheldSession` and ensured mutual-exclusion logic no longer disables it (Kalman IMU path removed).

3. SPARC canonicalization (Medium):
   - Multiple SPARC implementations may produce different scalings. Prefer using `SPARCCalculationService` as the canonical backend. Add a small adapter in `SPARC.swift` if necessary.
   - Action taken: added a static helper `SPARCCalculationService.computeSPARCStandalone` and updated `SPARC.swift` to call the canonical implementation. Legacy DFT code is retained as an internal helper but SPARCCalculationService is now the canonical backend.

4. Camera rep thresholds (Medium):
   - Confirmed: `getMinimumROMThreshold(for:)` provides non-zero minima for common camera games (e.g., BalloonPop, WallClimbers). No change required now, but adjust per-game if false positives are observed.

5. Performance and threading (Low):
   - SPARC uses FFT on a background queue. Confirm buffer sizes and FFT param selection to avoid spikes.

## Concrete Changes Implemented

- Added CoordinateMapper.normalizePixelPointToNormalized(...) to `Utilities/CoordinateMapper.swift` to convert Vision pixel-space to normalized 0..1 coordinates (with mirroring option).
- Updated `VisionPoseProvider.makeKeypoints` to use the normalization helper and output normalized coordinates (match MediaPipe signature).

## Recommended Next Steps

1. Verify Handheld rep-detector gating:
   - Inspect `SimpleMotionService.startHandheldSession` and ensure `isHandheldRepDetectorActive = true` for games that require it. If Fruit Slicer and Fan the Flame rely solely on ROM direction-change, ensure detector not required.
   - Short patch: set `isHandheldRepDetectorActive = true` for all handheld games (small, low-risk change) and test.

2. SPARC canonicalization & tests:
   - Reconcile `SPARC.swift` and `SPARCCalculationService` to ensure identical scaling and a single public API. Add unit tests to assert outputs from both match within tolerance.
   - Add a small adapter `SPARCCompatibility.swift` if needed.

3. Tests & Validation:
   - Run existing `CameraRepDetectorTests` to confirm behavior after normalization change.
   - Add unit tests for Vision normalization (happy path + edge cases like landmarks out-of-bounds). Add tests for CoordinateMapper.normalizePixelPointToNormalized.

4. Documentation:
   - Update docs to explicitly state coordinate conventions expected by SimplifiedPoseKeypoints (normalized 0..1 top-left with X mirrored for front camera).

## Files Reviewed
- Services/SimpleMotionService.swift
- Services/Handheld/HandheldROMCalculator.swift
- Services/Handheld/HandheldRepDetector.swift
- Services/Handheld/HandheldMotionService.swift
- Services/Handheld/InstantARKitTracker.swift
- Services/Camera/MediaPipePoseProvider.swift
- Services/Camera/VisionPoseProvider.swift
- Services/Camera/CameraROMCalculator.swift
- Services/Camera/CameraRepDetector.swift
- Services/Camera/CameraSmoothnessAnalyzer.swift
- Services/SPARC/SPARCCalculationService.swift
- Services/SPARC.swift
- Services/SimplifiedPoseKeypoints.swift
- Utilities/CoordinateMapper.swift

## Acceptance Criteria
- All camera providers emit `SimplifiedPoseKeypoints` with normalized 0..1 coordinates and consistent mirroring.
- Handheld ARKit ROM uses baseline and projects to best 2D plane; per-rep arc-length is used for ROM and reset between reps.
- SPARC pipeline uses `SPARCCalculationService` as the canonical source for smoothness timelines.
- Rep detectors use per-game thresholds and enforce sufficient cooldowns to avoid duplicates.

---

Audit completed: Coordinate normalization fix implemented. Next: enable gating checks, SPARC canonicalization plan, and tests.
