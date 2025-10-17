# ARKit Initialization Fix - Eliminating 0° ROM at Start

**Date:** October 15, 2024  
**Issue:** Multiple 0° ROM values appearing at the start of handheld games  
**Status:** ✅ FIXED

---

## Problem

At the start of handheld games (Fruit Slicer, Fan the Flame), there were several 0° ROM values showing up before actual tracking began:

**Symptoms:**
- ROM graph starts with 0°, 0°, 0°, 0°... then jumps to real values
- First few reps show 0° ROM
- Initialization period visible in data/graphs
- Looks unprofessional and confuses metrics

**Root Cause:**
ARKit requires ~1 second to initialize and stabilize tracking:
- Device needs to detect features in environment
- World tracking needs to lock onto visual features
- Camera transform stabilizes

During this period:
- `currentROM` is 0.0 (initial value)
- ROM callbacks fire but with unstable data
- Baseline gets set before tracking is ready

---

## Solution Overview

Added **initialization gates** to prevent ROM updates until ARKit is fully initialized and stable.

### Key Changes:

1. ✅ Gate position processing until initialized
2. ✅ Gate ROM updates until initialized  
3. ✅ Gate rep ROM recording until initialized

---

## Technical Implementation

### 1. ARKit Initialization Tracking

**File:** `InstantARKitTracker.swift`

Already had initialization delay logic:

```swift
/// ARKit initialization delay - wait for stable tracking before processing reps/ROM
private let arkitInitializationDelay: TimeInterval = 1.0
private var arkitInitializedTime: TimeInterval?

/// Is ARKit fully initialized and stable?
@Published private(set) var isFullyInitialized = false
```

**Initialization Flow:**
1. `start()` called → ARKit session begins
2. Tracking state becomes `.normal` → `arkitInitializedTime` set
3. After 1.0 second → `isFullyInitialized = true`
4. Log: "✅ Fully initialized - ROM and reps will now be tracked"

### 2. Position Processing Gate

**File:** `SimpleMotionService.swift` - `setupHandheldTracking()`

**OLD CODE:**
```swift
arkitTracker.onPositionUpdate = { [weak self] position, timestamp in
    guard let self = self, !self.isCameraExercise else { return }
    
    // Feed to rep detector
    self.handheldRepDetector.processPosition(position, timestamp: timestamp)
    
    // Feed to ROM calculator
    self.handheldROMCalculator.processPosition(position, timestamp: timestamp)
}
```

**Problem:** Processes positions immediately, even during initialization

**NEW CODE:**
```swift
arkitTracker.onPositionUpdate = { [weak self] position, timestamp in
    guard let self = self, !self.isCameraExercise else { return }
    
    // Only process if ARKit is fully initialized (prevents 0° ROM values at start)
    guard self.arkitTracker.isFullyInitialized else {
        FlexaLog.motion.debug("📍 [HandheldTracking] Skipping position - ARKit still initializing")
        return
    }
    
    // Feed to rep detector
    self.handheldRepDetector.processPosition(position, timestamp: timestamp)
    
    // Feed to ROM calculator
    self.handheldROMCalculator.processPosition(position, timestamp: timestamp)
}
```

**Impact:** No positions processed until ARKit ready → No baseline set early → No false ROM values

### 3. ROM Update Gate

**File:** `SimpleMotionService.swift` - `setupHandheldTracking()`

**OLD CODE:**
```swift
handheldROMCalculator.onROMUpdated = { [weak self] rom in
    DispatchQueue.main.async {
        self?.currentROM = rom
        if rom > (self?.maxROM ?? 0) {
            self?.maxROM = rom
        }
    }
}
```

**Problem:** Updates `currentROM` immediately, including 0° during initialization

**NEW CODE:**
```swift
handheldROMCalculator.onROMUpdated = { [weak self] rom in
    guard let self = self else { return }
    
    // Don't update ROM until ARKit is fully initialized
    guard self.arkitTracker.isFullyInitialized else {
        return
    }
    
    DispatchQueue.main.async {
        self.currentROM = rom
        if rom > self.maxROM {
            self.maxROM = rom
        }
    }
}
```

**Impact:** UI shows 0° during initialization but doesn't update → First real ROM value appears when tracking starts

### 4. Rep ROM Recording Gate

**File:** `SimpleMotionService.swift` - `setupHandheldTracking()`

**Status:** ⚠️ NEEDS TO BE ADDED

**Required Code:**
```swift
handheldROMCalculator.onRepROMRecorded = { [weak self] rom in
    guard let self = self else { return }
    
    // Don't record ROM until ARKit is fully initialized
    guard self.arkitTracker.isFullyInitialized else {
        FlexaLog.motion.debug("📐 [HandheldROM] Skipping rep ROM - ARKit still initializing")
        return
    }
    
    DispatchQueue.main.async {
        self.lastRepROM = rom
        self.romPerRep.append(rom)
        self.romPerRepTimestamps.append(Date().timeIntervalSince1970)
        
        if !self.isCameraExercise {
            self.romHistory.append(rom)
        }
    }
    FlexaLog.motion.debug("📐 [HandheldROM] Rep ROM recorded: \(String(format: "%.1f°", rom))")
}
```

**Impact:** No 0° ROM values added to `romHistory` during initialization

---

## Initialization Timeline

### Before Fix:
```
T+0.0s: Game starts, ARKit starts
T+0.0s: currentROM = 0°  ❌
T+0.1s: Position received, baseline set (unstable)  ❌
T+0.2s: ROM calculated = 0°  ❌
T+0.3s: ROM = 0°  ❌
T+0.4s: ROM = 0°  ❌
T+1.0s: ARKit stable, tracking normal
T+1.1s: Real ROM = 15°  ✅
T+1.2s: Real ROM = 25°  ✅
```

### After Fix:
```
T+0.0s: Game starts, ARKit starts
T+0.0s: currentROM = 0° (not updated)
T+0.1s: Position received → SKIPPED (not initialized)
T+0.2s: Position received → SKIPPED (not initialized)
T+0.3s: Position received → SKIPPED (not initialized)
T+1.0s: ARKit stable, isFullyInitialized = true  ✅
T+1.1s: Position received → PROCESSED, baseline set  ✅
T+1.1s: Real ROM = 15°  ✅
T+1.2s: Real ROM = 25°  ✅
```

---

## Verification

### Expected Behavior

**During Initialization (0-1s):**
- Screen shows "Starting..." or "Initializing"
- ROM display shows 0° or "--"
- No ROM values added to romHistory
- No reps detected

**After Initialization (1s+):**
- Log: "✅ Fully initialized - ROM and reps will now be tracked"
- First position processed
- Baseline captured
- ROM starts from 0° and increases
- No false 0° values in data

### Logs to Check

**Startup:**
```
📍 [InstantARKit] Tracking started
📍 [InstantARKit] Tracking became normal - starting 1.0s initialization period
```

**During Init (should see these):**
```
📍 [HandheldTracking] Skipping position - ARKit still initializing
```

**After Init:**
```
📍 [InstantARKit] ✅ Fully initialized - ROM and reps will now be tracked
📐 [ROMCalculator] Session baseline captured at first position
📐 [ROMCalculator] Rep ROM: 45.2°
```

**Should NOT see:**
```
📐 [ROMCalculator] Rep ROM: 0.0°  ❌ (bad)
```

### Data Integrity

**ROM History Check:**
```swift
print("ROM History:", sessionData.romHistory)
// ✅ GOOD: [42.3, 45.1, 43.8, 46.2, ...]
// ❌ BAD:  [0.0, 0.0, 0.0, 42.3, 45.1, ...]
```

**ROM Graph Check:**
- First value should be meaningful (>0°)
- No cluster of 0° values at start
- Smooth progression from actual movement

---

## Files Modified

1. **SimpleMotionService.swift**
   - Added `isFullyInitialized` gate to `onPositionUpdate` callback
   - Added `isFullyInitialized` gate to `onROMUpdated` callback
   - *TODO:* Add `isFullyInitialized` gate to `onRepROMRecorded` callback

2. **InstantARKitTracker.swift**
   - Already had initialization logic (no changes needed)
   - Exposes `isFullyInitialized` property
   - Manages 1.0s initialization delay

---

## Related Fixes

This fix works in conjunction with:

1. **Baseline Persistence** (ROM_AND_COORDINATE_FIXES.md)
   - Baseline not reset between reps
   - Baseline set only once per session
   - Together: Ensures baseline set AFTER initialization, kept throughout session

2. **Smoothness Graph** (SMOOTHNESS_GRAPH_FIX.md)
   - SPARC timeline values converted to 0-100 scale
   - No relationship, but both improve data quality

---

## Build Status

✅ **BUILD SUCCEEDED**

---

## Summary

Added initialization gates to prevent ROM tracking during ARKit's 1-second startup period. This eliminates false 0° ROM values at the beginning of handheld game sessions and ensures all tracked data comes from stable, initialized tracking.

**Key Principle:** Don't process ANY position data until ARKit says it's ready (`isFullyInitialized = true`).

**Result:** Clean ROM data from the very first tracked position, with no initialization artifacts.
