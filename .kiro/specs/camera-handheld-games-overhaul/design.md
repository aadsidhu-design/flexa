# Design Document

## Overview

This design addresses the comprehensive overhaul of camera-based and handheld game systems in the Flexa iOS application. The current implementation has critical issues with rep detection algorithms, ROM calculation methods, coordinate mapping, gameplay mechanics, and smoothness analysis. This design establishes correct motion tracking pipelines, accurate ROM measurements using proper geometric calculations, validated rep detection algorithms, and engaging gameplay mechanics for all six built-in exercise games.

## Architecture

### High-Level System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    SimpleMotionService                       │
│              (Central Motion Coordinator)                    │
└─────────────────────────────────────────────────────────────┘
                    │                    │
        ┌───────────┴──────────┐        │
        │                      │        │
        ▼                      ▼        ▼
┌──────────────┐      ┌──────────────┐ ┌──────────────┐
│   Handheld   │      │    Camera    │ │    SPARC     │
│   Pipeline   │      │   Pipeline   │ │   Service    │
└──────────────┘      └──────────────┘ └──────────────┘
        │                      │                │
        ▼                      ▼                ▼
┌──────────────┐      ┌──────────────┐ ┌──────────────┐
│  ARKit 3D    │      │  MediaPipe   │ │  Smoothness  │
│  Tracking    │      │  Pose 2D     │ │  Analysis    │
└──────────────┘      └──────────────┘ └──────────────┘
```

### Handheld Games Pipeline

```
ARKit Transform (4x4 matrix)
    │
    ▼
Extract 3D Position (x, y, z)
    │
    ▼
┌─────────────────────────────────────┐
│  HandheldROMCalculator              │
│  - Accumulate 3D trajectory    
│  - Complete rep
│  - Detect best 2D plane (XY/XZ/YZ) from all data │
│  - Project all data to same detected 2D plane               │
│  - Calculate arc length              │
│  - ROM = arcLength / armLength * 180/π│
└─────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────┐
│  HandheldRepDetector                │
│  - Fruit Slicer: Direction changes  │
│  - Follow Circle: Circle completion │
│  - Fan Flame: Direction changes     │
└─────────────────────────────────────┘
    │
    ▼
Rep Detected → Reset Baseline → Record ROM
```

### Camera Games Pipeline

```
Camera Frame (CMSampleBuffer)
    │
    ▼
MediaPipePoseProvider
    │
    ▼
33 Landmarks (normalized 0-1)
    │
    ▼
CoordinateMapper
    │
    ▼
Screen Coordinates (pixels)
    │
    ▼
┌─────────────────────────────────────┐
│  CameraROMCalculator                │
│  - Wall Climbers: Shoulder angle    │
│  - Constellation: Shoulder angle    │
│  - Elbow Extension: Elbow angle     │
│  - 3-point angle calculation        │
└─────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────┐
│  CameraRepDetector                  │
│  - Wall Climbers: Upward motion     │
│  - Constellation: Dot connections   │
│  - Elbow Extension: Extension cycle │
└─────────────────────────────────────┘
    │
    ▼
Rep Detected → Record Peak ROM
```

## Components and Interfaces

### 1. Handheld ROM Calculator (Enhanced)

**Purpose**: Calculate ROM from 3D ARKit trajectories using 2D plane projection

**Key Methods**:
```swift
class HandheldROMCalculator {
    // Process incoming 3D position
    func processPosition(_ position: SIMD3<Float>, timestamp: TimeInterval)
    
    // Complete rep and calculate final ROM
    func completeRep(timestamp: TimeInterval)
    
    // Find best 2D projection plane
    private func findBestProjectionPlane(_ positions: [SIMD3<Float>]) -> ProjectionPlane
    
    // Calculate arc length on 2D plane
    private func calculateArcLengthOn2DPlane(_ positions: [SIMD3<Float>], plane: ProjectionPlane) -> Double
    
    // Calculate ROM from arc length
    private func calculateROMFromArcLength(_ arcLength: Double) -> Double
    
    // Calculate ROM from radius (circular motion)
    private func calculateROMFromRadius(_ radius: Double) -> Double
    
    // Reset baseline after rep
    func resetLiveROM()
}
```

**2D Plane Selection Algorithm**:
```
1. Calculate variance for each axis (X, Y, Z)
2. Sort axes by variance (highest = most motion)
3. Select plane containing top 2 axes:
   - XY plane: if X and Y have highest variance
   - XZ plane: if X and Z have highest variance
   - YZ plane: if Y and Z have highest variance
4. Project all 3D points onto selected 2D plane
5. Calculate arc length in 2D space
```

**ROM Calculation Formula**:
```
For pendulum motion (Fruit Slicer, Fan Flame):
  ROM (degrees) = (arcLength / armLength) * (180 / π)

For circular motion (Follow Circle):
  ROM (degrees) = arcsin(radius / armLength) * (180 / π)
```

### 2. Handheld Rep Detector (Enhanced)

**Purpose**: Detect reps based on motion patterns

**Fruit Slicer & Fan Flame** (Direction Change Detection):
```swift
class HandheldRepDetector {
    // Detect pendulum direction change
    private func detectPendulumRep(position: SIMD3<Float>, timestamp: TimeInterval, rom: Double)
    
    // Direction change logic:
    // 1. Calculate displacement vector
    // 2. Normalize to get direction
    // 3. Compare with last direction (dot product)
    // 4. If dot product < -0.2 → direction changed
    // 5. Check cooldown (0.3s minimum)
    // 6. If ROM > threshold → count rep
}
```

**Follow Circle** (Circle Completion Detection):
```swift
class HandheldRepDetector {
    // Detect circular motion completion
    private func detectCircularRep(position: SIMD3<Float>, timestamp: TimeInterval)
    
    // Circle detection logic:
    // 1. Establish circle center (moving average)
    // 2. Calculate angle from center
    // 3. Accumulate angle changes
    // 4. When accumulated angle >= 2π → circle complete
    // 5. Check cooldown (0.4s minimum)
    // 6. Count rep and reset accumulator
}
```

### 3. Camera ROM Calculator (Fixed)

**Purpose**: Calculate ROM from MediaPipe pose landmarks

**Key Methods**:
```swift
class CameraROMCalculator {
    // Calculate ROM based on joint preference
    func calculateROM(from keypoints: SimplifiedPoseKeypoints, jointPreference: CameraJointPreference) -> Double
    
    // Calculate shoulder angle (armpit ROM)
    private func calculateArmAngle(shoulder: CGPoint, elbow: CGPoint) -> Double
    
    // Calculate elbow flexion angle
    private func calculateElbowFlexionAngle(shoulder: CGPoint, elbow: CGPoint, wrist: CGPoint) -> Double
}
```

**Shoulder Angle Calculation** (Wall Climbers, Constellation):
```
1. Get shoulder and elbow landmarks
2. Calculate vector from shoulder to elbow
3. Calculate angle from vertical (screen Y-axis)
4. ROM = abs(angle) in degrees
```

**Elbow Angle Calculation** (Elbow Extension):
```
1. Get shoulder, elbow, wrist landmarks
2. Calculate upper arm vector (shoulder → elbow)
3. Calculate forearm vector (elbow → wrist)
4. Calculate angle between vectors using dot product
5. ROM = angle in degrees (0° = fully bent, 180° = fully extended)
```

### 4. Camera Rep Detector (Fixed)

**Purpose**: Detect reps based on pose changes

**Wall Climbers** (Upward Motion Detection):
```swift
enum ClimbingPhase {
    case waitingToStart
    case goingUp
    case goingDown
}

// Rep detection logic:
// 1. Track wrist Y position (screen pixels)
// 2. Detect upward movement (deltaY < -threshold)
// 3. Enter "goingUp" phase, track peak Y
// 4. Detect downward movement (deltaY > threshold)
// 5. Enter "goingDown" phase
// 6. Calculate distance traveled (startY - peakY)
// 7. If distance >= minimum → count rep
// 8. Record peak ROM angle
// 9. Reset to waitingToStart
```

**Constellation** (Dot Connection Detection):
```swift
// Rep detection logic:
// 1. Detect hand collision with constellation dot
// 2. Validate connection based on pattern rules:
//    - Triangle: any unconnected dot, must close loop
//    - Rectangle: only adjacent dots (no diagonals)
//    - Circle: only left/right adjacent dots
// 3. If invalid → show "incorrect" feedback
// 4. If valid → connect dot, count rep
// 5. When pattern complete → next pattern
```

**Elbow Extension** (Extension Cycle Detection):
```swift
// Rep detection logic:
// 1. Track elbow angle continuously
// 2. Detect extension start (angle > 140°)
// 3. Track peak extension angle
// 4. Detect flexion return (angle < 90°)
// 5. Calculate ROM (peak - start)
// 6. If ROM >= threshold → count rep
// 7. Reset for next cycle
```

### 5. Coordinate Mapper (Fixed)

**Purpose**: Map MediaPipe normalized coordinates to screen space

**Current Issue**: Incorrect coordinate transformation causing misalignment

**Fixed Implementation**:
```swift
struct CoordinateMapper {
    static func mapVisionPointToScreen(
        _ point: CGPoint,  // MediaPipe normalized (0-1)
        cameraResolution: CGSize,  // Camera frame size
        previewSize: CGSize  // Screen size
    ) -> CGPoint {
        // MediaPipe coordinates are already in portrait orientation
        // and already mirrored for front camera
        
        // Direct mapping: normalized → screen pixels
        let screenX = point.x * previewSize.width
        let screenY = point.y * previewSize.height
        
        // Clamp to screen bounds
        let finalX = max(0, min(previewSize.width, screenX))
        let finalY = max(0, min(previewSize.height, screenY))
        
        return CGPoint(x: finalX, y: finalY)
    }
}
```

**Key Fix**: Remove incorrect rotation and scaling logic. MediaPipe already provides portrait-oriented, mirrored coordinates.

### 6. SPARC Smoothness Analyzer (Enhanced)

**Purpose**: Calculate movement smoothness from position trajectories

**Handheld Games** (ARKit Position-Based):
```swift
class SPARCCalculationService {
    // Add ARKit position for smoothness analysis
    func addHandheldMovement(position: SIMD3<Float>, timestamp: TimeInterval)
    
    // Calculate smoothness from 3D trajectory
    private func calculateSPARCFromTrajectory() -> Double
}
```

**Camera Games** (Wrist Position-Based):
```swift
class SPARCCalculationService {
    // Add wrist position for smoothness analysis
    func addCameraMovement(position: SIMD3<Float>, timestamp: TimeInterval)
    
    // Calculate smoothness from 2D trajectory
    private func calculateSPARCFromTrajectory() -> Double
}
```

**SPARC Calculation**:
```
1. Collect position samples over time
2. Calculate velocity profile (finite differences)
3. Apply Hanning window to reduce spectral leakage
4. Compute DFT magnitude spectrum
5. Calculate spectral arc length
6. Return negative arc length (higher = smoother)
7. Display as curved line graph (not up/down pattern)
```

## Data Models

### Handheld Game Data Flow

```swift
// ARKit Transform → 3D Position
let position = SIMD3<Float>(
    transform.columns.3.x,
    transform.columns.3.y,
    transform.columns.3.z
)

// Process position
romCalculator.processPosition(position, timestamp: timestamp)
repDetector.processPosition(position, timestamp: timestamp)

// On rep detection
romCalculator.completeRep(timestamp: timestamp)
let repROM = romCalculator.getLastRepROM()

// Reset baseline
romCalculator.resetLiveROM()
```

### Camera Game Data Flow

```swift
// MediaPipe Landmarks → Screen Coordinates
let wrist = keypoints.rightWrist  // or leftWrist
let screenWrist = CoordinateMapper.mapVisionPointToScreen(
    wrist,
    cameraResolution: cameraResolution,
    previewSize: screenSize
)

// Calculate ROM
let rom = romCalculator.calculateROM(
    from: keypoints,
    jointPreference: .armpit  // or .elbow
)

// Detect rep
let evaluation = repDetector.evaluateRepCandidate(
    rom: rom,
    threshold: minimumThreshold,
    timestamp: timestamp
)

if case .accept = evaluation {
    // Count rep and record ROM
    motionService.recordCameraRepCompletion(rom: rom)
}
```

## Gameplay Mechanics

### Handheld Games

#### Fruit Slicer
- **Objective**: Slice fruits by swinging phone forward/backward
- **Rep Detection**: Each direction change = 1 rep
- **ROM Tracking**: Arc length of swing projected to best 2D plane
- **Gameplay**: 
  - Fruits spawn from edges toward center
  - Slicer (red circle) follows IMU tilt
  - Collision detection between slicer and fruits
  - Bombs end game after 3 hits
  - Score based on fruits sliced

#### Follow Circle
- **Objective**: Trace circular path with phone
- **Rep Detection**: Each complete circle = 1 rep
- **ROM Tracking**: Radius of circular path
- **Gameplay**:
  - White guide circle orbits in circular path
  - Green cursor follows ARKit position
  - Score increases while touching guide circle
  - Streak multiplier for consecutive touches
  - Game ends after 2 minutes or losing contact

#### Fan the Flame
- **Objective**: Fan left/right to extinguish flame
- **Rep Detection**: Each direction change = 1 rep
- **ROM Tracking**: Arc length of fanning motion
- **Gameplay**:
  - Animated flame with intensity meter
  - Each rep reduces flame intensity
  - Hand animation follows motion
  - Game ends when flame extinguished or 2 minutes

### Camera Games

#### Wall Climbers
- **Objective**: Raise arm to climb altitude meter
- **Rep Detection**: Upward motion followed by downward return
- **ROM Tracking**: Peak shoulder angle during upward phase
- **Gameplay**:
  - Vertical altitude meter on right side
  - Altitude increases with each rep
  - Altitude gain proportional to distance traveled
  - Game ends when altitude meter full

#### Constellation
- **Objective**: Connect dots to form 3 patterns
- **Rep Detection**: Each dot connection = 1 rep
- **ROM Tracking**: Shoulder angle during arm movement
- **Gameplay**:
  - Pattern 1: Triangle (3 dots, any start, must close loop)
  - Pattern 2: Rectangle (4 dots, no diagonals allowed)
  - Pattern 3: Circle (8 dots, only adjacent connections)
  - Cyan circle follows hand position
  - Line draws from selected dot to hand
  - "Incorrect" feedback for invalid connections
  - Game ends after completing all 3 patterns

#### Elbow Extension (Balloon Pop)
- **Objective**: Extend arm to pop balloons
- **Rep Detection**: Each extension cycle = 1 rep
- **ROM Tracking**: Elbow angle during extension
- **Gameplay**:
  - Balloons spawn at top of screen
  - Pin/dart follows wrist position
  - Collision detection between pin and balloons
  - One balloon at a time (spawns after pop)
  - 60-second timer (background, not displayed)
  - Score based on balloons popped

## Error Handling

### Handheld Games

**ARKit Tracking Loss**:
```swift
// Fallback to IMU-only mode
if !motionService.isARKitRunning {
    // Use IMU gyroscope for rep detection only
    // Disable ROM calculation (requires ARKit)
    // Show warning overlay
}
```

**Invalid ROM Values**:
```swift
// Validate ROM before recording
func validateROM(_ rom: Double) -> Bool {
    return rom > 0 && rom <= 360 && rom.isFinite
}
```

**Baseline Reset Failure**:
```swift
// Ensure baseline resets after each rep
func completeRep() {
    // Calculate final ROM
    let rom = calculateRepROM()
    
    // Record ROM
    romPerRep.append(rom)
    
    // CRITICAL: Reset ALL baseline positions
    currentRepPositions.removeAll()
    baselinePosition = nil
    repBaselinePosition = nil
    
    // Reset live ROM display
    currentROM = 0.0
}
```

### Camera Games

**Pose Detection Failure**:
```swift
// Handle missing landmarks
guard let keypoints = motionService.poseKeypoints else {
    // Hide hand cursor
    handPosition = .zero
    return
}

// Validate landmark confidence
let confidenceThreshold: Float = 0.5
guard keypoints.leftWristConfidence > confidenceThreshold else {
    // Ignore low-confidence landmarks
    return
}
```

**Coordinate Mapping Errors**:
```swift
// Defensive checks in CoordinateMapper
guard !point.x.isNaN, !point.x.isInfinite,
      !point.y.isNaN, !point.y.isInfinite else {
    return .zero
}

guard cameraResolution.width > 0, cameraResolution.height > 0 else {
    return .zero
}
```

**Invalid Rep Detection**:
```swift
// Constellation: Validate connections
func isValidConnection(from: Int, to: Int) -> Bool {
    switch currentPatternName {
    case "Triangle":
        // Allow any unconnected point
        return !connectedPoints.contains(to)
    case "Square":
        // Only adjacent (no diagonals)
        let diff = abs(from - to)
        return diff == 1 || diff == 3
    case "Circle":
        // Only left/right adjacent
        let diff = abs(from - to)
        return diff == 1 || diff == numPoints - 1
    default:
        return false
    }
}
```

## Testing Strategy

### Unit Tests

**Handheld ROM Calculator**:
```swift
func testArcLengthCalculation() {
    // Test 2D plane projection
    // Test arc length calculation
    // Test ROM formula
}

func testBaselineReset() {
    // Test baseline resets after rep
    // Test ROM doesn't accumulate
}

func test2DPlaneSelection() {
    // Test variance calculation
    // Test plane selection logic
}
```

**Handheld Rep Detector**:
```swift
func testDirectionChangeDetection() {
    // Test direction vector calculation
    // Test dot product threshold
    // Test cooldown enforcement
}

func testCircleCompletion() {
    // Test angle accumulation
    // Test circle detection threshold
}
```

**Camera ROM Calculator**:
```swift
func testShoulderAngleCalculation() {
    // Test 3-point angle calculation
    // Test vertical reference
}

func testElbowAngleCalculation() {
    // Test vector angle calculation
    // Test range validation (0-180°)
}
```

**Coordinate Mapper**:
```swift
func testCoordinateMapping() {
    // Test normalized to screen conversion
    // Test bounds clamping
    // Test edge cases (0, 1, NaN, Inf)
}
```

### Integration Tests

**Handheld Game Flow**:
```swift
func testFruitSlicerGameFlow() {
    // 1. Start game
    // 2. Simulate ARKit positions (forward swing)
    // 3. Verify rep detected
    // 4. Verify ROM calculated
    // 5. Verify baseline reset
    // 6. Simulate backward swing
    // 7. Verify second rep
    // 8. Verify ROM doesn't accumulate
}
```

**Camera Game Flow**:
```swift
func testWallClimbersGameFlow() {
    // 1. Start game
    // 2. Simulate pose landmarks (arm up)
    // 3. Verify ROM calculated
    // 4. Simulate arm down
    // 5. Verify rep detected
    // 6. Verify altitude increased
    // 7. Verify peak ROM recorded
}
```

### Manual Testing Checklist

**Handheld Games**:
- [ ] Fruit Slicer: Forward/backward swings count as separate reps
- [ ] Fruit Slicer: ROM resets after each rep
- [ ] Fruit Slicer: Slicer follows phone tilt smoothly
- [ ] Follow Circle: Complete circles count as reps
- [ ] Follow Circle: Cursor follows ARKit position accurately
- [ ] Fan Flame: Left/right fans count as separate reps
- [ ] Fan Flame: Flame intensity decreases with reps

**Camera Games**:
- [ ] Wall Climbers: Upward arm raises count as reps
- [ ] Wall Climbers: Altitude meter increases with reps
- [ ] Constellation: Triangle allows any start point
- [ ] Constellation: Rectangle blocks diagonal connections
- [ ] Constellation: Circle only allows adjacent connections
- [ ] Elbow Extension: Pin follows wrist accurately
- [ ] Elbow Extension: Balloons pop on collision
- [ ] Elbow Extension: Game ends after 60 seconds

**Smoothness Analysis**:
- [ ] Handheld: SPARC graph shows curved line (not up/down)
- [ ] Camera: SPARC graph shows curved line (not up/down)
- [ ] SPARC values in reasonable range (-8 to -2)

## Performance Considerations

### Handheld Games
- ARKit tracking at 60 Hz
- ROM calculation on background queue
- Rep detection with 0.3s cooldown
- Baseline reset after each rep to prevent accumulation

### Camera Games
- MediaPipe pose detection at 30 Hz
- Coordinate mapping with defensive checks
- Rep detection with minimum thresholds
- Confidence filtering for landmarks

### Memory Management
- Clear trajectory buffers after rep completion
- Limit active game objects (balloons, fruits)
- Remove off-screen objects promptly
- Use weak references in closures

## Migration Strategy

### Phase 1: Fix Core Services
1. Fix `CoordinateMapper` (remove incorrect transformations)
2. Enhance `HandheldROMCalculator` (add 2D plane projection)
3. Fix `HandheldRepDetector` (correct direction change logic)
4. Fix `CameraROMCalculator` (correct angle calculations)
5. Fix `CameraRepDetector` (add proper phase tracking)

### Phase 2: Update Game Views
1. Update `OptimizedFruitSlicerGameView` (direction-based reps)
2. Update `FollowCircleGameView` (circle completion reps)
3. Update `FanOutTheFlameGameView` (direction-based reps)
4. Update `WallClimbersGameView` (upward motion reps, altitude meter)
5. Update `SimplifiedConstellationGameView` (smart validation)
6. Update `BalloonPopGameView` (extension cycle reps, 60s timer)

### Phase 3: Enhance SPARC Analysis
1. Update `SPARCCalculationService` (ARKit position input)
2. Fix smoothness graph rendering (curved line)
3. Add proper data collection for handheld games

### Phase 4: Testing & Validation
1. Unit tests for all calculators and detectors
2. Integration tests for game flows
3. Manual testing with real devices
4. Performance profiling and optimization

## Dependencies

### External Frameworks
- **ARKit**: 3D position tracking for handheld games
- **MediaPipeTasksVision**: Pose detection for camera games
- **AVFoundation**: Camera capture
- **CoreMotion**: IMU data (fallback for handheld games)

### Internal Services
- **SimpleMotionService**: Central motion coordinator
- **CalibrationDataManager**: User calibration (arm length)
- **SPARCCalculationService**: Smoothness analysis
- **HapticFeedbackService**: Tactile feedback

### Utilities
- **CoordinateMapper**: Coordinate transformations
- **FlexaLog**: Structured logging
- **NavigationCoordinator**: Screen navigation
