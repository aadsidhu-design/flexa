# Handheld ROM Calculation - Simple & Clear

**Date**: October 6, 2025  
**Requirement**: Exactly what the user described - track, convert, measure, reset

---

## The Simple Truth

**For ONE rep:**
1. Track phone in 3D space (ARKit collects positions)
2. Rep detected → Take ALL the tracking data from that rep
3. Put it into 2D (project to remove one dimension)
4. Average/smooth the 2D arc to make it nice
5. Get arc length from the WHOLE 2D path
6. Use arc length formula: `angle = arcLength / armRadius`
7. Reset tracking for next rep

That's it. No peaks, no segments, no complexity.

---

## The Code (Exactly As User Described)

```swift
func calculateROMAndReset() -> Double {
    // Step 1: Get ALL 3D positions tracked during this ONE rep
    let positions3D = rawPositions  // Collected by ARKit
    
    // Step 2: Convert to 2D (project to optimal plane)
    let plane = findOptimalProjectionPlane(positions3D)
    var positions2D = positions3D.map { projectTo2D($0, plane) }
    
    // Step 3: Smooth the 2D arc to make it nice (optional)
    // Simple moving average removes sensor jitter
    if positions2D.count >= 3 {
        var smoothed = [positions2D[0]]  // Keep first
        for i in 1..<(positions2D.count - 1) {
            let avg = (positions2D[i-1] + positions2D[i] + positions2D[i+1]) / 3.0
            smoothed.append(avg)
        }
        smoothed.append(positions2D.last!)  // Keep last
        positions2D = smoothed
    }
    
    // Step 4: Get arc length from WHOLE 2D path
    var arcLength = 0.0
    for i in 1..<positions2D.count {
        arcLength += distance(positions2D[i], positions2D[i-1])
    }
    
    // Step 5: Use arc length formula
    let angle = arcLength / armRadius
    let rom = angle * 180 / π
    
    // Step 6: Reset for next rep
    rawPositions.removeAll()
    
    return rom
}
```

---

## Visual Example

### Rep 1: Pendulum Swing

```
3D Space (ARKit tracking):
    •─•─•─•─•─•─•─•─•─•  (10 positions collected)
    
↓ Project to 2D
    
2D Plane:
    Start •───•───•───•───• Peak (nice smooth arc)
    
↓ Calculate arc length
    
Arc = 0.45m (sum of all segments)
Arm Radius = 0.67m
ROM = (0.45 / 0.67) × 180/π = 38.4°

↓ Reset
    
Ready for Rep 2 (positions cleared)
```

---

## Why Smoothing Helps

### Without Smoothing (Raw ARKit Data):
```
•──•──•──•
     ↑ jitter!
```
Arc length might include tiny zigzags from sensor noise

### With Smoothing:
```
•─────•─────•
  smooth curve
```
Arc length represents the actual movement path

---

## The Formula

```
arc = radius × angle (in radians)

Therefore:
angle = arc / radius

Convert to degrees:
angle_degrees = (arc / radius) × (180 / π)
```

**Example**:
- Arc length: 0.45m
- Arm radius: 0.67m (arm length 0.52m + grip offset 0.15m)
- Angle: 0.45 / 0.67 = 0.671 radians
- ROM: 0.671 × 180 / π = 38.4°

---

## What Each Part Does

### ARKit Session
**Purpose**: Track phone position in 3D space  
**Output**: Array of 3D positions (SIMD3<Double>)  
**Frequency**: ~60Hz (every frame)  
**Stored in**: `rawPositions` array

### Projection to 2D
**Purpose**: Remove one dimension to get a clean plane  
**Method**: PCA (Principal Component Analysis) finds optimal plane  
**Why**: Movement is mostly in one plane, reduces noise

### Smoothing
**Purpose**: Remove sensor jitter, make arc nice  
**Method**: Moving average (window size 3)  
**Why**: ARKit can have small jitters, smoothing gives cleaner arc

### Arc Length Calculation
**Purpose**: Measure total distance along the path  
**Method**: Sum of all segment lengths  
**Formula**: `Σ distance(point[i], point[i-1])`

### Conversion to Angle
**Purpose**: Turn arc length into ROM angle  
**Method**: Arc length formula (geometry)  
**Formula**: `angle = arcLength / armRadius × 180/π`

---

## Rep Detection Flow

```
User swings phone
       ↓
ARKit tracks: pos1, pos2, pos3, ... posN
       ↓
IMU detects direction reversal
       ↓
"Rep detected!" signal
       ↓
calculateROMAndReset() called
       ↓
Takes ALL positions (pos1 to posN)
       ↓
Projects to 2D
       ↓
Smooths the arc
       ↓
Calculates arc length
       ↓
Converts to ROM angle
       ↓
Clears positions for next rep
       ↓
Ready for Rep 2
```

---

## No More:

❌ Peak detection  
❌ Segmentation  
❌ Chord length calculations  
❌ Complex trigonometry  
❌ Multiple ROM calculations per rep  

---

## Just:

✅ Collect 3D positions during rep  
✅ Project to 2D  
✅ Smooth the arc  
✅ Measure arc length  
✅ Convert to angle  
✅ Reset for next rep  

---

## Log Output

What you'll see in logs:
```
📐 [ROM-Arc] 206 points → 204 smoothed, Arc=0.234m, Radius=0.67m → ROM=20.0°
🔄 [Universal3D] Position array reset for next rep
```

This tells you:
- Raw points collected: 206
- Points after smoothing: 204
- Measured arc length: 0.234m
- Arm radius used: 0.67m
- Final ROM: 20.0°

---

## Summary

The system does **exactly** what was described:
1. Track phone in 3D for one rep ✅
2. Rep detected → take all tracking data ✅
3. Put into 2D ✅
4. Average/smooth to make nice arc ✅
5. Get arc length ✅
6. Use arc length formula ✅
7. Reset for next rep ✅

No complexity. Just clean geometric measurement.

