ROMS and Games Audit — Short Report

Scope
- Handheld games: Fruit Slicer, Fan the Flame (FanOutFlame), Follow Circle.
- Camera games: Wall Climbers, Constellation (Arm Raises), Balloon Pop (Elbow Extension).

Summary of what I inspected
- SimpleMotionService.swift — central orchestrator for ARKit, MediaPipe, SPARC, rep detectors and session export.
- Handheld/InstantARKitTracker.swift — ARKit position provider and callbacks.
- Handheld/HandheldROMCalculator.swift — converts 3D trajectories into ROM (arc-length, circular radius math) and resets baselines on rep complete.
- Handheld/HandheldRepDetector.swift — pendulum and circular rep detection logic.
- Camera/MediaPipePoseProvider.swift — MediaPipe BlazePose integration and conversion to SimplifiedPoseKeypoints.
- Camera/CameraROMCalculator.swift — camera-based ROM math (elbow angle and shoulder/armpit angle).
- Camera/CameraRepDetector.swift and Camera/CameraSmoothnessAnalyzer.swift — rep cooldown and SPARC feeding.
- Models/ComprehensiveSessionData.swift — final export model and fields required by backend.

High-level findings (what's good)
- Clear separation: Handheld flow uses ARKit -> HandheldROMCalculator -> SPARC; Camera flow uses MediaPipe -> CameraROMCalculator -> SPARC.
- Handheld ROM calculator implements plane-selection (xy/xz/yz) using variance and does a 2D-projection arc-length method — this matches your described approach to reduce wrist bias.
- HandheldROMCalculator correctly resets baselines at rep completion (prevents ROM accumulation) — good.
- HandheldRepDetector implements direction-change rep detection for pendulum games and full-rotation accumulation for circular games. It exposes romProvider closures so detectors can check live ROM.
- MediaPipe provider converts MediaPipe landmarks to the app's SimplifiedPoseKeypoints and properly mirrors front camera X coordinates — good for consistency.
- Camera ROM calculator has both elbow flexion and shoulder abduction (armpit) calculations implemented and a selection strategy preferring confidence — matches the camera-game ROM rules.

High-level issues and risks (prioritized)
1) Missing ARKit start for IMU-primary games (observed & fixed)
   - Symptom: Kalman IMU used as primary rep detector for Fruit Slicer/Fan, but ROM is sourced from ARKit positions. If ARKit wasn't started, ROM would be zero or missing.
   - Fix applied: auto-start ARKit in startHandheldSession when Kalman IMU is primary. (Small, safe patch added.)
   - File/lines: SimpleMotionService.startHandheldSession (around 1490+)
   - Severity: High for correctness of ROM metrics in IMU-primary games.

2) Coordinate / mapping confidence and logging
   - MediaPipe points are clamped to 0..1 and mirrored for front camera in MediaPipePoseProvider.getNormalizedMirroredPoint — this is correct, but the project has had many previous fixes (docs show multiple iterations). Recommend adding a unit test for coordinate transforms to lock in behavior.
   - File/lines: Camera/MediaPipePoseProvider.swift convertToSimplifiedKeypoints / getNormalizedMirroredPoint.
   - Severity: Medium.

3) SPARC calculation and lifecycle
   - SPARC is fed ARKit positions live (sparcService.addARKitPositionData) and camera wrist positions via CameraSmoothnessAnalyzer. Handheld SPARC appears deferred for post-game analysis and stored in offlineHandheldSparcTimeline — reasonable.
   - Risk: If ARKit tracking quality drops (limited/notAvailable), arkitPositionHistory may contain bad data. There is gating (isARKitTrackingNormal) used when appending arkitPositionHistory which is good; keep QA on transitions and relocalization.
   - File/lines: SimpleMotionService.arkitTracker.onPositionUpdate and onTransformUpdate.
   - Severity: Medium.

4) Many global helpers/logging/calibration symbols used across files (FlexaLog, CalibrationDataManager, ROMErrorHandler) weren't resolved by the static checker in this environment
   - The project build in Xcode likely provides them; the analyzer showed missing types when run outside Xcode context. Still, ensure these singletons are robust to nil and provide stubs in unit tests.
   - Files: multiple (HandheldROMCalculator, InstantARKitTracker, many).
   - Severity: Low (environmental), but add tests and graceful handling in code paths.

5) Constellation and pattern validation complexity
   - The repo includes docs and several fixes indicating triangle/square/circle validation and the need to connect back to the start for triangle; the UI views call recordCameraRepCompletion after validation. Suggest moving complex validation logic into a testable game-model class and add unit tests for allowed/disallowed transitions.
   - Files: Games/SimplifiedConstellationGameView.swift (and docs mention fixes applied already)
   - Severity: Medium (games logic correctness)

6) Camera rep detection rules and thresholds
   - CameraRepDetector enforces a minimum interval cooldown and threshold. The SimpleMotionService.getMinimumROMThreshold returns 0 for all games. That means cameraRepDetector will accept any ROM >= 0 (subject to cooldown). Consider per-game minimums (e.g., elbow extension > 15°, armpit raise > 10°) to avoid noise.
   - Files: SimpleMotionService.getMinimumROMThreshold and CameraRepDetector.evaluateRepCandidate
   - Severity: Medium (false-positive rep counts possible)

7) Follow Circle specifics
   - HandheldROMCalculator uses circular motion center estimation and calculates rotation accumulator (via HandheldRepDetector). The rep reset in completeRep zeroes baselines, which matches your stated need of resetting ROM baseline after each rep — good.
   - Still: verify that rep completion triggers a baseline reset immediately (it does) so ROM doesn't accumulate across reps.
   - Files: HandheldROMCalculator.completeRep
   - Severity: Low

8) Session export and model shape
   - ComprehensiveSessionData requires fields like userID, sessionNumber, sparcDataOverTime, romPerRep, repTimestamps. SimpleMotionService.createSessionDataSnapshot and getFullSessionData provide these pieces, but ensure fields such as userID/sessionNumber are populated upstream by LocalDataManager before upload.
   - Files: Models/ComprehensiveSessionData.swift and SimpleMotionService.createSessionDataSnapshot / getFullSessionData
   - Severity: Low-to-medium (data completeness for server analytics)

Concrete recommended fixes (quick, safe, prioritized)
1) (APPLIED) Auto-start ARKit when Kalman IMU is primary to ensure ROM availability. See SimpleMotionService.startHandheldSession patch.
2) Add per-game minimum ROM thresholds in getMinimumROMThreshold(for:) for camera games (balloonPop elbow: 15°, wallClimbers armpit: 12°, constellation: 10°). This will reduce false positives.
3) Add unit tests for MediaPipe coordinate transform mirroring and clamping to confirm front/back camera behavior.
4) Move Constellation validation logic into a ConstellationGame model class and cover with unit tests (triangle must return to start point; square must not accept diagonal). The repo docs indicate partial fixes already; this will make it maintainable.
5) Add a small defensive check in SPARC ingestion to drop arkit positions when arkitTracker.trackingQuality != .normal for >0.5s (or add a relocalization guard) — there is already isARKitTrackingNormal gating, but consider stricter temporal guards across relocalization transitions.
6) Add per-game configuration constants (thresholds, cooldowns) in a single place (GameConfig) to tune without code changes.

Suggested next steps & tests
- Add a small unit test target for these core services. Tests to add now:
  - MediaPipe coordinate transform correctness (front/back mirroring, clamping)
  - HandheldROMCalculator projection plane selection (synthesize trajectories on XY/XZ/YZ and assert plane chosen and ROM computed)
  - HandheldRepDetector pendulum detection: feed a synthetic forward/backward swing and assert rep count increments on direction change
  - CameraRepDetector cooldown: ensure repeated candidate calls within cooldown are rejected
- Run an instrumented on-device test for ARKit gating: start Fruit Slicer session while moving slowly and with fast motion to ensure isMovementTooFast gating works and ARKit remains Normal.

Files changed
- SimpleMotionService.swift — small, safe edit to auto-start ARKit for IMU-primary handheld games.

Quality gates
- Build: Not fully validated in this environment (Xcode frameworks like UIKit/ARKit/Metal unavailable). The codebase has many platform-specific symbols that require Xcode and iOS SDK to fully build. The change applied is small and uses existing APIs.
- Lint/Typecheck: Some unresolved symbols were reported by the static checker used in this environment (FlexaLog, CalibrationDataManager). These are project-specific singletons and likely exist when building in Xcode.

Completion summary
- I inspected the core handheld and camera pipelines, verified the ROM calculation approaches align with your design (projection to best plane, arc-length->angle, circular radius math), and validated rep-detection logic types (direction-change pendulum, angle accumulation for circles, peak-based for camera reps).
- I applied a conservative fix to auto-start ARKit when IMU/Kalman is primary to ensure ROM is available, and I documented prioritized next actions and tests.

If you want, I can:
- Implement the per-game minimum ROM thresholds (quick change).
- Add a simple ConstellationGame model refactor (more work but testable).
- Add unit tests for the coordinate transform and ROM math (requires setting up a lightweight test target).

Which should I do next? (I recommend adding per-game camera thresholds and small unit tests for MediaPipe mirroring first.)
