# Complete Motion Tracking System Refactor Plan

## Overview
Complete overhaul of motion tracking, ROM calculation, and rep detection for both handheld and camera-based games.

## Handheld Games (ARKit + IMU)

### 1. Fruit Slicer
- **Rep Detection**: Direction changes (forward swing = 1 rep, backward swing = 1 rep)
- **ROM Calculation**: 
  - Track 3D position via ARKit
  - Project arc to best 2D plane (XY, XZ, or YZ) to reduce bias
  - Calculate angle using arc length and arm length
  - Reset baseline after each rep detection
- **Smoothness**: Based on ARKit positions, show smooth curve (not up/down spikes)

### 2. Fan the Flame
- **Rep Detection**: Direction changes (fan left = 1 rep, fan right = 1 rep)
- **ROM Calculation**: Same as Fruit Slicer
- **Smoothness**: Same as Fruit Slicer

### 3. Follow Circle
- **Rep Detection**: One complete circle = 1 rep
- **ROM Calculation**: 
  - Find biggest radius of circular motion
  - Use arm length to calculate angle from triangle legs
  - Reset baseline after each circle completion
- **Smoothness**: Same as Fruit Slicer

## Camera Games (MediaPipe Pose)

### 1. Wall Climbers
- **Pose Detection**: MediaPipe (NOT Apple Vision)
- **ROM Calculation**: 3-point armpit/shoulder angle
- **Rep Detection**: 
  - Going UP = ROM tracking (peak angle = rep ROM)
  - Coming DOWN = rep counted INSTANTLY when descent detected
  - Going back up ≠ rep (only down motion counts)
- **Gameplay**: 
  - Altitude meter on right side
  - Each rep increases altitude
  - Game ends when meter is full
- **Wrist Tracking**: Use pose detection for wrist position

### 2. Constellation
- **Pose Detection**: MediaPipe
- **ROM Calculation**: 3-point armpit/shoulder angle
- **Rep Detection**: Based on connecting constellation dots
- **Gameplay**:
  - Circle around hand, selects dot on collision
  - Line drawn from dot to hand circle
  - 3 constellations to complete:
    1. **Triangle**: Start anywhere, visit all 3 points, must return to start
    2. **Square**: Start anywhere, NO DIAGONALS (show "incorrect" and reset if diagonal)
    3. **Circle**: Start anywhere, can only go to adjacent left/right point
  - No timer, game ends after all 3 completed

### 3. Elbow Extension (Balloon Pop)
- **Pose Detection**: MediaPipe
- **ROM Calculation**: 3-point elbow angle
- **Rep Detection**: 
  - Extension UP = 1 rep
  - Coming down ≠ rep
- **Gameplay**:
  - Pin follows user's hand
  - Balloons spawn on top
  - Pop balloons with pin
  - 60 second timer (hidden from user)
  - Game ends after 60 seconds

## Key Technical Fixes Needed

### HandheldROMCalculator
- [ ] Implement 2D plane projection (XY, XZ, YZ)
- [ ] Add arc length calculation
- [ ] Use arm length from calibration
- [ ] Calculate angle from arc length and arm length
- [ ] Add baseline reset on rep detection
- [ ] Fix circular motion detection for Follow Circle

### HandheldRepDetector
- [ ] Fix direction change detection for Fruit Slicer
- [ ] Fix direction change detection for Fan the Flame
- [ ] Implement circle completion detection for Follow Circle

### CameraROMCalculator
- [ ] Fix MediaPipe coordinate mapping
- [ ] Implement 3-point angle calculation for armpit/shoulder
- [ ] Implement 3-point angle calculation for elbow
- [ ] Ensure correct landmark selection

### CameraRepDetector
- [ ] Implement up/down detection for Wall Climbers
- [ ] Implement constellation dot connection logic
- [ ] Implement extension detection for Balloon Pop
- [ ] Add peak ROM tracking during ascent

### SPARCCalculationService
- [ ] Fix handheld smoothness to use ARKit positions
- [ ] Generate smooth curve (not spiky up/down)
- [ ] Calculate average smoothness across session

### Game Views
- [ ] Fix Wall Climbers altitude meter
- [ ] Fix Constellation dot connection logic
- [ ] Fix Balloon Pop timer and balloon spawning
- [ ] Ensure all games properly start/stop motion tracking

## Implementation Priority
1. Fix HandheldROMCalculator (affects all 3 handheld games)
2. Fix HandheldRepDetector (affects all 3 handheld games)
3. Fix CameraROMCalculator (affects all 3 camera games)
4. Fix CameraRepDetector (affects all 3 camera games)
5. Fix individual game views
6. Fix SPARC smoothness calculation

## Testing Checklist
- [ ] Fruit Slicer: Direction changes count reps correctly
- [ ] Fruit Slicer: ROM resets after each rep
- [ ] Fan the Flame: Direction changes count reps correctly
- [ ] Follow Circle: Circle completion counts as 1 rep
- [ ] Follow Circle: ROM calculated from radius
- [ ] Wall Climbers: Only down motion counts as rep
- [ ] Wall Climbers: Altitude meter works
- [ ] Constellation: All 3 patterns work with rules
- [ ] Balloon Pop: 60 second timer works
- [ ] Balloon Pop: Extension counts as rep
- [ ] All games: Smoothness shows smooth curve
