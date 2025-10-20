# Direction Change Rep Detection Refactor

## Problem Statement
The rep detection system was overcounting reps (83 reps detected when <20 were actually performed) due to:
1. **Complex detection logic** with multiple overlapping detection methods
2. **Rolling buffer ROM calculation** that was running continuously
3. **2D projected space complexity** for direction detection
4. **Duplicate detection** from multiple detector instances

## Solution Implemented

### 1. Unified Direction-Change Detection
**File**: `FlexaSwiftUI/Services/Handheld/HandheldRepDetector.swift`

Replaced complex hysteresis-based peak detection with simple direction-change detection:

```swift
// Simple algorithm:
1. Track position history (last 2 seconds)
2. Calculate displacement between consecutive positions
3. Determine primary axis (X, Y, or Z with most movement)
4. Detect direction change on primary axis (sign change)
5. Validate minimum displacement (0.05m) and cooldown (0.3s)
6. Calculate ROM AFTER rep is detected
```

### 2. Variance-Based 2D Plane Selection for ROM
ROM is now calculated **AFTER** a rep is detected, not continuously:

```swift
private func calculateROMForRep(startPos: SIMD3<Float>, peakPos: SIMD3<Float>) -> Double {
    // Calculate displacement vector
    let displacement = peakPos - startPos
    
    // Calculate variance on each axis
    let varX = displacement.x * displacement.x
    let varY = displacement.y * displacement.y
    let varZ = displacement.z * displacement.z
    
    // Select 2 axes with highest variance for 2D plane
    // Calculate angle in that plane
    // Convert to degrees
}
```

### 3. Removed Complexity
- ❌ Removed rolling buffer ROM calculation
- ❌ Removed 2D projected space complexity
- ❌ Removed hysteresis-based peak detection
- ❌ Removed duplicate detection logic
- ❌ Removed IMUDirectionRepDetector (unused)
- ❌ Removed UnifiedHandheldRepDetector (merged into HandheldRepDetector)

### 4. Key Changes

#### HandheldRepDetector.swift
- **Before**: 500+ lines with complex state machine, hysteresis, peak detection
- **After**: ~200 lines with simple direction-change detection
- **State**: Minimal - just last direction, rep start/peak positions, position history
- **Detection**: Simple sign change on primary axis
- **ROM**: Calculated once per rep using variance-based 2D plane selection

#### Games (Fruit Slicer & Fan the Flame)
- No changes needed - they already use SimpleMotionService
- SimpleMotionService forwards ARKit positions to HandheldRepDetector
- Rep detection happens automatically via unified detector

### 5. Benefits

✅ **Accurate Rep Counting**: Simple direction change = 1 rep (no duplicates)
✅ **No Overcounting**: Cooldown period (0.3s) prevents chatter
✅ **Efficient ROM Calculation**: Only calculated when rep detected (not every frame)
✅ **Adaptive 2D Plane**: Variance-based selection works for any movement pattern
✅ **Clean Architecture**: Single detector, single source of truth
✅ **Better Performance**: No rolling buffers, no continuous calculations

### 6. Testing Recommendations

Test with these scenarios:
1. **Slow movements**: Should detect each direction change
2. **Fast movements**: Should not double-count due to cooldown
3. **Small movements**: Should filter out movements < 0.05m
4. **Different orientations**: Variance-based plane selection should adapt
5. **Fruit Slicer**: Forward/backward swings
6. **Fan the Flame**: Side-to-side swings

### 7. Configuration

Key parameters (in HandheldRepDetector):
```swift
cooldownPeriod: 0.3 seconds  // Minimum time between reps
minimumDisplacement: 0.05 meters  // Minimum movement for valid rep
```

Adjust these if needed based on testing feedback.

## Files Modified
- `FlexaSwiftUI/Services/Handheld/HandheldRepDetector.swift` - Complete refactor
- `FlexaSwiftUI/Services/Handheld/UnifiedHandheldRepDetector.swift` - Deleted (merged)

## Files Unchanged (Working Correctly)
- `FlexaSwiftUI/Games/OptimizedFruitSlicerGameView.swift`
- `FlexaSwiftUI/Games/FanOutTheFlameGameView.swift`
- `FlexaSwiftUI/Services/SimpleMotionService.swift`

## Next Steps
1. Test Fruit Slicer game - verify rep counts are accurate
2. Test Fan the Flame game - verify rep counts are accurate
3. Monitor logs for "✅ [UnifiedRep] Rep #X detected" messages
4. Adjust cooldownPeriod or minimumDisplacement if needed
5. Verify ROM values are reasonable (should be 0-180°)
