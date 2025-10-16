# Comprehensive ROM & SPARC Audit - Issues Found

## Critical Issues Identified

### Issue #1: ROM History Being Polluted with Live Updates ⚠️ CRITICAL
**Location**: `SimpleMotionService.swift` - `updateROMFromARKit()`

**Problem**:
```swift
func updateROMFromARKit(_ rom: Double) {
    let validatedROM = validateAndNormalizeROM(rom)
    DispatchQueue.main.async {
        self.currentROM = validatedROM
        if validatedROM > self.maxROM {
            self.maxROM = validatedROM
        }
        
        // ❌ WRONG: This appends EVERY live ROM update to romHistory
        self.romHistory.append(validatedROM)  // Called ~60 times per second!
        
        if !self.isCameraExercise {
            if validatedROM > self.repPeakROM {
                self.repPeakROM = validatedROM
            }
        }
    }
}
```

**Impact**:
- `romHistory` contains thousands of live ROM samples (not per-rep values)
- Graph shows spiky pattern because it's plotting every frame's ROM
- Analyzing view receives bloated ROM data (3600+ values for 1-minute session)
- Per-rep ROM data gets lost in the noise

**Evidence from Logs**:
```
🍎 [ROM Normalize] Fruit Slicer passthrough → ROM=0.0°
🍎 [ROM Normalize] Fruit Slicer passthrough → ROM=0.0°
... (repeated hundreds of times)
🍎 [ROM Normalize] Fruit Slicer passthrough → ROM=180.0°
🍎 [ROM Normalize] Fruit Slicer passthrough → ROM=180.0°
```

This is being called at ~60 Hz, creating a massive array.

---

### Issue #2: Duplicate Data Paths for ROM
**Locations**: Multiple services have overlapping responsibilities

**Problem**:
1. `UnifiedRepROMService` has `romPerRep` array (correct, per-rep data)
2. `SimpleMotionService` has `romPerRep` array (copied from UnifiedRepROMService)
3. `SimpleMotionService` has `romHistory` array (polluted with live data)
4. `Universal3DROMEngine` calculates ROM per segment

**Data Flow**:
```
Universal3DROMEngine
    ↓ (live updates at 60Hz)
updateROMFromARKit()
    ↓ (appends to romHistory)
SimpleMotionService.romHistory (thousands of values)
    ↓
AnalyzingView receives bloated data
    ↓
Graph shows spiky pattern
```

**Correct Flow Should Be**:
```
Universal3DROMEngine
    ↓ (on rep detection only)
UnifiedRepROMService.registerRep()
    ↓ (stores per-rep ROM)
UnifiedRepROMService.romPerRep (one value per rep)
    ↓ (copied to)
SimpleMotionService.romPerRep
    ↓
AnalyzingView (clean per-rep data)
    ↓
Graph shows stable values
```

---

### Issue #3: Live ROM Window Still Accumulating
**Location**: `Universal3DROMEngine.swift` - `updateLiveROMWindow()`

**Problem** (partial fix applied, but needs verification):
The live ROM window accumulates positions over 2.5 seconds. Even with peak detection, if the window isn't pruned correctly, old data can cause issues.

**Current Code**:
```swift
private func updateLiveROMWindow(with position: SIMD3<Double>, timestamp: TimeInterval) {
    liveROMPositions.append(position)
    liveROMTimestamps.append(timestamp)
    
    pruneLiveROMWindow(latestTimestamp: timestamp)  // ← Does this work correctly?
    
    guard liveROMPositions.count >= 8 else { return }
    let pattern = detectMovementPattern(liveROMPositions)
    let rom = calculateLiveROMWithPeakDetection(liveROMPositions, pattern: pattern)
    
    // ❌ This triggers updateROMFromARKit which pollutes romHistory
    DispatchQueue.main.async { [weak self] in
        self?.onLiveROMUpdated?(rom)
    }
}
```

---

### Issue #4: SPARC Calculation Frequency
**Location**: `SPARCCalculationService.swift`

**Problem**: Need to verify SPARC is calculated at correct intervals for handheld games.

**From Logs**:
```
📊 [SPARC] Data point added: t=0.71s value=46.2 total=1
📊 [SPARC] Data point added: t=0.92s value=44.2 total=2
... (every ~0.2 seconds)
```

SPARC is being calculated every ~200ms, which seems correct, but we need to verify:
1. Are calculations based on sufficient data windows?
2. Is SPARC per-rep being stored correctly?
3. Is the SPARC history being polluted like ROM history?

---

### Issue #5: Rep Counting May Be Over-Detecting
**Location**: `UnifiedRepROMService.swift` - Accelerometer direction change detection

**Evidence from Logs**:
```
🎯 [UnifiedRep] ⚠️ Rep #1 [Accelerometer] ROM=0.0°
🎯 [UnifiedRep] ⚠️ Rep #2 [Accelerometer] ROM=0.0°
🎯 [UnifiedRep] ⚠️ Rep #3 [Accelerometer] ROM=24.2°
🎯 [UnifiedRep] ⚠️ Rep #4 [Accelerometer] ROM=12.2°
```

Many reps detected with 0° or very low ROM. This suggests:
1. Accelerometer is too sensitive to direction changes
2. Noise/jitter being counted as reps
3. Debounce timing may be too short

---

## Required Fixes

### Fix #1: Stop Polluting romHistory with Live Updates
**File**: `SimpleMotionService.swift`

**Change**:
```swift
func updateROMFromARKit(_ rom: Double) {
    let validatedROM = validateAndNormalizeROM(rom)
    
    DispatchQueue.main.async {
        // ✅ Update live display values ONLY (not per-rep data)
        self.currentROM = validatedROM
        if validatedROM > self.maxROM {
            self.maxROM = validatedROM
        }
        
        // ❌ REMOVE THIS LINE - romHistory should only contain per-rep ROM
        // self.romHistory.append(validatedROM)
        
        // ✅ Track peak ROM for current rep window (handheld games only)
        if !self.isCameraExercise {
            if validatedROM > self.repPeakROM {
                self.repPeakROM = validatedROM
            }
        }
    }
}
```

**Rationale**:
- `romHistory` should ONLY be populated when a rep is detected
- Live ROM updates are for display purposes only (currentROM, maxROM)
- Per-rep data comes from UnifiedRepROMService, not live updates

---

### Fix #2: Ensure romHistory Is Only Populated Per-Rep
**File**: `SimpleMotionService.swift`

**Verify** that `romHistory` is ONLY appended to in these scenarios:
1. When `UnifiedRepROMService` publishes a new rep
2. Never from live ROM callbacks

**Add safeguard**:
```swift
// In setupUnifiedRepObservation()
unifiedRepROMService.$romPerRep
    .receive(on: DispatchQueue.main)
    .sink { [weak self] romArray in
        guard let self = self else { return }
        
        // Clear and repopulate romPerRep (this is correct)
        self.romPerRep.removeAll()
        romArray.forEach { self.romPerRep.append($0) }
        
        // ✅ ADD: Ensure romHistory matches romPerRep for handheld games
        if !self.isCameraExercise {
            // For handheld games, romHistory should equal romPerRep
            self.romHistory.removeAll()
            romArray.forEach { self.romHistory.append($0) }
        }
    }
    .store(in: &cancellables)
```

---

### Fix #3: Improve Accelerometer Rep Detection Threshold
**File**: `UnifiedRepROMService.swift`

**Current Issue**: Too many false reps with 0° ROM

**Change**:
```swift
private func detectRepViaAccelReversal(timestamp: TimeInterval) {
    guard let result = imuDetectionState.detectAccelDirectionReversal(
        threshold: currentProfile.repThreshold,
        debounce: currentProfile.debounceInterval,
        lastRepTime: lastRepTime
    ) else { return }
    
    let rom = SimpleMotionService.shared.universal3DEngine.calculateROMAndReset()
    
    // ✅ ADD: Minimum ROM threshold to filter noise
    // Only count as valid rep if ROM is meaningful
    let minimumRepROM: Double = 15.0  // At least 15° of movement
    
    if rom >= minimumRepROM {
        registerRep(rom: rom, timestamp: timestamp, method: "Accelerometer")
    } else {
        FlexaLog.motion.debug("🎯 [UnifiedRep] Rep rejected - ROM too low: \(String(format: "%.1f", rom))° < \(minimumRepROM)°")
        // Still reset the position array to prevent accumulation
        _ = SimpleMotionService.shared.universal3DEngine.calculateROMAndReset()
    }
}
```

---

### Fix #4: Add Minimum ROM to Gyro Detection Too
**File**: `UnifiedRepROMService.swift`

```swift
private func detectRepViaGyroAccumulation(timestamp: TimeInterval) {
    guard let result = imuDetectionState.detectGyroRotationComplete(
        targetRotation: currentProfile.repThreshold,
        debounce: currentProfile.debounceInterval,
        lastRepTime: lastRepTime
    ) else { return }
    
    let rom = SimpleMotionService.shared.universal3DEngine.calculateROMAndReset()
    
    // ✅ ADD: Minimum ROM threshold
    let minimumRepROM: Double = 15.0
    
    if rom >= minimumRepROM {
        registerRep(rom: rom, timestamp: timestamp, method: "Gyro-Accumulation")
    } else {
        FlexaLog.motion.debug("🎯 [UnifiedRep] Rep rejected - ROM too low: \(String(format: "%.1f", rom))° < \(minimumRepROM)°")
    }
}
```

---

### Fix #5: Verify SPARC Calculation Window
**File**: `SPARCCalculationService.swift`

**Check**: Ensure SPARC calculations are based on sufficient data:
- Minimum window: 1.0 second of data
- Maximum window: 3.0 seconds of data
- Update frequency: Every 200ms (current seems correct)

**Verify this code**:
```swift
private func schedulePeriodicSPARCCalculation() {
    sparcTimer?.invalidate()
    sparcTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
        self?.calculateSPARC()
    }
}
```

---

## Testing Plan

### Test #1: ROM History Cleanup
1. Start Fruit Slicer game
2. Do 5 pendulum swings (arm forward → overhead → forward)
3. Check logs for romHistory size
4. **Expected**: romHistory should have exactly 5 values (or 10 if counting forward+back as separate reps)
5. **Before fix**: romHistory would have 3000+ values

### Test #2: Graph Display
1. Complete Fruit Slicer session with 10 reps
2. View Analyzing screen
3. **Expected**: ROM graph shows flat line around 90° (or stable values per rep)
4. **Before fix**: Graph shows wild spikes from 0° → 180° → 0°

### Test #3: Rep Detection Accuracy
1. Do pendulum swings with clear, deliberate movements
2. Count actual movements: 10 swings
3. Check app rep count
4. **Expected**: App shows 10 reps (or 20 if counting bidirectional)
5. **Verify**: No reps with 0° ROM in romPerRep array

### Test #4: SPARC Consistency
1. Complete session with smooth movements
2. Check SPARC history
3. **Expected**: SPARC values should be relatively stable (±5 points)
4. **Verify**: SPARC history matches number of calculations, not per-rep

---

## Summary of Root Causes

1. **Live ROM updates being stored as per-rep data** (Critical)
   - `updateROMFromARKit` appends to `romHistory` at 60Hz
   - Should only update display values, not historical data

2. **No minimum ROM filter for rep detection** (High)
   - 0° ROM reps getting counted
   - Need 15° minimum threshold

3. **Live ROM window accumulation** (Medium - partially fixed)
   - Peak detection added, but callback chain pollutes romHistory

4. **Data architecture confusion** (Medium)
   - Multiple overlapping arrays (romHistory, romPerRep)
   - Need clear separation: live display vs. per-rep storage

## Implementation Priority

1. **IMMEDIATE**: Fix #1 - Remove `romHistory.append()` from `updateROMFromARKit()`
2. **IMMEDIATE**: Fix #2 - Sync romHistory with romPerRep from UnifiedRepROMService
3. **HIGH**: Fix #3 & #4 - Add minimum ROM threshold to rep detection
4. **MEDIUM**: Fix #5 - Verify SPARC calculation windows

All fixes should be applied together for comprehensive solution.
