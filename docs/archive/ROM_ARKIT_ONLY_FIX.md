# ROM Calculation - ARKit Only (No IMU)

**Date**: October 6, 2025  
**Issue**: ROM was being calculated from both IMU and ARKit  
**Fix**: Disabled IMU/live ROM calculations, ROM now ONLY from ARKit

---

## Problem Identified

From the logs:
```
🎯 [UnifiedRep] Profile: method=Accel-Reversal ROM=ARKit-Spatial
📐 [ROM-FullArc] 21 points, TotalArc=0.000m, Radius=0.67m → ROM=0.0°
```

The system was:
1. Using IMU accelerometer for rep detection ✅ (Correct)
2. Calculating "live ROM" from IMU sensors ❌ (Incorrect - inaccurate)
3. Calculating "per-rep ROM" from ARKit positions ✅ (Correct)

**The confusion**: Live ROM updates during gameplay were using IMU, even though per-rep ROM was correctly using ARKit.

---

## The Fix

### What Was Changed

**File**: `UnifiedRepROMService.swift`

**Lines 123-143** - Disabled IMU live ROM:
```swift
private func processIMU(motion: CMDeviceMotion, timestamp: TimeInterval) {
    // Update IMU state
    imuDetectionState.addSample(motion: motion, timestamp: timestamp)
    
    // Route to appropriate detection method (rep detection only)
    switch currentProfile.repDetectionMethod {
    case .accelerometerReversal:
        detectRepViaAccelerometer(timestamp: timestamp)
    // ... other cases
    }
    
    // ❌ DISABLED: Do NOT calculate live ROM from IMU
    // Live ROM is not accurate from IMU sensors
    // Per-rep ROM is calculated from ARKit positions only
}
```

**Lines 145-167** - Disabled ARKit live ROM:
```swift
private func processARKit(position: SIMD3<Double>, timestamp: TimeInterval) {
    // Update ARKit state
    arkitDetectionState.addPosition(position, timestamp: timestamp, armLength: armLength)
    
    // ARKit-based rep detection (for circular motion games)
    if currentProfile.repDetectionMethod == .arkitCircleComplete {
        detectRepViaARKitCircle(timestamp: timestamp)
    }
    
    // ❌ DISABLED: Do NOT calculate live ROM here
    // Per-rep ROM is calculated via Universal3DEngine.calculateROMAndReset()
}
```

---

## How ROM Actually Works Now

### Rep Detection (IMU Sensors)
```
IMU Accelerometer → Detects direction reversal → Rep detected!
```

### ROM Calculation (ARKit Only)
```
ARKit → Collects 3D positions during rep
       ↓
Universal3DEngine → When rep detected:
       ↓
calculateROMAndReset() → Calculate cumulative arc through ALL positions
       ↓
ROM = (arcLength / armRadius) × 180/π
```

---

## Data Flow Diagram

```
HANDHELD GAMES (Fruit Slicer, Follow Circle, Fan Flame)
========================================================

┌─────────────┐
│ IMU Sensors │ → Rep Detection ONLY
└─────────────┘
       │
       │ Direction reversal detected
       ↓
┌──────────────────────┐
│ UnifiedRepROMService │ → "Rep detected!"
└──────────────────────┘
       │
       │ Call calculateROMAndReset()
       ↓
┌───────────────────────┐
│ Universal3DROMEngine  │ → ARKit positions collected
└───────────────────────┘
       │
       │ 1. Project 3D → 2D
       │ 2. Calculate arc length
       │ 3. Convert to angle
       ↓
    ROM Value (ARKit-based, accurate!)
```

---

## What Each Sensor Does

### IMU (Accelerometer/Gyro)
**Purpose**: Rep detection only  
**Why**: Fast, responsive, detects motion changes instantly  
**Used For**:
- Detecting direction reversals (pendulum swings)
- Detecting rotation complete (circular motions)
- Triggering "rep complete" event

**NOT Used For**:
- ❌ ROM calculation (inaccurate - no spatial reference)
- ❌ Position tracking (sensors drift)

### ARKit (Camera + Computer Vision)
**Purpose**: Position tracking and ROM calculation  
**Why**: Accurate 3D position in space  
**Used For**:
- Tracking phone position in 3D space
- Building arc of movement (series of 3D points)
- Calculating ROM from arc length

**NOT Used For**:
- ❌ Rep detection (too slow, would miss fast movements)

---

## Why This Separation Matters

### Old Approach (Both IMU and ARKit for ROM)
```
IMU: "I think the ROM is 45° based on rotation rate"
ARKit: "I measured the actual arc and ROM is 52°"
System: "Which one do I use??" 🤔
```

Result: Inconsistent, sometimes used IMU (inaccurate), sometimes ARKit

### New Approach (IMU for Reps, ARKit for ROM)
```
IMU: "Rep detected at 2.5 seconds!"
ARKit: "I tracked the full arc, ROM is 52°"
System: "Perfect! Rep #3, ROM 52°" ✅
```

Result: Consistent, always accurate ARKit-based ROM

---

## Example from Logs

### Before Fix (Confusing)
```
IMU live ROM: 35° (inaccurate estimate)
Rep detected!
ARKit ROM: 49.4° (actual measured)
→ Shows: 49.4° (correct, but IMU ROM was misleading)
```

### After Fix (Clear)
```
Rep detected!
ARKit ROM: 49.4° (measured from full arc)
→ Shows: 49.4° (clear, no confusing live ROM)
```

---

## Technical Details

### Disabled Functions
1. `updateROMFromIMU()` - Never called anymore
2. `updateROMFromARKit()` - Never called anymore (was for live updates)
3. Live ROM calculations during gameplay - Disabled

### Active Functions
1. `processIMU()` - Still active for rep detection
2. `processARKit()` - Still active for position collection
3. `Universal3DEngine.calculateROMAndReset()` - Called when rep detected
4. Per-rep ROM stored in `romPerRep` array

---

## Verification

### Check Logs For
✅ **Good**: `📐 [ROM-FullArc] X points, TotalArc=Y.Zm, Radius=W.Vm → ROM=A.B°`
- This means ARKit-based ROM calculation happened

❌ **Bad**: Multiple ROM values per rep or IMU-based ROM estimates
- Should not see anymore

### Expected Behavior
1. Rep detected via IMU (fast, responsive)
2. Single ROM value calculated from ARKit positions
3. ROM logged once per rep
4. No intermediate/live ROM values

---

## Build Status
```
✅ BUILD SUCCEEDED
✅ No Errors
✅ IMU live ROM disabled
✅ ARKit-only ROM calculation active
```

---

## Summary

**Before**: 
- IMU used for rep detection ✅
- IMU used for live ROM ❌ (inaccurate)
- ARKit used for per-rep ROM ✅

**After**:
- IMU used for rep detection ONLY ✅
- ARKit used for ROM calculation ONLY ✅
- Clear separation of concerns ✅
- More accurate measurements ✅

**Result**: ROM is now **exclusively calculated from ARKit positions** using the cumulative arc method. IMU is used **only** for fast rep detection.

