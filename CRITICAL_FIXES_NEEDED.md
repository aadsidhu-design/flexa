# Critical Fixes Needed - Priority Order

## IMMEDIATE PRIORITY (Do These First)

### 1. Fruit Slicer - Direction Change Rep Detection ✅ PARTIALLY WORKING
**Current Status**: IMU rep detector exists but may not be properly wired
**What's Needed**:
- Verify IMURepDetector is detecting direction changes correctly
- Ensure baseline resets after each rep
- Test that forward/backward swings each count as 1 rep

**Files to Check**:
- `Services/Handheld/IMUrepdetector.swift`
- `Services/SimpleMotionService.swift` (lines ~1680-1750 for IMU setup)
- `Games/OptimizedFruitSlicerGameView.swift`

### 2. Camera Games - MediaPipe Coordinate Mapping ❌ BROKEN
**Current Status**: Likely broken coordinate system
**What's Needed**:
- Fix MediaPipePoseProvider coordinate mapping
- Ensure landmarks are in correct screen space
- Verify 3-point angle calculations work

**Files to Fix**:
- `Services/Camera/MediaPipePoseProvider.swift`
- `Services/Camera/CameraROMCalculator.swift`

### 3. Wall Climbers - Up/Down Rep Detection ❌ NOT IMPLEMENTED
**Current Status**: Needs complete rewrite
**What's Needed**:
- Detect upward motion (ROM tracking phase)
- Detect downward motion (instant rep count)
- Track peak ROM during ascent
- Implement altitude meter

**Files to Fix**:
- `Services/Camera/CameraRepDetector.swift`
- `Games/WallClimbersGameView.swift`

## MEDIUM PRIORITY

### 4. Balloon Pop - Timer and Extension Detection
**Current Status**: Needs timer implementation
**What's Needed**:
- Add 60-second hidden timer
- Detect elbow extension as rep
- Ensure balloons spawn correctly
- Pin follows hand correctly

**Files to Fix**:
- `Games/BalloonPopGameView.swift`
- `Services/Camera/CameraRepDetector.swift`

### 5. Constellation - Dot Connection Logic
**Current Status**: Needs complete gameplay rewrite
**What's Needed**:
- Implement 3 constellation patterns (triangle, square, circle)
- Add collision detection for hand circle + dots
- Implement line drawing
- Add validation rules (no diagonals for square, etc.)

**Files to Fix**:
- `Games/SimplifiedConstellationGameView.swift`

### 6. Follow Circle - Circle Completion Detection
**Current Status**: Needs circle detection algorithm
**What's Needed**:
- Detect when user completes full circle
- Calculate ROM from maximum radius
- Reset baseline after circle completion

**Files to Fix**:
- `Services/Handheld/HandheldRepDetector.swift`
- `Services/Handheld/HandheldROMCalculator.swift` (circular mode exists)

### 7. Fan the Flame - Direction Change Detection
**Current Status**: Similar to Fruit Slicer, may work
**What's Needed**:
- Verify left/right fanning motion detection
- Ensure each direction counts as 1 rep

**Files to Fix**:
- `Services/Handheld/IMUrepdetector.swift`
- `Games/FanOutTheFlameGameView.swift`

## LOW PRIORITY (Polish)

### 8. SPARC Smoothness - Smooth Curve Display
**Current Status**: Shows spiky up/down graph
**What's Needed**:
- Calculate smoothness from ARKit positions
- Generate smooth curve for display
- Show average smoothness score

**Files to Fix**:
- `Services/SPARCCalculationService.swift`
- `Views/Components/SmoothnessTrendChartView.swift`

## TESTING REQUIREMENTS

After each fix, test:
1. Rep counting accuracy
2. ROM calculation accuracy  
3. Baseline reset after rep
4. Game completion conditions
5. Session data export

## ESTIMATED TIME

- **Critical Fixes (1-3)**: 8-12 hours
- **Medium Priority (4-7)**: 12-16 hours
- **Low Priority (8)**: 4-6 hours
- **Total**: 24-34 hours of focused development

## RECOMMENDED APPROACH

1. Fix one game completely before moving to next
2. Test thoroughly after each fix
3. Use Fruit Slicer as template for other handheld games
4. Use Wall Climbers as template for other camera games
5. Keep SimpleMotionService changes minimal

## CURRENT WORKING PARTS (Don't Break These)

✅ HandheldROMCalculator - 2D plane projection works
✅ ARKit position tracking - InstantARKitTracker works
✅ MediaPipe pose detection - MediaPipePoseProvider works
✅ Session data export - Works correctly
✅ Calibration system - Works correctly

## FILES THAT NEED MAJOR CHANGES

1. `Services/Camera/CameraRepDetector.swift` - Complete rewrite needed
2. `Games/WallClimbersGameView.swift` - Altitude meter + gameplay
3. `Games/SimplifiedConstellationGameView.swift` - Dot connection logic
4. `Games/BalloonPopGameView.swift` - Timer + balloon spawning
5. `Services/Handheld/HandheldRepDetector.swift` - Circle detection

## FILES THAT NEED MINOR CHANGES

1. `Services/Camera/MediaPipePoseProvider.swift` - Coordinate mapping
2. `Services/Camera/CameraROMCalculator.swift` - Verify angles
3. `Services/Handheld/IMUrepdetector.swift` - Verify direction changes
4. `Services/SPARCCalculationService.swift` - Smooth curve calculation
