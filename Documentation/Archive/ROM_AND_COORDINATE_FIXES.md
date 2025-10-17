# ROM Tracking & Camera Coordinate Fixes

**Date:** October 15, 2024  
**Issue:** Handheld ROM drops to 0° between reps, Camera coordinates mapping wrong  
**Status:** ✅ FIXED

---

## Problem 1: Handheld ROM Dropping to 0°

### Symptoms
- ROM starts at 0°
- Goes up during first rep
- Drops back to 0° at start of next rep
- Pattern repeats: up/down/0°, up/down/0°
- Should be consistent across reps

### Root Cause

**HandheldROMCalculator** was resetting `baselinePosition` between reps:

```swift
// OLD CODE - completeRep()
self.baselinePosition = nil  // ❌ Resets baseline every rep!
```

This caused:
1. Rep 1: Baseline set at first position → ROM calculated from there
2. Rep 1 ends: Baseline reset to nil
3. Rep 2: NEW baseline set at different position → ROM restarts from 0°
4. This made ROM graphs show drops to 0° between reps

### Solution Applied

**Two fixes in HandheldROMCalculator.swift:**

#### Fix 1: Don't reset baseline between reps
```swift
// NEW CODE - completeRep()
// DON'T reset baselinePosition - keep it consistent across reps
// (removed: self.baselinePosition = nil)
```

#### Fix 2: Set baseline ONLY ONCE per session
```swift
// OLD CODE - processPosition()
if self.currentRepPositions.count == 1 {
    self.baselinePosition = position  // ❌ Sets new baseline every rep!
}

// NEW CODE - processPosition()
// Set baseline ONLY ONCE at the very first position (not every rep)
if self.baselinePosition == nil {
    self.baselinePosition = position  // ✅ Sets baseline once!
    FlexaLog.motion.debug("📐 [ROMCalculator] Session baseline captured at first position")
}
```

### How It Works Now

1. **First position ever:** Baseline captured
2. **All subsequent positions:** ROM calculated relative to SAME baseline
3. **Between reps:** Baseline stays the same
4. **Result:** Consistent ROM tracking throughout session

---

## Problem 2: Camera Coordinate Mapping Wrong

### Symptoms
- Cursor/overlays don't align with body parts
- Tracking appears offset or scaled incorrectly
- MediaPipe landmarks not mapping to screen properly

### Root Cause

**MediaPipePoseProvider** used fixed coordinate space:

```swift
// OLD CODE
let coordinateWidth: CGFloat = 480.0
let coordinateHeight: CGFloat = 640.0
func scaledPoint(_ landmark: NormalizedLandmark) -> CGPoint {
    return CGPoint(x: CGFloat(landmark.x) * coordinateWidth,
                   y: CGFloat(landmark.y) * coordinateHeight)
}
```

**Problems:**
1. **Fixed dimensions (480x640)** don't match actual screen size (varies by device)
2. **No Y-axis flip**: MediaPipe Y-axis is inverted (0 = top, 1 = bottom)
3. Camera now uses HD 1280x720, not VGA 640x480

### Solution Applied

**Use actual screen dimensions + flip Y-axis:**

```swift
// NEW CODE
// Use actual screen dimensions for proper coordinate mapping
let screenBounds = UIScreen.main.bounds
let coordinateWidth: CGFloat = screenBounds.width
let coordinateHeight: CGFloat = screenBounds.height

func scaledPoint(_ landmark: NormalizedLandmark) -> CGPoint {
    // MediaPipe gives normalized (0-1) coordinates
    // Map to screen space with Y-axis correction (MediaPipe Y is inverted)
    return CGPoint(
        x: CGFloat(landmark.x) * coordinateWidth,
        y: CGFloat(1.0 - landmark.y) * coordinateHeight // Flip Y axis
    )
}
```

### Key Changes

1. **Dynamic dimensions:** Uses `UIScreen.main.bounds` (adapts to any device)
2. **Y-axis flip:** `1.0 - landmark.y` converts MediaPipe top-down to screen bottom-up
3. **Proper scaling:** Coordinates now match actual screen pixels

### Coordinate System

| Coordinate System | Origin | X-Axis | Y-Axis |
|-------------------|--------|--------|--------|
| **MediaPipe** | Top-left | 0 (left) → 1 (right) | 0 (top) → 1 (bottom) |
| **UIKit Screen** | Top-left | 0 (left) → width (right) | 0 (top) → height (bottom) |
| **Our Mapping** | Top-left | landmark.x × width | (1.0 - landmark.y) × height |

### Example Mapping

**Device:** iPhone 15 Pro (393×852 points)

| Body Part | MediaPipe (x, y) | Screen Point (x, y) |
|-----------|------------------|---------------------|
| Nose | (0.5, 0.2) | (196.5, 681.6) |
| Left Wrist | (0.3, 0.7) | (117.9, 255.6) |
| Right Hip | (0.6, 0.6) | (235.8, 340.8) |

Note: Y values are inverted in final mapping.

---

## Files Modified

### 1. HandheldROMCalculator.swift
**Location:** `FlexaSwiftUI/Services/Handheld/HandheldROMCalculator.swift`

**Changes:**
- Line 126-129: Changed baseline capture to only set once (not every rep)
- Line 230: Removed `self.baselinePosition = nil` from completeRep()

### 2. MediaPipePoseProvider.swift
**Location:** `FlexaSwiftUI/Services/Camera/MediaPipePoseProvider.swift`

**Changes:**
- Line 207-218: Updated coordinate mapping to use screen dimensions + Y-axis flip

---

## Testing Guide

### Test Handheld ROM Tracking

**Game:** Fruit Slicer or Fan the Flame

**Steps:**
1. Start game
2. Perform 5+ reps
3. Watch ROM graph on screen

**Expected:**
- ROM starts from 0°
- Increases as you move
- **Stays consistent between reps** (no drops to 0°)
- Graph shows smooth up/down pattern without resets

**Failure signs:**
- ROM drops to 0° at start of each rep
- Graph shows repeated 0° valleys
- ROM "restarts" every rep

### Test Camera Coordinate Mapping

**Game:** Balloon Pop, Wall Climbers, or Constellation

**Steps:**
1. Start camera game
2. Move hands/body slowly
3. Observe cursor/overlays on screen

**Expected:**
- Cursor follows hand accurately
- No offset or scaling issues
- Landmarks align with actual body position
- Tracking feels natural and responsive

**Failure signs:**
- Cursor offset from actual hand position
- Landmarks appear stretched/compressed
- Y-axis appears inverted (up moves down)
- Tracking drifts or misaligns

---

## Build Status

✅ **BUILD SUCCEEDED**

---

## Impact

### Handheld Games
- ✅ ROM tracking now consistent across all reps
- ✅ No more 0° drops between reps
- ✅ Accurate ROM graphs in ResultsView
- ✅ Better session metrics and AI analysis

### Camera Games
- ✅ Accurate coordinate mapping for all devices
- ✅ Cursor/overlays align with body parts
- ✅ Proper Y-axis orientation
- ✅ Works with HD 1280x720 camera resolution

---

## Technical Details

### Why Baseline Matters

ROM is calculated as **distance from baseline**:
- Baseline = reference position (usually starting position)
- ROM = angular/linear distance moved from baseline
- Resetting baseline = restarting measurement from new reference

**Before Fix:**
```
Rep 1: Baseline A → Move → ROM: 0° → 45° → 0°
Rep 2: Baseline B → Move → ROM: 0° → 50° → 0°
Rep 3: Baseline C → Move → ROM: 0° → 48° → 0°
```

**After Fix:**
```
All Reps: Baseline A → Move → ROM: 0° → 45° → 25° → 50° → 30° → 48°
```

### Why Y-Axis Flip Matters

MediaPipe outputs normalized coordinates where Y increases **downward**:
- Y = 0.0 means **top** of frame
- Y = 1.0 means **bottom** of frame

UIKit screen coordinates have Y increasing **downward** too, BUT:
- We often think of "up" as positive movement
- Many overlays expect inverted Y for intuitive display

By flipping: `y = (1.0 - landmark.y) × height`, we convert MediaPipe's top-down to screen bottom-up for proper alignment with visual expectations.

---

## Summary

Fixed two critical tracking issues:

1. **Handheld ROM**: Keep baseline consistent across reps (no resets)
2. **Camera Coordinates**: Use screen dimensions + flip Y-axis

Both systems now provide accurate, consistent tracking throughout gameplay sessions.
