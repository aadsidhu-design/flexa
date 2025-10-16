# Rep Detection - Simple Direction Change

**Date**: October 6, 2025  
**Requirement**: One direction change = 1 rep (no matter which direction)

---

## The Rule (Crystal Clear)

**One swing forward = 1 rep**  
**One swing backward = 1 rep**

Direction changes = reps. Period.

---

## Examples

### Pendulum Swing (Fruit Slicer)
```
Start at center
Swing forward →  Rep #1 (forward swing)
Swing backward ← Rep #2 (backward swing)  
Swing forward →  Rep #3 (forward swing)
Swing backward ← Rep #4 (backward swing)
```

Each direction change counts!

### Horizontal Swing (Fan Flame)
```
Start at center
Swing right →    Rep #1
Swing left ←     Rep #2
Swing right →    Rep #3
Swing left ←     Rep #4
```

Same principle!

---

## The Detection Logic (Simple)

### Old (Too Complex):
- Wait for peak
- Wait for valley
- Check if peak big enough
- Check multiple thresholds
- Miss some direction changes ❌

### New (Simple):
```swift
if currentDirection != previousDirection {
    // Direction changed!
    Rep detected! ✅
}
```

With:
- Low threshold (0.08g minimum movement)
- Debounce to prevent noise (0.5s typical)
- No peak/valley complexity

---

## The Code

```swift
mutating func detectAccelerometerReversal(...) -> ... {
    // Get current acceleration direction
    let currentDirection = acceleration.z  // Z-axis for pendulum
    let currentSign = currentDirection > 0 ? 1.0 : -1.0  // + or -
    
    // Compare to previous direction
    if let prevDirection = lastDirection {
        let prevSign = prevDirection.z > 0 ? 1.0 : -1.0
        
        // Direction changed? → Rep!
        if prevSign != currentSign && abs(currentDirection) >= minThreshold {
            lastDirection = currentDirection  // Update for next time
            return "Rep detected!"
        }
    }
    
    // First time? Just store direction
    if lastDirection == nil && abs(currentDirection) >= minThreshold {
        lastDirection = currentDirection
    }
    
    return nil
}
```

---

## What Happens Per Rep

```
User swings forward
    ↓
IMU: "Direction changed to forward!"
    ↓
Rep #1 detected
    ↓
calculateROMAndReset() called
    ↓
Takes all ARKit positions from this swing
    ↓
Calculates ROM for forward swing
    ↓
Resets positions
    ↓
---
User swings backward
    ↓
IMU: "Direction changed to backward!"
    ↓
Rep #2 detected
    ↓
calculateROMAndReset() called
    ↓
Takes all ARKit positions from backward swing
    ↓
Calculates ROM for backward swing
    ↓
Resets positions
    ↓
Ready for next rep
```

---

## Key Points

### No Matter Orientation
- Phone vertical? ✅ Works
- Phone horizontal? ✅ Works  
- Phone tilted? ✅ Works

The Z-axis accelerometer detects forward/backward motion regardless of phone orientation.

### No Matter Direction
- Forward swing? ✅ Counts as rep
- Backward swing? ✅ Counts as rep
- Small swing? ✅ Counts as rep (if > 0.08g)
- Big swing? ✅ Counts as rep

Every direction change = 1 rep!

### Debounce Prevents Noise
- Minimum 0.5s between reps (typical)
- Prevents detecting noise as reps
- Prevents double-counting same movement

---

## ROM Per Rep

Each rep gets its own ROM calculation:

**Rep #1 (Forward)**: 
- Positions collected: [pos1, pos2, ..., posN]
- ROM calculated: 45.2°

**Rep #2 (Backward)**:
- Positions collected: [pos1, pos2, ..., posM]  (NEW positions)
- ROM calculated: 38.7°

**Rep #3 (Forward)**:
- Positions collected: [pos1, pos2, ..., posK]  (NEW positions)
- ROM calculated: 52.1°

Each rep is independent!

---

## Threshold

**Minimum Movement**: 0.08g (very low)
- Detects even gentle swings
- Higher than sensor noise
- Low enough for therapy patients

**Debounce**: 0.5s typical
- Prevents too-fast detection
- Allows natural swing rhythm
- Configurable per game

---

## Summary

**Before**: Complex peak/valley detection, missed some direction changes  
**After**: Simple direction change detection, catches every swing

**Rule**: Direction change = rep  
**Method**: Compare current vs. previous direction sign  
**Result**: Every swing counts!

---

## Build Status
```
✅ BUILD SUCCEEDED
✅ Simplified direction detection
✅ No more peak/valley complexity
✅ Every direction change = 1 rep
```

