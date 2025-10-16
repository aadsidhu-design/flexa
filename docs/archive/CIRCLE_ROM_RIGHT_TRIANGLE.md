# Follow Circle ROM - Right Triangle Method

## The Setup

User's **arm points down** (toward floor), they make a **horizontal circle**.

```
        Shoulder (pivot point)
            |
            |
            | L = arm length (long leg/hypotenuse)
            |
            |
            •──────────────•
         Center          Edge
         (below         (circle
        shoulder)      perimeter)
        
            R = circle radius (short leg)
```

## Right Triangle

```
      Shoulder
         |  ╲
         |    ╲ L (arm length)
         |      ╲
         | ROM   ╲
         |________╲
      Center     Edge
         
         R (circle radius)
```

**Right triangle components:**
- **Hypotenuse** = L (arm length)
- **Opposite side** = R (circle radius)
- **Adjacent side** = vertical drop
- **Angle** = ROM (how much arm deviates from vertical)

## The Formula

**sin(ROM) = opposite / hypotenuse**

**sin(ROM) = R / L**

Therefore:

**ROM = arcsin(R / L)**

## Example Calculations

### Small Circle
```
Arm length L = 0.85m
Circle radius R = 0.15m (15cm)

ROM = arcsin(0.15 / 0.85)
    = arcsin(0.176)
    = 10.1°
```

User's arm deviates **10° from vertical** to make a 15cm radius circle.

### Medium Circle
```
Arm length L = 0.85m
Circle radius R = 0.40m (40cm)

ROM = arcsin(0.40 / 0.85)
    = arcsin(0.471)
    = 28.1°
```

User's arm deviates **28° from vertical** to make a 40cm radius circle.

### Large Circle
```
Arm length L = 0.85m
Circle radius R = 0.70m (70cm)

ROM = arcsin(0.70 / 0.85)
    = arcsin(0.824)
    = 55.5°
```

User's arm deviates **56° from vertical** to make a 70cm radius circle.

### Maximum Circle
```
Arm length L = 0.85m
Circle radius R = 0.85m (arm's full length)

ROM = arcsin(0.85 / 0.85)
    = arcsin(1.0)
    = 90°
```

User's arm is **horizontal** (90° from vertical) - maximum possible.

## Implementation

```swift
if currentGameType == .followCircle {
    // Find circle center (average of all positions)
    var centerSum = SIMD2<Double>(0, 0)
    for point in projected2DPath {
        centerSum += point
    }
    let center = centerSum / Double(projected2DPath.count)
    
    // Find max radius (furthest distance from center)
    var maxRadius: Double = 0.0
    for point in projected2DPath {
        let distanceFromCenter = simd_length(point - center)
        maxRadius = max(maxRadius, distanceFromCenter)
    }
    
    // Right triangle: ROM = arcsin(R / L)
    let ratio = min(1.0, maxRadius / armRadius)  // Valid arcsin range
    let angleRadians = asin(ratio)
    let angleDegrees = angleRadians * 180.0 / .pi
    
    // Cap at 90° (arm horizontal is max)
    angleDegrees = min(angleDegrees, 90.0)
}
```

## Why This Makes Sense

**ROM = shoulder angle deviation from rest position**

- Arm hanging down = 0° ROM (rest position)
- Arm slightly out = 10-20° ROM (small circle)
- Arm medium out = 30-50° ROM (medium circle)
- Arm horizontal = 90° ROM (largest possible circle)

This directly measures the **shoulder abduction angle** needed to maintain the circle.

## Comparison to Arc Length Method

**Arc Length Method** (old):
```
Circle circumference = 2πR = 2π × 0.40m = 2.51m
ROM = arc / armLength = 2.51 / 0.85 = 2.95 radians = 169°
```
**Problem**: Reports 169° for a medium circle, but shoulder only moved 28° from vertical!

**Right Triangle Method** (new):
```
Circle radius R = 0.40m
ROM = arcsin(0.40 / 0.85) = 28°
```
**Correct**: Shoulder actually deviated 28° from vertical.

## Physiological Accuracy

The right triangle method gives the **actual shoulder ROM** (angular deviation), not the total path traveled.

For physical therapy:
- ✅ Measures true shoulder abduction angle
- ✅ Matches clinical ROM assessment
- ✅ Capped at 90° (realistic maximum)
- ✅ Smaller circles = smaller ROM (makes sense)
- ✅ Larger circles = larger ROM (makes sense)

## Expected ROM Values

**Follow Circle game:**
- Tiny circle (5cm radius): ~3-5° ROM
- Small circle (15cm radius): ~10-12° ROM
- Medium circle (40cm radius): ~25-30° ROM
- Large circle (70cm radius): ~50-60° ROM
- Maximum circle (85cm radius): ~90° ROM (arm horizontal)

**Much more realistic than 100-360° values from arc length!**
