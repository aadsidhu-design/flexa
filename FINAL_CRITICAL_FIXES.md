# FINAL CRITICAL FIXES - All Issues

## Issue 1: Camera SPARC Wrist at (0,0) 🐛

**Problem**: `📊 [CameraSPARC] Wrist tracked: left at (0, 0)`

**Root Cause**: Passing Vision coordinates (0-1 normalized) instead of screen coordinates to SPARC!

**Fix**: Map wrist to screen coordinates before passing to SPARC

**File**: `SimpleMotionService.swift` line ~3765-3787

**CHANGE THIS:**
```swift
if activeSide == .right {
    if let wrist = smoothedKeypoints.rightWrist, self.isValidWristPosition(wrist) {
        self.sparcService.addVisionMovement(timestamp: timestamp, position: wrist)  // ❌ WRONG - normalized coords!
```

**TO THIS:**
```swift
if activeSide == .right {
    if let wrist = smoothedKeypoints.rightWrist, self.isValidWristPosition(wrist) {
        // Map Vision coordinates (0-1) to screen coordinates (pixels)
        let screenWrist = CoordinateMapper.mapVisionPointToScreen(wrist, previewSize: self.cameraPreviewSize)
        self.sparcService.addVisionMovement(timestamp: timestamp, position: screenWrist)  // ✅ CORRECT!
        FlexaLog.motion.debug(
            "📊 [CameraSPARC] Wrist tracked: right at (\(String(format: "%.0f", screenWrist.x)), \(String(format: "%.0f", screenWrist.y)))"
        )
```

Do the same for left wrist!

---

## Issue 2: Follow Circle - One Circle = One Rep 🎯

**Problem**: Using IMU direction detection which counts every direction change, not full circles

**Solution**: Need custom logic to count only FULL 360° rotations

**Current**: IMU detects every swing → too many reps
**Needed**: Full circle (360° rotation) = 1 rep

**Implementation Needed**: Create circular motion detector that accumulates rotation angle until 360° reached

**File**: `HandheldRepDetector.swift` or new circular detector

---

## Issue 3: Fan the Flame False Positives 🔥

**Problem**: IMU detecting false positives on side-to-side motion

**Root Cause**: Too sensitive direction change detection

**Fix**: Increase amplitude threshold and cooldown

**File**: `IMUDirectionRepDetector.swift`

**Changes Needed**:
- Increase minimum amplitude threshold (current unknown, need to check file)
- Increase cooldown between reps (prevent double-counting)
- Add side-to-side specific filtering

---

## Issue 4: Constellation Complete Rewrite 🔺

**Critical Issues**:
1. Circle glitches when face covered (wrist lost)
2. Reps recorded per connection (wrong - should be per pattern)
3. Logic is complex and broken

**New Logic** (Per User Requirements):

### Triangle:
```
Start: Any point
Step 1: Go to any other unvisited point
Step 2: Go to remaining unvisited point  
Step 3: Go back to START point → Pattern complete = 1 rep
```

### Square/Rectangle:
```
Start: Any point
Step 1-3: Go to adjacent points (no diagonals!)
Step 4: Return to START → Pattern complete = 1 rep
```

### Circle (8 points):
```
Start: Any point
Step 1-7: Go to immediate LEFT or RIGHT neighbor only
Step 8: Return to START → Pattern complete = 1 rep
```

**Key Changes Needed**:

1. **Remove per-connection rep recording**:
```swift
// DELETE THIS from handleCorrectHit:
if connectedPoints.count > 1 {
    motionService.recordVisionRepCompletion(rom: normalized)  // ❌ REMOVE!
}
```

2. **Only record rep on pattern completion**:
```swift
private func onPatternCompleted() {
    // Record ONE rep for the completed pattern
    motionService.recordVisionRepCompletion(rom: normalized)  // ✅ Only here!
    
    completedPatterns += 1
    
    if completedPatterns >= 3 {
        endGame()
    } else {
        generateNewPattern()
    }
}
```

3. **Fix connection validation logic**:
```swift
private func isValidConnection(from startIdx: Int, to endIdx: Int) -> Bool {
    // Universal: Can't connect to already-connected point
    guard !connectedPoints.contains(endIdx) else { return false }
    
    switch currentPatternName {
    case "Triangle":
        // Any unvisited point is valid
        return true
        
    case "Square":
        // Must be adjacent (not diagonal)
        // Valid adjacencies for square: 0↔1, 1↔2, 2↔3, 3↔0
        let adjacentPairs: Set<Set<Int>> = [[0,1], [1,2], [2,3], [3,0]]
        return adjacentPairs.contains([startIdx, endIdx])
        
    case "Circle":
        // Must be immediate neighbor (left or right)
        let numPoints = currentPattern.count  // 8
        let leftNeighbor = (startIdx - 1 + numPoints) % numPoints
        let rightNeighbor = (startIdx + 1) % numPoints
        return endIdx == leftNeighbor || endIdx == rightNeighbor
        
    default:
        return false
    }
}
```

4. **Fix closing pattern logic**:
```swift
// In evaluateTargetHit, when touching already-connected dot:
if connectedPoints.contains(index) {
    // Only allow if it's the START point AND we've visited ALL other points
    if index == patternStartIndex && connectedPoints.count == currentPattern.count {
        print("🌟 Closing pattern - all \(currentPattern.count) points visited!")
        onPatternCompleted()  // This records the rep!
    }
}
```

5. **Fix wrist tracking when face covered**:
```swift
// In updateHandTracking:
guard let wrist = activeWrist else {
    // NO WRIST DETECTED - hide hand circle completely
    handPosition = .zero  // This hides the circle
    return
}

// Only show circle when wrist is actually detected
if handPosition != .zero {
    Circle()  // Hand circle
        .position(handPosition)
}
```

6. **Make circle appear instantly** (reduce smoothing on first detection):
```swift
let alpha: CGFloat = 0.95
handPosition = CGPoint(
    x: previousPosition == .zero ? mapped.x : (previousPosition.x * (1 - alpha) + mapped.x * alpha),  
    y: previousPosition == .zero ? mapped.y : (previousPosition.y * (1 - alpha) + mapped.y * alpha)
)
```

This already does instant appearance when `previousPosition == .zero`! Just verify it's working.

---

## Issue 5: Wall Climbers Verification ✅

Based on earlier fixes, should be working:
- Altitude meter updates for any arm raise
- Reps recorded when ROM threshold met

**Test**: Verify reps are counted correctly and altitude meter responds

---

## Implementation Priority:

### P0 (DO IMMEDIATELY):
1. ✅ Fix camera SPARC wrist coordinates (map to screen)
2. ✅ Fix constellation rep recording (only on pattern complete)
3. ✅ Fix constellation connection validation logic

### P1 (DO NEXT):
4. 🔧 Fix Follow Circle full-circle detection
5. 🔧 Fix Fan the Flame false positives

---

## Code Changes Summary:

### File 1: `SimpleMotionService.swift` (line ~3765-3787)

**FIX WRIST COORDINATES:**
```swift
// Right wrist
if let wrist = smoothedKeypoints.rightWrist, self.isValidWristPosition(wrist) {
    let screenWrist = CoordinateMapper.mapVisionPointToScreen(wrist, previewSize: self.cameraPreviewSize)
    self.sparcService.addVisionMovement(timestamp: timestamp, position: screenWrist)
    FlexaLog.motion.debug("📊 [CameraSPARC] Wrist tracked: right at (\(String(format: "%.0f", screenWrist.x)), \(String(format: "%.0f", screenWrist.y)))")
}

// Left wrist  
if let wrist = smoothedKeypoints.leftWrist, self.isValidWristPosition(wrist) {
    let screenWrist = CoordinateMapper.mapVisionPointToScreen(wrist, previewSize: self.cameraPreviewSize)
    self.sparcService.addVisionMovement(timestamp: timestamp, position: screenWrist)
    FlexaLog.motion.debug("📊 [CameraSPARC] Wrist tracked: left at (\(String(format: "%.0f", screenWrist.x)), \(String(format: "%.0f", screenWrist.y)))")
}
```

### File 2: `SimplifiedConstellationGameView.swift`

**REMOVE per-connection rep recording** (line ~441):
```swift
private func handleCorrectHit(for index: Int) {
    currentTargetIndex = index
    wrongConnectionCount = 0
    clearIncorrectFeedback()
    HapticFeedbackService.shared.successHaptic()

    if !connectedPoints.contains(index) {
        connectedPoints.append(index)
        
        // ❌ DELETE THIS ENTIRE BLOCK:
        // if connectedPoints.count > 1 {
        //     motionService.recordVisionRepCompletion(rom: normalized)
        // }
        
        score += 10
    }
}
```

**FIX pattern completion** (already correct at line ~593):
```swift
private func onPatternCompleted() {
    print("🌟 [ArmRaises] Pattern COMPLETED!")
    completedPatterns += 1
    score += 100
    HapticFeedbackService.shared.successHaptic()

    // Record ONE rep for this pattern
    if let keypoints = motionService.poseKeypoints {
        var normalized = motionService.currentROM
        if normalized <= 0 {
            let rawROM = keypoints.getArmpitROM(side: keypoints.phoneArm)
            normalized = motionService.validateAndNormalizeROM(rawROM)
        }
        let minimumThreshold = motionService.getMinimumROMThreshold(for: .constellation)
        if normalized >= minimumThreshold {
            motionService.recordVisionRepCompletion(rom: normalized)
            completedPatterns = motionService.currentReps
        }
    }

    if completedPatterns >= 3 {
        print("🎉 [ArmRaises] ALL 3 PATTERNS COMPLETED!")
        endGame()
        return
    }

    print("🎯 [ArmRaises] Pattern \(completedPatterns)/3 done")
    generateNewPattern()
}
```

**FIX connection validation** (line ~453):
Already mostly correct, just verify Square adjacency logic!

---

## Expected Results After Fixes:

### Constellation:
```
🌟 [ArmRaises] Pattern COMPLETED!
🎥 [CameraRep] Recorded camera rep #1 ROM=88.1°
🎯 [ArmRaises] Pattern 1/3 done
🌟 [ArmRaises] Pattern COMPLETED!
🎥 [CameraRep] Recorded camera rep #2 ROM=90.3°
🎯 [ArmRaises] Pattern 2/3 done
🌟 [ArmRaises] Pattern COMPLETED!
🎥 [CameraRep] Recorded camera rep #3 ROM=85.6°
🎉 [ArmRaises] ALL 3 PATTERNS COMPLETED!
```

### Camera SPARC:
```
📊 [CameraSPARC] Wrist tracked: left at (195, 362)  ← Real coordinates!
📊 [CameraSPARC] Wrist tracked: left at (208, 358)
📊 [AnalyzingView] ✨ Camera wrist smoothness: 76%  ← Accurate!
```

---

## Quick Implementation:

1. Edit `SimpleMotionService.swift` - Add `CoordinateMapper.mapVisionPointToScreen()` to wrist SPARC tracking (2 places)
2. Edit `SimplifiedConstellationGameView.swift` - Remove per-connection rep recording from `handleCorrectHit`
3. Test constellation - should get EXACTLY 3 reps (one per pattern)
4. Test SPARC - should show real coordinates, not (0,0)

**Estimated Time**: 30 minutes for P0 fixes
