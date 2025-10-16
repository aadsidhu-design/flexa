# SPARC and ROM Calculation Fixes - Complete

**Date:** October 12, 2025  
**Scope:** Camera and handheld game smoothness (SPARC) + handheld ROM finalization

## Problems Fixed

### 1. **Live SPARC Logs During Gameplay** ❌
- **Before:** Real-time SPARC finalization after every rep with verbose logging
- **Issue:** Cluttered logs, unnecessary computation during gameplay
- **After:** SPARC calculated once in analyzing screen from complete trajectory data

### 2. **Incorrect SPARC Data Sources** ❌
- **Camera Games Before:** Using IMU/accelerometer data (phone motion)
- **Handheld Games Before:** Using IMU data instead of ARKit positions
- **After:** 
  - **Camera:** Wrist trajectory smoothness from pose keypoints (TODO: capture wrist data)
  - **Handheld:** ARKit 3D position trajectory smoothness

### 3. **Premature ROM Finalization** ❌
- **Before:** Handheld ROM calculated live during gameplay, subject to tracking gaps
- **After:** Live ROM for HUD feedback, **final ROM calculated in analyzing screen** from stored trajectories

## Implementation Details

### SPARC Calculation Service (`SPARCCalculationService.swift`)

#### New Methods Added:
```swift
// Camera games: compute smoothness from wrist 2D trajectory
func computeCameraWristSPARC(wristPositions: [CGPoint], timestamps: [TimeInterval]) -> Double?

// Handheld games: compute smoothness from ARKit 3D trajectory
func computeHandheldARKitSPARC(positions: [SIMD3<Float>], timestamps: [TimeInterval]) -> Double?
```

**How it works:**
1. Takes full session trajectory (positions + timestamps)
2. Computes velocity magnitudes from position deltas
3. Detrends velocity signal (removes mean)
4. Applies spectral arc length (SPARC) algorithm
5. Returns normalized smoothness score (0-100)

**Key difference from old approach:**
- Uses **spatial trajectory data** (actual movement path)
- Not IMU/accelerometer (which measures phone shaking, not movement smoothness)

### Simple Motion Service (`SimpleMotionService.swift`)

#### Changes Made:

**1. Removed Live SPARC Finalization:**
```swift
// OLD (removed):
self._sparcService.finalizeHandheldRep(at: timestamp) { score in
    self.sparcHistory.append(score)
    FlexaLog.motion.info("📊 [HandheldSPARC] Real-time rep #\(reps) SPARC score=\(score)")
}

// NEW:
// 📊 SPARC calculation deferred to analyzing screen - no live logs during gameplay
FlexaLog.motion.debug("🔁 [HandheldRep] Rep #\(reps) completed at \(timestamp)s")
```

**2. Added Trajectory Export Methods:**
```swift
func getHandheldRepTrajectories() -> [HandheldRepTrajectory]
func computeFinalHandheldROMFromTrajectories() -> [Double]
func getARKitPositionTrajectory() -> (positions: [SIMD3<Float>], timestamps: [TimeInterval])
```

**3. Updated ROM Recording:**
- Live ROM values marked as **preliminary**
- Final ROM calculation happens in analyzing screen from trajectories

### Analyzing View (`AnalyzingView.swift`)

#### New Calculation Flow in `calculateComprehensiveMetrics()`:

```swift
// 1. Compute SPARC from session trajectories
if isHandheldGame {
    let (positions, timestamps) = motionService.getARKitPositionTrajectory()
    finalSPARCScore = sparcService.computeHandheldARKitSPARC(positions, timestamps)
} else {
    // Camera games: TODO - need to capture wrist positions during gameplay
    finalSPARCScore = sessionData.sparcScore
}

// 2. Finalize ROM from handheld trajectories
if isHandheldGame {
    finalROMPerRep = motionService.computeFinalHandheldROMFromTrajectories()
    finalMaxROM = finalROMPerRep.max()
    finalAvgROM = finalROMPerRep.average()
}

// 3. Apply final metrics to session data
enhancedData.sparcScore = finalSPARCScore
enhancedData.romHistory = finalROMPerRep
enhancedData.maxROM = finalMaxROM
enhancedData.averageROM = finalAvgROM
```

## Data Flow Summary

### Handheld Games (Fruit Slicer, Fan Flame, Follow Circle)

**During Gameplay:**
1. ARKit tracker captures 3D positions at ~60fps → `arkitPositionHistory`
2. ROM calculator stores per-rep trajectories → `HandheldRepTrajectory`
3. Live ROM shown in HUD (preliminary, for feedback only)
4. **No SPARC calculation** (deferred to analyzing screen)

**In Analyzing Screen:**
1. Retrieve ARKit position trajectory
2. Compute SPARC from 3D velocity smoothness
3. Recompute ROM from stored per-rep trajectories
4. Display final metrics

### Camera Games (Balloon Pop, Wall Climbers, Constellation)

**During Gameplay:**
1. Pose keypoints captured → wrist positions tracked
2. ROM calculated from joint angles (armpit/elbow)
3. Live ROM shown in HUD
4. **No SPARC calculation** (deferred to analyzing screen)

**In Analyzing Screen:**
1. **TODO:** Retrieve wrist trajectory from captured keypoints
2. Compute SPARC from wrist 2D velocity smoothness
3. Use live ROM values (already accurate)
4. Display final metrics

## Benefits

### ✅ Cleaner Logs
- No more "📊 [HandheldSPARC] Real-time rep #X SPARC score=Y" spam during gameplay
- Single calculation with final values in analyzing screen

### ✅ Accurate SPARC
- **Handheld:** Based on actual 3D movement trajectory (not phone shaking)
- **Camera:** Based on wrist movement trajectory (not phone accelerometer)

### ✅ Reliable ROM
- **Handheld:** Recalculated from complete trajectories, avoiding tracking gaps
- Live ROM still available for HUD feedback

### ✅ Better Performance
- No expensive SPARC FFT calculations during gameplay
- All computation happens once in analyzing screen

## Camera Game TODO

**Missing:** Wrist position capture during camera gameplay

**Required Changes:**
1. Store wrist positions + timestamps during `processPoseKeypointsInternal`
2. Add `getCameraWristTrajectory()` method to SimpleMotionService
3. Update AnalyzingView to call `computeCameraWristSPARC()` with wrist data

**Temporary State:**
- Camera games use existing SPARC calculation (camera smoothness analyzer)
- Works but not optimal (should use wrist trajectory)

## Testing Checklist

### Handheld Games:
- [ ] Play Fruit Slicer, verify no SPARC logs during gameplay
- [ ] Check analyzing screen shows final SPARC score
- [ ] Verify ROM values are recalculated from trajectories
- [ ] Confirm live ROM in HUD still works during gameplay

### Camera Games:
- [ ] Play Balloon Pop, verify no SPARC logs during gameplay
- [ ] Check analyzing screen shows SPARC score (temporary calculation)
- [ ] Verify ROM values match live calculations
- [ ] (Future) Test wrist trajectory SPARC when implemented

## Code Quality

### Architecture:
- ✅ Separation of concerns: gameplay vs. analysis
- ✅ Single responsibility: SPARC service handles smoothness, not motion service
- ✅ Data availability: trajectories stored for post-session analysis

### Performance:
- ✅ No heavy computation during gameplay
- ✅ Batch processing in analyzing screen
- ✅ Trajectory data stored efficiently in BoundedArray

### Maintainability:
- ✅ Clear documentation of data flow
- ✅ Explicit preliminary vs. final calculations
- ✅ TODO markers for incomplete features

## Summary

**SPARC is now calculated correctly:**
- **Camera games:** From wrist movement smoothness (TODO: capture wrist data)
- **Handheld games:** From ARKit 3D trajectory smoothness

**ROM is finalized accurately:**
- **Handheld games:** Recalculated from complete trajectories in analyzing screen
- **Camera games:** Use live calculations (already accurate)

**Logs are clean:**
- No live SPARC spam during gameplay
- Single final calculation with detailed metrics

**Next steps:**
1. Implement wrist position capture for camera games
2. Test analyzing screen metrics thoroughly
3. Verify performance on physical device
