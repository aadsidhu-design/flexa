# BlazePose Debug Logging Guide

## Overview

Comprehensive logging has been added to track pose detection, coordinate mapping, and angle calculations in real-time.

## Logging Locations

### 1. BlazePose Provider (`BlazePosePoseProvider.swift`)

**Frequency**: Every 30 frames (~0.5 seconds at 60fps)

**What's Logged**:
- Frame count
- Visibility scores for all key joints (0.0 - 1.0)
  - Left/Right Wrist
  - Left/Right Elbow  
  - Left/Right Shoulder
- 2D normalized coordinates (0-1 range)
  - Wrist positions
  - Elbow positions
- 3D world coordinates (meters)
  - Wrist positions (X, Y, Z)
  - Elbow positions (X, Y, Z)

**Example Output**:
```
👁 [BLAZEPOSE] Frame 180
📊 VISIBILITY:
  L-Wrist: 0.95 | R-Wrist: 0.87
  L-Elbow: 0.72 | R-Elbow: 0.65
  L-Shoulder: 0.88 | R-Shoulder: 0.91
📍 2D COORDS (normalized 0-1):
  L-Wrist: (0.234, 0.567)
  R-Wrist: (0.789, 0.543)
  L-Elbow: (0.312, 0.445)
  R-Elbow: (0.701, 0.432)
🌍 3D WORLD (meters):
  L-Wrist: (-0.123, 0.456, -0.234)
  R-Wrist: (0.145, 0.432, -0.198)
  L-Elbow: (-0.089, 0.234, -0.156)
  R-Elbow: (0.112, 0.221, -0.143)
```

### 2. Coordinate Mapper (`CoordinateMapper.swift`)

**Frequency**: On-demand (set `enableLogging: true`)

**What's Logged**:
- Input normalized coordinates (0-1)
- Screen size
- Raw output before clamping
- Final output after clamping
- Clamping status (if coordinates were out of bounds)

**Example Output**:
```
📍 [CoordinateMapper] Mapping:
  Input (normalized): (0.7234, 0.5432)
  Screen size: 393×852
  Raw output: (284.30, 462.81)
  Final output: (284.30, 462.81)
```

### 3. Game View - Hand Positions (`BalloonPopGameView.swift`)

**Frequency**: Every 60 frames (~1 second at 60fps)

**What's Logged**:
- Screen size
- Active arm (left/right)
- Wrist position (normalized and screen coordinates)
- All joint positions (elbow, shoulder) for both arms
- Final pin position on screen

**Example Output**:
```
🎮 [BalloonPop] Coordinate Mapping (Frame ~180)
📱 Screen Size: 393×852
🫱 Active Arm: Right
📍 Wrist (normalized): (0.723, 0.543)
📍 Wrist (screen): (284.3, 462.8)
📍 L-Elbow: (0.312, 0.445)
📍 R-Elbow: (0.701, 0.432)
📍 L-Shoulder: (0.289, 0.334)
📍 R-Shoulder: (0.734, 0.321)
🎯 Pin Position: (284.3, 462.8)
```

### 4. Game View - Angle Calculations (`BalloonPopGameView.swift`)

**Frequency**: Every 60 frames (~1 second at 60fps)

**What's Logged**:
- Active arm
- Shoulder, elbow, wrist positions (normalized)
- Calculated elbow angle (degrees)
- Previous angle for comparison
- Rep detection state (in position or not)

**Example Output**:
```
📐 [BalloonPop] Angle Calculation:
  Active Arm: Right
  Shoulder: (0.734, 0.321)
  Elbow: (0.701, 0.432)
  Wrist: (0.723, 0.543)
  Calculated Angle: 145.3°
  Last Angle: 132.7°
  In Position: true
```

## How to Use This Logging

### Debugging Tracking Issues

1. **Check Visibility Scores**
   - Should be > 0.1 for tracking to work
   - Lower scores mean joint is occluded or out of frame
   - BlazePose estimates even with low visibility

2. **Verify 2D Coordinates**
   - Should be in 0-1 range
   - X: 0 = left edge, 1 = right edge
   - Y: 0 = top edge, 1 = bottom edge
   - Check if coordinates make sense for where your hand is

3. **Check 3D World Coordinates**
   - In meters relative to hip center
   - X: left (-) to right (+)
   - Y: down (-) to up (+)
   - Z: back (-) to front (+)
   - Typical arm reach: 0.5-0.8 meters

4. **Verify Screen Mapping**
   - Normalized coords should scale correctly to screen size
   - Check if clamping is happening (coordinates out of bounds)
   - Pin position should match wrist screen position

5. **Validate Angle Calculations**
   - Elbow angle should be 0-180°
   - ~180° = straight arm
   - ~90° = bent arm
   - Check if all 3 points (shoulder-elbow-wrist) are present

## Common Issues to Look For

### Issue: Pin not following hand
- Check if wrist visibility > 0.1
- Verify screen mapping is correct
- Check if active arm detection is correct

### Issue: Inverted/rotated tracking
- Check 2D coordinate orientation
- Verify mirroring is applied correctly
- Check camera orientation setting

### Issue: Jittery tracking
- Check visibility scores (should be stable)
- Verify smoothing alpha (should be 0.95)
- Check if coordinates are being clamped

### Issue: No angle calculation
- Verify all 3 points are present (shoulder, elbow, wrist)
- Check visibility scores for all joints
- Verify angle is in valid range (0-180°)

## Performance Notes

- Logging every 30-60 frames keeps overhead minimal
- All logs use structured format for easy parsing
- Can be disabled by commenting out logging blocks
- No impact on tracking performance (runs on separate thread)
