# ROM Graph Spike Fix

## Problem
The ROM graph in the Analyzing view was showing wild spikes from 0° to 90° to 0° to 90° repeatedly, instead of staying relatively flat around 90° for a pendulum swing exercise where the user was moving their arm from in front to above their head (both 90° movements).

## Root Cause
The issue was in the **live ROM calculation** for the sliding window in `Universal3DROMEngine.swift`. The `updateLiveROMWindow()` function was using `calculateROMForSegment()` directly, which calculates ROM for a complete segment/rep. 

However, the live ROM window accumulates positions over 2.5 seconds without resetting. For pendulum swings:
1. User swings forward → positions accumulate, ROM increases to ~90°
2. User swings back → positions **continue to accumulate** (window doesn't reset at peak)
3. Arc length calculation keeps growing beyond the peak
4. ROM hits the 180° cap
5. When a rep is detected, positions are reset → ROM drops to 0°
6. Cycle repeats → creates spike pattern

## Solution
Created a new function `calculateLiveROMWithPeakDetection()` that matches the per-rep ROM calculation logic:

### Key Changes in `Universal3DROMEngine.swift`

**Before:**
```swift
private func updateLiveROMWindow(with position: SIMD3<Double>, timestamp: TimeInterval) {
    liveROMPositions.append(position)
    liveROMTimestamps.append(timestamp)
    pruneLiveROMWindow(latestTimestamp: timestamp)
    guard liveROMPositions.count >= 8 else { return }
    let pattern = detectMovementPattern(liveROMPositions)
    
    // ❌ Problem: This calculates ROM for the entire accumulated path
    let rom = calculateROMForSegment(liveROMPositions, pattern: pattern)
    
    guard rom.isFinite else { return }
    DispatchQueue.main.async { [weak self] in
        self?.onLiveROMUpdated?(rom)
    }
}
```

**After:**
```swift
private func updateLiveROMWindow(with position: SIMD3<Double>, timestamp: TimeInterval) {
    liveROMPositions.append(position)
    liveROMTimestamps.append(timestamp)
    pruneLiveROMWindow(latestTimestamp: timestamp)
    guard liveROMPositions.count >= 8 else { return }
    let pattern = detectMovementPattern(liveROMPositions)
    
    // ✅ Fixed: Use peak detection to prevent accumulation
    let rom = calculateLiveROMWithPeakDetection(liveROMPositions, pattern: pattern)
    
    guard rom.isFinite else { return }
    DispatchQueue.main.async { [weak self] in
        self?.onLiveROMUpdated?(rom)
    }
}

/// Calculate live ROM with peak detection to prevent accumulation
/// This ensures live ROM matches per-rep ROM calculation logic
private func calculateLiveROMWithPeakDetection(_ positions: [SIMD3<Double>], pattern: MovementPattern) -> Double {
    guard positions.count >= 2 else { return 0.0 }
    
    // Step 1: Find optimal 2D projection plane
    let projectionPlane = findOptimalProjectionPlane(positions)
    let projected2DPath = positions.map { projectPointTo2DPlane($0, plane: projectionPlane) }
    
    // Step 2: Calculate grip-adjusted arm radius
    let gripOffset = 0.15
    let armRadius = armLength + gripOffset
    
    var angleDegrees: Double
    
    if currentGameType == .followCircle || pattern == .circle {
        // CIRCLE: Right triangle method (unchanged)
        var centerSum = SIMD2<Double>(0, 0)
        for point in projected2DPath {
            centerSum += point
        }
        let center = centerSum / Double(projected2DPath.count)
        
        var maxRadius: Double = 0.0
        for point in projected2DPath {
            let distanceFromCenter = simd_length(point - center)
            maxRadius = max(maxRadius, distanceFromCenter)
        }
        
        let ratio = min(1.0, maxRadius / armRadius)
        let angleRadians = asin(ratio)
        angleDegrees = angleRadians * 180.0 / .pi
        angleDegrees = min(angleDegrees, 90.0)
        
    } else {
        // PENDULUM/ARC: PEAK DETECTION
        // ✅ Key Fix: Find the furthest point from start (peak of swing)
        let startPos = projected2DPath.first!
        var maxDistanceFromStart: Double = 0.0
        var peakIndex = 0
        
        for (index, point) in projected2DPath.enumerated() {
            let distanceFromStart = simd_length(point - startPos)
            if distanceFromStart > maxDistanceFromStart {
                maxDistanceFromStart = distanceFromStart
                peakIndex = index
            }
        }
        
        // ✅ Only calculate arc length UP TO THE PEAK (not beyond)
        // This prevents accumulation when swinging back
        let relevantPath = Array(projected2DPath[0...peakIndex])
        
        var arcLength: Double = 0.0
        for i in 1..<relevantPath.count {
            let segmentLength = simd_length(relevantPath[i] - relevantPath[i-1])
            arcLength += segmentLength
        }
        
        let angleRadians = arcLength / armRadius
        angleDegrees = angleRadians * 180.0 / .pi
        angleDegrees = min(angleDegrees, 180.0)
    }
    
    return max(0.0, angleDegrees)
}
```

## Why This Works

### Before the Fix:
- Live ROM window: [positions 1-100] accumulated over 2.5 seconds
- User swings forward (positions 1-40): ROM = 90°
- User swings back (positions 41-100): ROM = 180° (accumulated path length)
- **Result**: ROM spikes to 180° instead of staying at 90°

### After the Fix:
- Live ROM window: [positions 1-100] accumulated over 2.5 seconds
- Peak detection finds position 40 as the furthest from start
- Arc length calculated only for positions 1-40 (ignoring 41-100)
- **Result**: ROM stays at 90° even as user swings back

## Verification
The per-rep ROM calculation (`calculateROMForSegment`) already had peak detection implemented correctly. This fix ensures the **live ROM updates** match the **per-rep ROM calculation** logic.

### Expected Behavior After Fix:
1. **Pendulum Swing**: Graph should show flat line around 90° (not spiking up/down)
2. **Circular Motion**: Should still work correctly (uses different calculation method)
3. **Live HUD**: Should display stable ROM values during gameplay

## Related Files
- `FlexaSwiftUI/Services/Universal3DROMEngine.swift` - Main fix location
- `FlexaSwiftUI/Views/AnalyzingView.swift` - Displays ROM graph
- `FlexaSwiftUI/Views/ResultsView.swift` - Shows final ROM chart

## Testing Notes
Test on physical device with pendulum swing exercise:
1. Move arm from front (0°) to overhead (90°) and back
2. ROM should remain relatively stable around 90°
3. Graph should not spike between 0° and 180°
4. Per-rep ROM values should be consistent

Build Status: ✅ BUILD SUCCEEDED
