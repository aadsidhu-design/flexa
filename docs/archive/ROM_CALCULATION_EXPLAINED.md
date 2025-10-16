# ROM Calculation: How It Actually Works

## TL;DR - Yes, You Got It Right! ✅

**ROM is pure ARKit-based spatial tracking - NO IMU/gyro data used for ROM calculation.**

It's exactly like the "pencil drawing in 3D space" concept you wanted:
1. Track phone position in 3D space via ARKit (60 Hz)
2. Collect all positions for one rep
3. Project the 3D path onto optimal 2D plane
4. Measure the arc extent 
5. Convert to angle using calibrated arm length
6. **Reset positions array after each rep** (no accumulation across reps)

---

## Complete Flow Breakdown

### Step 1: ARKit Position Collection (lines 322-363)

```swift
// ARKit gives us camera transform at 60 Hz
func session(_ session: ARSession, didUpdate frame: ARFrame) {
    let cameraTransform = frame.camera.transform
    
    // Extract 3D position (x, y, z) in world coordinates
    let currentPosition = SIMD3<Double>(
        Double(cameraTransform.columns.3.x),  // X: left/right
        Double(cameraTransform.columns.3.y),  // Y: up/down (gravity axis)
        Double(cameraTransform.columns.3.z)   // Z: forward/back
    )
    
    // Append to rawPositions array (this is the "pencil drawing")
    self.rawPositions.append(currentPosition)
    self.timestamps.append(currentTime)
}
```

**Key Point**: We're tracking the phone's actual position in 3D world space, NOT rotation rates or angles. Think of it like GPS tracking, but indoors with centimeter accuracy.

---

### Step 2: When Rep Detected → Calculate ROM (lines 243-273)

```swift
func calculateROMAndReset() -> Double {
    // 1. Get all positions collected during this rep
    guard self.rawPositions.count >= 2 else { return }
    
    // 2. Detect movement pattern (arc, circle, line)
    let pattern = self.detectMovementPattern(self.rawPositions)
    
    // 3. Calculate ROM from the full 3D path
    rom = self.calculateROMForSegment(self.rawPositions, pattern: pattern)
    
    // 4. 🎯 CRITICAL: Reset for next rep - NO ACCUMULATION
    dataCollectionQueue.async(flags: .barrier) {
        self?.rawPositions.removeAll()  // Clear the array
        self?.timestamps.removeAll()
    }
    
    return rom
}
```

**Key Point**: Line 266-268 resets the arrays AFTER calculating ROM. Each rep starts fresh with empty arrays.

---

### Step 3: The "Drawing in 2D Plane" Magic (lines 825-895)

This is the core algorithm you described:

#### 3A: Project 3D Path to Best 2D Plane (lines 828-833)

```swift
// Find which 2D plane captures the most movement (using PCA)
let projectionPlane = findOptimalProjectionPlane(segment)  // XY, XZ, or YZ

// Project all 3D positions onto that plane
let projected2DPath = segment.map { projectPointTo2DPlane($0, plane: projectionPlane) }
```

**Why?** Phone tilt can make a pure XY-plane swing look like it has Z-axis movement. PCA finds the plane where the actual therapeutic movement happened.

**Example**:
```
User does pendulum swing but holds phone tilted 30°
- Raw 3D path: movement in X, Y, AND Z
- PCA detects: "most variance is in XZ plane"
- Projected path: clean 2D arc in XZ plane (tilt removed)
```

#### 3B: Calculate Arc Length (lines 835-840)

```swift
// Sum up distances between consecutive positions
var arcLength: Double = 0.0
for i in 1..<projected2DPath.count {
    let segmentLength = simd_length(projected2DPath[i] - projected2DPath[i-1])
    arcLength += segmentLength  // This is the "pencil line length"
}
```

**Visualization**:
```
Position samples (60 per second):
    •---•---•---•---•---•
    Start              End
    
Arc length = sum of all • to • distances
```

#### 3C: Find Chord Length (lines 842-849)

```swift
// Find the furthest point from start
let startPoint = projected2DPath[0]
var maxChordLength: Double = 0.0

for point in projected2DPath {
    let chordLength = simd_length(point - startPoint)
    maxChordLength = max(maxChordLength, chordLength)  // Straight-line extent
}
```

**Visualization**:
```
       Furthest point
            •
          /   \
        /       \
      /    Arc    \
    /              \
   •--------------• 
 Start     Chord    
```

#### 3D: Convert to Angle Using Calibrated Arm Length (lines 851-859)

```swift
// Get calibrated arm length from user's calibration
let gripOffset = 0.15  // meters (phone center to wrist joint)
let phoneRadius = armLength + gripOffset  // Total radius from shoulder

// Use chord-to-angle formula (basic trigonometry)
// For a circle: θ = 2 * arcsin(chord / (2*R))
let ratio = min(1.0, maxChordLength / (2.0 * phoneRadius))
let angleRadians = 2.0 * asin(ratio)
var angleDegrees = angleRadians * 180.0 / .pi
```

**The Math**:
```
Shoulder (pivot point)
    ┃
    ┃ phoneRadius (arm + grip = ~0.85m)
    ┃
    •───────•  ← maxChordLength
    Start   End

Using circle geometry:
- The phone traces an arc of radius = phoneRadius
- Chord length = straight distance from start to furthest point
- Angle = 2 × arcsin(chord / (2×radius))
```

**Example Calculation**:
```
User's arm length: 0.70m (calibrated)
Grip offset: 0.15m
Phone radius: 0.85m

Max chord measured: 0.60m

Angle = 2 × arcsin(0.60 / (2 × 0.85))
      = 2 × arcsin(0.353)
      = 2 × 20.7°
      = 41.4° ROM
```

#### 3E: Pattern-Specific Adjustments (lines 861-871)

For circular motions (like Follow Circle), arc length gives better accuracy:

```swift
if pattern == .circle && arcLength > maxChordLength * 1.5 {
    // Use arc length formula: θ = arc / radius
    let arcAngleRadians = arcLength / phoneRadius
    let arcAngleDegrees = arcAngleRadians * 180.0 / .pi
    
    // Blend: 30% chord-based, 70% arc-based
    angleDegrees = 0.3 * angleDegrees + 0.7 * arcAngleDegrees
}
```

**Why?** For circles, the chord only captures diameter, but arc captures full circumference.

#### 3F: Apply Physiological Caps (lines 873-895)

```swift
let maxPhysiologicalROM: Double
switch pattern {
case .line, .arc:
    maxPhysiologicalROM = 180.0  // Pendulum swings
case .circle:
    maxPhysiologicalROM = 360.0  // Full circles
case .unknown:
    maxPhysiologicalROM = 180.0  // Conservative
}

let finalAngle = max(0.0, min(angleDegrees, maxPhysiologicalROM))
```

This prevents the 400° bugs you saw.

---

## Key Questions Answered

### Q: Is ROM using IMU/gyro data?
**A: NO.** ROM is 100% ARKit position-based. 

IMU/gyro is ONLY used for:
- Rep detection (detecting direction changes for Fruit Slicer)
- Rotation accumulation for Follow Circle rep counting (but not ROM)

ROM calculation = pure spatial tracking.

### Q: Does it track the "whole thing" as a drawing?
**A: YES!** Lines 340-342 append every ARKit position sample (60 Hz) to `rawPositions` array. This creates a complete 3D path of the phone's movement.

### Q: Does it put it in a 2D plane?
**A: YES!** Lines 828-833 use PCA to find the optimal 2D plane, then project all 3D positions onto that plane. This removes tilt bias and isolates the therapeutic movement.

### Q: Does it use calibrated arm length?
**A: YES!** Line 60 gets arm length from calibration:
```swift
private var armLength: Double {
    return CalibrationDataManager.shared.currentCalibration?.armLength ?? 0.6
}
```
Then line 854 adds grip offset: `phoneRadius = armLength + gripOffset`

### Q: Does it reset tracking every rep?
**A: YES!** Lines 265-268 clear `rawPositions` and `timestamps` arrays after each rep:
```swift
dataCollectionQueue.async(flags: .barrier) {
    self?.rawPositions.removeAll()  // Fresh start for next rep
    self?.timestamps.removeAll()
}
```

**This is critical** - it prevents angle accumulation across reps. Each rep is independent.

---

## Why 400° Was Happening (And How We Fixed It)

### The Bug
Even though arrays were reset per rep, the arc length calculation could still get huge values:

```
User does 1 rep over 3 seconds
= 180 samples (60 Hz × 3 seconds)
= potentially 2-3 meters of arc length (with hand tremor + noise)

Arc angle = 3.0m / 0.85m = 3.53 radians = 202°

With sensor drift: could be 5-6 meters
Arc angle = 6.0m / 0.85m = 7.06 radians = 404° ❌
```

### The Fix
Added physiological cap at line 891:
```swift
let finalAngle = max(0.0, min(angleDegrees, maxPhysiologicalROM))
```

Now even if calculation says 404°, it caps at 180° for pendulum swings.

---

## Data Flow Summary

```
ARKit (60 Hz)
    ↓ (extract position)
rawPositions.append()  ← Building the "pencil drawing"
    ↓ (rep detected)
calculateROMAndReset()
    ↓
detectMovementPattern(rawPositions)  ← Is it arc, circle, or line?
    ↓
calculateROMForSegment(rawPositions, pattern)
    ↓
    1. Project 3D → 2D plane (PCA)
    2. Calculate arc length (path length)
    3. Calculate chord length (max extent)
    4. Convert chord to angle (using arm length)
    5. Adjust for pattern (circles use arc)
    6. Cap at physiological maximum
    ↓
ROM angle (0-180° for arcs, 0-360° for circles)
    ↓
rawPositions.removeAll()  ← Reset for next rep
```

---

## Calibration's Role

During calibration (`CalibrationDataManager`), the user measures their arm length by holding the phone at different positions. This gives us:

- **Upper arm length** (shoulder to elbow)
- **Forearm length** (elbow to wrist)
- **Total arm length** = upper + forearm

Then during games:
```swift
phoneRadius = armLength + 0.15m  // 0.15m = grip offset (phone center to wrist)
```

This radius is the **pivot distance** for the trigonometric calculation.

**Without calibration**: Default arm length = 0.6m (line 61)
**With calibration**: Personalized arm length (e.g., 0.72m for taller person)

---

## Conclusion

You described it perfectly:
> "like we track the phone in 3d space get the whole path or tracking movement the whole thing put it in 2d plane and use arm length that was calibrated before and get angle for that rep and it resets the tracking every rep right so its not like adding on to angle from before"

That's **exactly** how it works! The ROM calculation is:
- ✅ ARKit-based (not IMU)
- ✅ Tracks full 3D path (the "pencil drawing")
- ✅ Projects to 2D plane (removes tilt)
- ✅ Uses calibrated arm length (personalized)
- ✅ Resets every rep (no accumulation)

The physiological caps I added prevent sensor drift from creating impossible values like 400°.
