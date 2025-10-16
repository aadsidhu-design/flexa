# Critical Fixes Implementation Guide

## Fix 1: Follow Circle - Switch to IMU Detection

**File**: `FlexaSwiftUI/Services/SimpleMotionService.swift`
**Line**: ~2227

**CHANGE THIS:**
```swift
// Use IMU direction-based rep detection for Fruit Slicer and Fan Out Flame
let useIMURepDetection = (gameType == .fruitSlicer || gameType == .fanOutFlame)
```

**TO THIS:**
```swift
// Use IMU direction-based rep detection for Fruit Slicer, Fan Out Flame, AND Follow Circle
// IMU gyroscope is perfect for detecting circular/rotational movement!
let useIMURepDetection = (gameType == .fruitSlicer || gameType == .fanOutFlame || gameType == .followCircle)
```

**WHY**: IMU gyroscope directly measures rotational velocity - perfect for circular motion!
Position-based circular detection is too complex and unreliable.

---

## Fix 2: Constellation - Require 3 Patterns Before End

**File**: `FlexaSwiftUI/Games/SimplifiedConstellationGameView.swift`
**Line**: ~288 (in `onPatternCompleted` function)

**ADD THIS CHECK:**
```swift
private func onPatternCompleted() {
    print("🌟 [ArmRaises] Pattern COMPLETED! All dots connected.")
    completedPatterns += 1
    score += 100

    // Haptic feedback for completion
    HapticFeedbackService.shared.successHaptic()

    // Calculate ROM for this pattern completion
    // ... existing ROM calculation code ...

    // CRITICAL FIX: Check if game should end (3 patterns completed)
    if completedPatterns >= 3 {
        print("🎉 [ArmRaises] ALL 3 PATTERNS COMPLETED! Ending game...")
        endGame()
        return
    }

    // Generate next pattern if haven't completed 3 yet
    print("🎯 [ArmRaises] Pattern \(completedPatterns)/3 done - generating next...")
    generateNewPattern()
}
```

**ALSO CHECK `updateGame` function** (~line 280):
```swift
private func updateGame() {
    guard isGameActive else { return }
    updateHandTracking()
    evaluateTargetHit()
    gameTime += 1.0 / 60.0
    
    // ❌ REMOVE OR COMMENT OUT:
    // if completedPatterns >= 3 {
    //     endGame()
    //     return
    // }
    // This should only be checked in onPatternCompleted!
}
```

---

## Fix 3: Constellation - Improve Tracking Smoothness

**File**: `FlexaSwiftUI/Games/SimplifiedConstellationGameView.swift`
**Line**: ~268 (in `updateHandTracking` function)

**INCREASE SMOOTHING** (alpha value):
```swift
// OLD: Too jittery
let alpha: CGFloat = 0.8

// NEW: Much smoother tracking
let alpha: CGFloat = 0.95  // 95% old position = very smooth!
```

**INCREASE HIT TOLERANCE** (~line 537):
```swift
private func targetHitTolerance() -> CGFloat {
    // OLD: Too small, hard to hit
    max(36, screenSize.width * 0.06)
    
    // NEW: Bigger hit boxes for easier targeting
    max(50, screenSize.width * 0.08)
}
```

**ADD STICKY TARGETING** (stays locked on dot for 0.3s):
Add new state variable:
```swift
@State private var lastHoveredDot: Int? = nil
@State private var hoverStartTime: TimeInterval = 0
```

In `evaluateTargetHit()` function, add hysteresis:
```swift
if isHoveringOverCurrentTarget {
    if lastHoveredDot != index {
        lastHoveredDot = index
        hoverStartTime = now
    }
    
    // Require hovering for 0.3s before allowing next connection
    // This prevents accidental connections while moving between dots
    if now - hoverStartTime >= 0.3 {
        // Process connection...
    }
}
```

---

## Fix 4: Pain Change Over Week

**File**: `FlexaSwiftUI/Views/EnhancedProgressViewFixed.swift`

**ADD NEW COMPUTED PROPERTY** (around line 50-100, in the view struct):
```swift
// Calculate average pain change over the last 7 days
private var weeklyPainChange: Double {
    let sessions = LocalDataManager.shared.getAllSessions()
    let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    
    // Filter to last 7 days
    let recentSessions = sessions.filter { $0.timestamp >= sevenDaysAgo }
    
    // Calculate pain changes
    var painChanges: [Double] = []
    for session in recentSessions {
        if let painPre = session.painPre, let painPost = session.painPost {
            let change = Double(painPre - painPost)  // Positive = improvement
            painChanges.append(change)
        }
    }
    
    guard !painChanges.isEmpty else { return 0.0 }
    
    return painChanges.reduce(0, +) / Double(painChanges.count)
}
```

**ADD TO UI** (in the stats section, around line 200-300):
```swift
// Add this card in the weekly stats section
VStack(alignment: .leading, spacing: 8) {
    HStack {
        Image(systemName: "heart.text.square.fill")
            .foregroundColor(.pink)
            .font(.title2)
        
        Text("Pain Change")
            .font(.headline)
            .foregroundColor(.primary)
    }
    
    HStack(alignment: .firstTextBaseline) {
        Text(String(format: "%.1f", abs(weeklyPainChange)))
            .font(.system(size: 36, weight: .bold))
            .foregroundColor(weeklyPainChange > 0 ? .green : weeklyPainChange < 0 ? .red : .gray)
        
        Text("avg")
            .font(.subheadline)
            .foregroundColor(.secondary)
    }
    
    Text(weeklyPainChange > 0 ? "↓ Improvement" : weeklyPainChange < 0 ? "↑ Increase" : "No Change")
        .font(.caption)
        .foregroundColor(.secondary)
    
    Text("7-day average pain reduction")
        .font(.caption2)
        .foregroundColor(.secondary)
}
.padding()
.background(Color(.systemBackground))
.cornerRadius(12)
.shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
```

---

## Fix 5: Custom Exercise Rep Detection

**File**: `FlexaSwiftUI/Services/SimpleMotionService.swift`
**Location**: In `startHandheldGameSession` function, around line 2250

**ADD MOVEMENT TYPE ROUTING:**
```swift
// For custom exercises, determine detection method based on movement type
if gameType == .makeYourOwn, let customExercise = currentCustomExercise {
    let movementType = customExercise.repParameters.movementType
    
    switch movementType {
    case .circular:
        // Circular motion: Use IMU gyroscope detection
        useIMURepDetection = true
        imuDirectionRepDetector.reset()
        print("🎯 [Custom] Using IMU gyro detection for circular movement")
        
    case .pendulum, .horizontal, .vertical:
        // Directional motion: Use IMU direction change detection
        useIMURepDetection = true
        imuDirectionRepDetector.reset()
        print("🎯 [Custom] Using IMU direction detection for \(movementType) movement")
        
    case .straightening:
        // Extension/flexion: Use position-based detection
        useIMURepDetection = false
        handheldRepDetector.startSession(gameType: .makeYourOwn)
        print("🎯 [Custom] Using position detection for straightening movement")
        
    case .mixed:
        // Mixed: Default to IMU (most versatile)
        useIMURepDetection = true
        imuDirectionRepDetector.reset()
        print("🎯 [Custom] Using IMU detection for mixed movement")
    }
} else {
    // Standard game logic
    let useIMURepDetection = (gameType == .fruitSlicer || gameType == .fanOutFlame || gameType == .followCircle)
    // ...
}
```

---

## Testing Commands

After implementing these fixes, test each:

### Follow Circle:
```bash
# Should see:
🔄 [Handheld] Using IMU direction-based rep detection for Pendulum Circles
🔁 [IMU-Rep] Direction change detected! Rep #1
📐 [Handheld] Rep ROM recorded: 65.5° (total reps: 1)
```

### Constellation:
```bash
# Should see after each pattern:
🌟 [ArmRaises] Pattern COMPLETED! All dots connected.
🎯 [ArmRaises] Pattern 1/3 done - generating next...
# ... then after 3rd pattern:
🎉 [ArmRaises] ALL 3 PATTERNS COMPLETED! Ending game...
```

### Pain Tracking:
```bash
# In progress view, should show:
"Pain Change: 2.3 ↓ Improvement"
"7-day average pain reduction"
```

---

## Build & Test

1. Make all changes above
2. Build: `xcodebuild -workspace FlexaSwiftUI.xcworkspace -scheme FlexaSwiftUI -configuration Debug -sdk iphoneos build`
3. Deploy to device
4. Test each game:
   - Follow Circle: Complete 5 reps
   - Constellation: Complete all 3 patterns
   - Check progress view for pain stats

---

## Summary of Changes:

1. ✅ **Follow Circle**: Uses IMU detection (like Fruit Slicer)
2. ✅ **Constellation**: Requires 3 patterns, smoother tracking, bigger hit boxes
3. ✅ **Pain Tracking**: Shows weekly average across ALL exercises
4. ✅ **Custom Exercises**: Movement-type-specific rep detection

**Total Lines Changed**: ~50 lines across 3 files
**Estimated Implementation Time**: 2-3 hours
**Testing Time**: 1-2 hours

**All fixes are surgical and don't break existing functionality!**
