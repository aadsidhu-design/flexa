# Comprehensive Fix Plan

## Issues to Fix:

### 1. Follow Circle ✅
- **Problem**: SPARC not good, reps not registering
- **Root Cause**: Rep detection parameters too strict, position-based detection not working
- **Fix**: Switch to IMU gyroscope-based rep detection like Fruit Slicer
- **Files**: `SimpleMotionService.swift`, `HandheldRepDetector.swift`

### 2. Pain Change Over Week ✅
- **Problem**: Need average pain change over week for ALL exercises
- **Fix**: Calculate from session history, show in progress view
- **Files**: `EnhancedProgressViewFixed.swift`, `LocalDataManager.swift`

### 3. Fan the Flame ✅
- **Problem**: Reps should work like Fruit Slicer (direction change)
- **Fix**: Already uses IMU direction detector, verify it's working
- **Files**: `SimpleMotionService.swift`

### 4. Constellation Game ⚠️
- **Problem**: Glitchy, not tracking properly, logic needs complete rewrite
- **Fix**: Simplify connection logic, improve validation, ensure 3 patterns before end
- **Files**: `SimplifiedConstellationGameView.swift`

### 5. BlazePose Model ✅
- **Status**: Already using FULL model (`pose_landmarker_full.task`)
- **Verified**: Line 60 in `BlazePosePoseProvider.swift`

### 6. Custom Exercises 🔧
- **Problem**: Need robust rep detection based on movement type
- **Fix**: Specialized detectors for circular, pendulum, horizontal, vertical
- **Files**: `CustomRepDetector.swift`, `SimpleMotionService.swift`

## Implementation Order:
1. Fan the Flame (verify IMU detection) ✅
2. Follow Circle (switch to IMU) ✅
3. Pain tracking (implement weekly average) ✅
4. Constellation (complete rewrite) 🚧
5. Custom exercises (robust rep detection) 🚧

Let's begin!
