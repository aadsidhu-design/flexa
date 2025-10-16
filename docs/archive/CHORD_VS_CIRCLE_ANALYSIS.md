# Chord Measurement for Circle Game - Is It Accurate?

## What Is Chord?

**Chord** = straight-line distance from START point to FURTHEST point

## Circle Game Scenario

User makes a complete circle:

```
        Top (furthest from start)
            •
          /   \
        /       \
      /           \
    •             •
  Start         (halfway)
      \           /
        \       /
          \   /
            •
         Bottom
```

**Chord length** = distance from Start → Top = **diameter of the circle**

## The Problem

For a circle, chord only measures the **diameter**, not the full **circumference**.

### Example:

User makes a 30cm diameter circle:

**Chord method:**
- Start → Top = 0.30m (diameter)
- ROM = 2 × arcsin(0.30 / (2 × 0.85)) = 2 × arcsin(0.176) = 20.3°

**Reality:**
- User's shoulder traveled through 360° of rotation
- But chord only captures the diameter extent (20°)

### Is This Wrong?

**It depends on what ROM means for circular motion:**

**Option A: ROM = Angular displacement of shoulder joint**
- User does full circle = shoulder rotates 360°
- Chord captures only ~20° (diameter)
- **WRONG** ❌

**Option B: ROM = Maximum reach distance from center**
- ROM measures how far the arm extends from body
- A 30cm circle = arm extended 15cm from center point
- This is actually what chord measures (diameter = 2 × radius)
- **CORRECT** ✅

## What Should We Do Instead?

### Option 1: Keep Chord (Current)
**Pros:**
- Simple, consistent across all games
- Measures shoulder extension range
- Physiologically meaningful (how far arm reaches)

**Cons:**
- Doesn't capture full rotational ROM for circles
- User makes big circle, gets "small" ROM value

### Option 2: Use Arc Length for Circles Only
**Pros:**
- Captures full circular motion (circumference)
- User makes full circle, ROM reflects 360° motion

**Cons:**
- Adds back complexity (different logic per game)
- Arc length can accumulate errors over time
- Not consistent with pendulum games

### Option 3: Hybrid - Use Chord but Scale for Circles
**Pros:**
- Keep chord simplicity
- Scale up for circles: ROM = chord × π (approximately)
- Reflects that circular motion = continuous rotation

**Cons:**
- Still adds game-specific logic
- Arbitrary scaling factor

## My Recommendation

**For Follow Circle specifically, chord is NOT accurate for measuring ROM.**

Here's why:
- ROM in physical therapy = **angular range of motion**
- For circles, the shoulder continuously rotates through ~360°
- Chord only measures static extent (~diameter), not rotation

**Solution: Use different ROM calculation for Follow Circle**

```swift
// In calculateROMForSegment:
if currentGameType == .followCircle {
    // For circles, use circumference-based ROM
    // Approximate circle circumference from chord
    let circleRadius = maxChordLength / 2
    let circumference = 2 * .pi * circleRadius
    let arcAngleRadians = circumference / phoneRadius
    let angleDegrees = arcAngleRadians * 180.0 / .pi
    return min(angleDegrees, 360.0)  // Cap at 360° for full circle
} else {
    // For pendulum/arc movements, use chord
    // ... existing code
}
```

## Visual Comparison

### Fruit Slicer (Pendulum):
```
Start → → → → → Peak → → → → → Back
|________________|
     Chord (accurate for ROM)
```
**Chord = accurate** because ROM = peak angle reached

### Follow Circle:
```
      •
    /   \
   •  →  • (circumference path)
    \   /
      •
   |___|
   Chord (only diameter, NOT full rotation)
```
**Chord = NOT accurate** because ROM should reflect full 360° rotation

## The Real Question

**What does ROM mean for Follow Circle game?**

1. **If ROM = shoulder extension range** (how far arm extends):
   - Chord is correct (measures diameter/reach)
   
2. **If ROM = angular motion range** (how much shoulder rotates):
   - Need arc length or circumference (measures rotation)

**For physical therapy, ROM typically means #2 (angular motion).**

Therefore, for Follow Circle, we should use arc/circumference-based calculation.
