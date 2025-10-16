# Critical Fixes Implementation Plan

## Issue 1: Follow Circle Reps Not Working ✅

**Problem**: Position-based circular detection is too complex and unreliable
**Solution**: Switch to IMU gyroscope-based detection like Fruit Slicer

**Why**: IMU gyros detect rotational movement directly - perfect for circular motion!

**Implementation**:
```swift
// In SimpleMotionService.startHandheldSession:
// CHANGE: Follow Circle should use IMU direction detector
let useIMURepDetection = (gameType == .fruitSlicer || gameType == .fanOutFlame || gameType == .followCircle)

if useIMURepDetection {
    imuDirectionRepDetector.reset()
    // IMU detects circular rotation via gyroscope changes
} else {
    handheldRepDetector.startSession(gameType: detectorGameType)
}
```

**File**: `SimpleMotionService.swift` line ~2227

---

## Issue 2: Fan the Flame Already Uses IMU ✅

**Status**: ALREADY CORRECT!
- Line 2227: `let useIMURepDetection = (gameType == .fruitSlicer || gameType == .fanOutFlame)`
- Fan the Flame already uses IMU direction detector
- Should be working properly

**Verification Needed**: Test on device to confirm reps are registering

---

## Issue 3: Pain Change Over Week 📊

**Problem**: No weekly pain tracking displayed
**Solution**: Calculate average pain change from last 7 days of sessions

**Implementation**:
```swift
// In EnhancedProgressViewFixed or wherever weekly stats are shown:

func calculateWeeklyPainChange() -> Double {
    let sessions = LocalDataManager.shared.getRecentSessions(days: 7)
    
    var painChanges: [Double] = []
    
    for session in sessions {
        if let painPre = session.painPre, let painPost = session.painPost {
            let change = Double(painPre - painPost)  // Positive = improvement
            painChanges.append(change)
        }
    }
    
    guard !painChanges.isEmpty else { return 0.0 }
    
    return painChanges.reduce(0, +) / Double(painChanges.count)
}

// Display:
Text("Avg Pain Change: \(String(format: "%.1f", weeklyPainChange))")
    .foregroundColor(weeklyPainChange > 0 ? .green : weeklyPainChange < 0 ? .red : .gray)
```

**Files**: 
- `EnhancedProgressViewFixed.swift`
- `LocalDataManager.swift` (add `getRecentSessions(days:)` if needed)

---

## Issue 4: Constellation Complete Rewrite Needed 🔺

**Problems**:
1. Must complete all 3 constellations before ending
2. Glitchy tracking
3. Connection validation too complex
4. BlazePose tracking quality

**Solutions**:

### A. Ensure 3 Patterns Before End
```swift
private func endGame() {
    // CRITICAL: Only end if 3 patterns completed
    guard completedPatterns >= 3 else {
        print("⚠️ [Constellation] Not enough patterns: \(completedPatterns)/3")
        return
    }
    // ... rest of end game logic
}
```

### B. Simplify Connection Logic
```swift
// CURRENT: Complex validation with different rules per pattern
// BETTER: Unified approach with clear rules

private func isValidConnection(from startIdx: Int, to endIdx: Int) -> Bool {
    // Universal rule: Can't connect to already-connected point
    guard !connectedPoints.contains(endIdx) else { return false }
    
    switch currentPatternName {
    case "Triangle":
        return true  // Any unvisited point
        
    case "Square":
        // Must be adjacent in sequence (0→1→2→3→0)
        let expectedNext = (startIdx + 1) % 4
        return endIdx == expectedNext
        
    case "Circle":
        // Must be immediate neighbor (left or right)
        let numPoints = currentPattern.count
        let leftNeighbor = (startIdx - 1 + numPoints) % numPoints
        let rightNeighbor = (startIdx + 1) % numPoints
        return endIdx == leftNeighbor || endIdx == rightNeighbor
        
    default:
        return false
    }
}
```

### C. Fix Glitchy Tracking
**Root Cause**: Hand circle smoothing too aggressive or BlazePose jitter
**Solutions**:
1. Increase wrist position smoothing: `alpha = 0.9` (very smooth)
2. Increase hit tolerance: `targetHitTolerance() * 1.5` (bigger hit boxes)
3. Add hysteresis: Once hovering, stay for 0.2s before losing lock

```swift
// In updateHandTracking():
let alpha: CGFloat = 0.9  // High smoothing for stable cursor
handPosition = CGPoint(
    x: previousPosition.x * alpha + mapped.x * (1 - alpha),
    y: previousPosition.y * alpha + mapped.y * (1 - alpha)
)

// Increase tolerance:
private func targetHitTolerance() -> CGFloat {
    max(50, screenSize.width * 0.08)  // Bigger hit boxes
}
```

---

## Issue 5: Custom Exercise Robust Rep Detection 🎯

**Problem**: Reps not detecting properly based on movement type
**Solution**: Specialized detection per movement type

**Movement Types**:
- **Circular**: Use IMU gyroscope (rotational velocity)
- **Pendulum**: Use IMU direction change (accelerometer)
- **Horizontal**: Use IMU X-axis direction change
- **Vertical**: Use IMU Y-axis direction change
- **Straightening**: Use position-based extension detection

**Implementation**:
```swift
// In CustomRepDetector or SimpleMotionService:

func startCustomExerciseSession(exercise: CustomExercise) {
    let movementType = exercise.repParameters.movementType
    
    switch movementType {
    case .circular:
        // Use IMU gyroscope for rotation
        useIMUGyroscopeDetection = true
        
    case .pendulum:
        // Use IMU direction change
        imuDirectionRepDetector.reset()
        
    case .horizontal, .vertical:
        // Use IMU with axis-specific detection
        setupAxisSpecificDetection(axis: movementType)
        
    case .straightening:
        // Use position-based for joint extension
        usePositionBasedDetection = true
        
    case .mixed:
        // Use combination of methods
        useCombinedDetection = true
    }
}
```

---

## Priority Implementation Order:

### P0 (Critical - Do First):
1. ✅ Follow Circle: Switch to IMU detection
2. ✅ Constellation: Fix pattern completion counter (3 required)
3. ✅ Constellation: Improve tracking smoothness

### P1 (Important - Do Next):
4. 📊 Pain tracking: Weekly average calculation
5. 🔺 Constellation: Simplify connection validation
6. 🎯 Custom exercises: Movement-specific rep detection

### P2 (Nice to Have):
7. 🔍 SPARC: Tune for circular motion
8. 📈 Graphs: Additional smoothing options
9. 🎨 UI: Better visual feedback for tracking

---

## Testing Checklist:

### Follow Circle:
- [ ] Reps trigger on circular motion
- [ ] SPARC calculated from IMU data
- [ ] ROM per rep graphing works

### Fan the Flame:
- [ ] Reps trigger on side-to-side motion
- [ ] Direction changes detected properly

### Constellation:
- [ ] Must complete all 3 patterns
- [ ] Hand tracking smooth (not glitchy)
- [ ] Connection validation clear and consistent
- [ ] Pattern completion triggers next pattern

### Pain Tracking:
- [ ] Weekly average shown
- [ ] Works for ALL exercise types
- [ ] Color-coded (green=improvement, red=worsening)

### Custom Exercises:
- [ ] Reps detect based on movement type
- [ ] ROM calculated appropriately
- [ ] SPARC uses existing system

---

## Files To Modify:

1. **SimpleMotionService.swift**
   - Line ~2227: Add `.followCircle` to IMU detection
   - Add custom exercise movement type routing

2. **SimplifiedConstellationGameView.swift**
   - Fix pattern completion requirement (3 patterns)
   - Increase wrist smoothing (alpha = 0.9)
   - Increase hit tolerance (50px min)
   - Simplify connection validation

3. **EnhancedProgressViewFixed.swift**
   - Add weekly pain change calculation
   - Display average pain change over 7 days

4. **LocalDataManager.swift**
   - Add `getRecentSessions(days: Int)` method if missing

5. **CustomRepDetector.swift** (if exists) or **SimpleMotionService.swift**
   - Add movement-type-specific rep detection

---

## Summary:

**Quick Wins** (1-2 hours):
- Switch Follow Circle to IMU ✅
- Fix Constellation pattern counter ✅
- Improve Constellation tracking smoothness ✅

**Medium Effort** (3-4 hours):
- Implement pain weekly tracking 📊
- Simplify Constellation validation logic 🔺

**Larger Effort** (5+ hours):
- Custom exercise robust rep detection 🎯
- Full Constellation rewrite (if needed)

**Total Estimated Time**: 8-12 hours for complete implementation
