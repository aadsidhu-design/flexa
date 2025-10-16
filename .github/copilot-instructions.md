```instructions
## FlexaSwiftUI — AI Agent Quick Guide

Small, conservative edits are preferred. Run a build after 1–3 edits and surface diagnostics early.

Key files (read these first):
- `Services/SimpleMotionService.swift` — central coordinator (shared singleton) that gates camera vs handheld processing, feeds SPARC, and prepares `ComprehensiveSessionData` for upload.
- `Services/InstantARKitTracker.swift` — ARKit provider used for handheld ROM/rep when `DiagnosticsSample/stateLabel == "Normal"`.
- `Services/BlazePosePoseProvider.swift` & `Services/VisionPoseProvider.swift` — camera pose providers producing `SimplifiedPoseKeypoints`.
- `Services/HandheldROMCalculator.swift` & `Services/UnifiedRepROMService.swift` — trajectory -> ROM and per-rep data.
- `Services/SPARCCalculationService.swift` & `Services/SPARC.swift` — SPARC/smoothness pipeline; camera SPARC is eager, handheld SPARC may be deferred to `offlineHandheldSparcTimeline`.
- `Models/ComprehensiveSessionData.swift` — export model; ensure `userID`, `sessionNumber`, `sparcDataOverTime`, `romPerRep`, and `repTimestamps` are populated for uploads.

Build & debug (repo root):
- Full build and capture logs:
  xcodebuild -workspace FlexaSwiftUI.xcworkspace -scheme FlexaSwiftUI -destination 'id=<simulator-uuid>' clean build | tee /tmp/flexa_full_build.log
- Grep for errors: `grep -n "error:\|fatal error" /tmp/flexa_full_build.log`

Project patterns and gotchas (be concrete):
- Compatibility shims over refactors: many call-sites expect legacy API shapes. Add convenience inits or thin adapter methods (see `MotionAdapters.swift` and `Services/SPARCCompatibility.swift`).
- Preserve access levels: widen to `internal` rather than `fileprivate` only when necessary.
- Time handling: use `TimeInterval` for runtime data; convert to `Date`/ISO8601 only for exports.
- ARKit gating: `InstantARKitTracker.DiagnosticsSample.stateLabel` must be `Normal` before enabling handheld ROM/rep processing in `SimpleMotionService`.

Integration notes:
- MediaPipe (BlazePose) lives in `Pods/MediaPipeTasksVision` and `Pods/MediaPipeTasksCommon`. The model file `pose_landmarker_full.task` is referenced by `BlazePosePoseProvider.swift` — avoid renaming that path.
- Backend uploads: implemented in `Services/BackendService.swift` — payloads depend on `ComprehensiveSessionData` fields listed above.

Quick triage checklist (most common fixes):
1. Search build log for `error:` and fix missing members with small stubs (convenience init or no-op method). See `BUILD_FIXES_APPLIED.md` for past examples.
2. Missing enum cases? Add the case and map display names in `SimpleMotionService.GameType`.
3. MediaPipe provider API mismatch? Add a shim in `Services/Camera/CameraStubs.swift` that implements expected lifecycle methods (`start/stop/processFrame/onPoseDetected/setErrorHandler`).
4. SPARC signature differences? Add adapter methods in `Services/SPARCCompatibility.swift`.

Files & docs that explain architecture (use these as references):
- `ARKIT_IMPROVEMENTS_IMPLEMENTED.md`, `HANDHELD_ROM_STATUS.md`, `SPARC_ROM_VERIFICATION_COMPLETE.md`, and `BLAZEPOSE_MIGRATION_SUCCESS.md` — focused change notes and code locations.

If anything here is unclear or you'd like signature examples (shim or adapter methods) included, tell me which area and I will add concrete code snippets.

```## FlexaSwiftUI — AI Agent Instructions

This file is a concise, actionable guide for automated coding agents working on the FlexaSwiftUI iOS app.
Keep edits small and conservative: prefer compatibility shims over large refactors, run the build after every 1–3 edits, and surface diagnostics early.

- Key entry points and services to know:
  - `Services/SimpleMotionService.swift` — central orchestrator for ROM/rep detection, camera vs handheld gating, SPARC ingestion, and session export. Most cross-service wiring lives here.
  - `Services/SPARCCalculationService.swift` & `Services/SPARC.swift` — smoothness/SPARC logic and helpers. Exports SPARC time-series used by Results and session payloads.
  - `Services/InstantARKitTracker.swift` — lightweight ARKit tracker. Handheld ROM/rep processing is gated until ARKit readiness sample (`DiagnosticsSample/stateLabel`) indicates `Normal`.
  - `Services/BlazePosePoseProvider.swift` and `Services/VisionPoseProvider.swift` — camera pose providers. They produce `SimplifiedPoseKeypoints` consumed by `SimpleMotionService` and Camera calculators.
  - `Services/HandheldROMCalculator.swift` & `Services/UnifiedRepROMService.swift` — compute ROM and per-rep trajectories for handheld games.
  - `Models/ComprehensiveSessionData.swift` — final export model. Ensure `sparcDataOverTime`, `romPerRep` and `repTimestamps` are populated when exporting.

- Build & debug (run in repo root):
  - Clean + build (captures full compiler output):
    xcodebuild -workspace FlexaSwiftUI.xcworkspace -scheme FlexaSwiftUI -destination 'id=<simulator-uuid>' clean build | tee /tmp/flexa_full_build.log
  - Use the generated logs (`/tmp/flexa_full_build*.log`) and grep for `error:` lines to prioritize fixes.

- Common compatibility patterns you should follow:
  - Many call-sites expect older API shapes. Add small compatibility shims (convenience inits, no-op methods, or lightweight adapters) rather than wholesale refactors to minimize churn.
  - When adding methods to services, preserve access levels (make helpers `internal` instead of `fileprivate` if used across files).
  - Preserve session numbering when deleting/clearing data—`LocalDataManager` intentionally keeps sequential numbering.

- Project-specific conventions:
  - Time values: prefer `TimeInterval` (seconds since epoch) for runtime processing, and convert to `Date` only for exports using `ISO8601DateFormatter`.
  - SPARC pipeline: camera SPARC is computed eagerly for camera exercises; handheld SPARC can be deferred to the analyzing screen and stored in `offlineHandheldSparcTimeline`.
  - Pose model: `SimplifiedPoseKeypoints` is the canonical simplified landmark struct. Some providers pass fewer confidences; add convenience initializers in that file to accept legacy call shapes.
  - ARKit readiness gating: `InstantARKitTracker.DiagnosticsSample` and `stateLabel` are used to mark ARKit `Normal` before enabling handheld rep/ROM processing.

- Integration & external deps to respect:
  - MediaPipe frameworks are present in `Pods/MediaPipeTasksVision` and `Pods/MediaPipeTasksCommon` — BlazePose integration appears in `BlazePosePoseProvider.swift`. If you change these call paths, keep the MediaPipe model file `pose_landmarker_full.task` referenced by the provider.
  - Backend uploads use `Services/BackendService.swift` and `Models/ComprehensiveSessionData.swift`. Exports must include `userID`, `sessionNumber`, `sparcDataOverTime`, `romPerRep`, and `repTimestamps`.

- Quick coding checklist for common build errors:
  1. Grep compiler log for `error:` lines. Focus on missing members (add lightweight stubs) and initializer mismatches (add convenience initializers).
  2. If a missing enum case is reported, prefer adding a new case and mapping display names in `SimpleMotionService.GameType`.
  3. If `MediaPipePoseProvider` lacks methods (start/stop/processFrame/onPoseDetected/setErrorHandler), add a shim class in `Services/Camera/CameraStubs.swift` that forwards to existing providers or no-ops.
  4. When SPARC call signatures differ, provide adapter methods in `Services/SPARCCompatibility.swift` that translate between older call sites and the canonical `SPARCCalculationService` functions.

- Files to read first when onboarding:
  - `Services/SimpleMotionService.swift` (wiring + gating)
  - `Services/BlazePosePoseProvider.swift` and `Services/VisionPoseProvider.swift` (pose conversion)
  - `Services/HandheldROMCalculator.swift` (trajectory -> ROM)
  - `Services/SPARCCalculationService.swift` and `Services/SPARC.swift` (smoothness)
  - `Models/ComprehensiveSessionData.swift` (export shape)

If anything in this guide is unclear or you want more examples (e.g., exact shim signatures seen in build logs), say which area and I'll expand the doc with concrete snippets and prioritized next edits.
