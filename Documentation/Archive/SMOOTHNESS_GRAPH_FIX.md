# Smoothness Graph Fix

**Date:** October 15, 2024  
**Issue:** Smoothness graph not displaying in ResultsView  
**Status:** ✅ FIXED

---

## Problem

The smoothness graph in ResultsView was not displaying any data. The issue was twofold:

1. **Wrong Value Range:** SPARC timeline values were in -3.0 to 0.0 range instead of 0-100
2. **Chart expects 0-100:** ResultsView chart configured with `chartYScale(domain: 0...100)`

---

## Root Cause

In `ARKitSPARCAnalyzer.swift`, the `createTimeline()` function was creating SPARCPoint objects with smoothness values in the wrong range:

```swift
// OLD - Wrong range!
let smoothness = max(-3.0, min(0.0, -localJerk * 8.0))

timeline.append(SPARCPoint(
    sparc: smoothness,  // -3.0 to 0.0 range
    timestamp: Date(timeIntervalSince1970: sample.timestamp)
))
```

**Problem:** Chart expects 0-100, but was getting -3.0 to 0.0 values, which don't display properly.

---

## Solution

Fixed the `createTimeline()` function to properly convert jerk to 0-100 smoothness scale:

```swift
// NEW - Correct 0-100 range!
// Convert jerk to 0-100 smoothness scale
let normalizedJerk = min(1.0, abs(localJerk) / 5.0) // Normalize jerk (typical range 0-5)
let smoothnessPercent = (1.0 - normalizedJerk) * 100.0 // Invert and scale to percentage
let finalSmoothness = max(0.0, min(100.0, smoothnessPercent))

timeline.append(SPARCPoint(
    sparc: finalSmoothness,  // Now 0-100 range!
    timestamp: Date(timeIntervalSince1970: sample.timestamp)
))
```

---

## Conversion Logic

### Jerk to Smoothness Mapping

1. **Normalize Jerk:** `normalizedJerk = min(1.0, abs(jerk) / 5.0)`
   - Typical jerk range: 0-5 m/s³
   - Normalizes to 0.0-1.0 range
   - Values > 5 clamped to 1.0

2. **Invert to Smoothness:** `smoothnessPercent = (1.0 - normalizedJerk) * 100.0`
   - Low jerk (0.0) → High smoothness (100%)
   - High jerk (1.0) → Low smoothness (0%)

3. **Clamp:** `finalSmoothness = max(0.0, min(100.0, smoothnessPercent))`
   - Ensures values stay in 0-100 range

### Examples

| Jerk (m/s³) | Normalized Jerk | Smoothness (%) |
|-------------|-----------------|----------------|
| 0.0 | 0.0 | 100% |
| 1.0 | 0.2 | 80% |
| 2.5 | 0.5 | 50% |
| 5.0 | 1.0 | 0% |
| 10.0 | 1.0 (clamped) | 0% |

---

## File Modified

**File:** `FlexaSwiftUI/Services/Handheld/ARKitSPARCAnalyzer.swift`

**Function:** `createTimeline(samples:velocities:jerks:)`

**Lines Changed:** 366-375

---

## How Data Flows

### During Gameplay
1. ARKit positions collected at 60fps
2. Stored in `SimpleMotionService.arkitPositionHistory`

### Post-Game (Analyzing Screen)
1. `AnalyzingView` calls `ARKitSPARCAnalyzer.analyze()`
2. Analyzer computes velocities, accelerations, jerks
3. `createTimeline()` creates SPARCPoint array with **0-100 smoothness values**
4. Timeline assigned to `enhancedData.sparcData`
5. ResultsView displays the graph

### ResultsView Display
```swift
// Smoothness tab
Chart {
    ForEach(sessionData.sparcData, id: \.offset) { _, point in
        LineMark(
            x: .value("Time (s)", point.timestamp.timeIntervalSince(start)),
            y: .value("Smoothness", point.sparc)  // Now 0-100!
        )
    }
}
.chartYScale(domain: 0...100)  // Matches data range
```

---

## Testing

### Expected Behavior

**Before Fix:**
- Smoothness graph shows "No smoothness data available"
- OR graph appears empty/blank
- sparcData values are -3.0 to 0.0 (out of chart range)

**After Fix:**
- Smoothness graph displays green line
- Values range from 0-100%
- Smooth motion shows higher values (70-100%)
- Jerky motion shows lower values (0-30%)

### Log Verification

Look for this log after game ends:
```
📊 [AnalyzingView] ✨ NEW ARKit-based SPARC computed:
   Overall Score: -1.23
   Smoothness: 75%
   Per-rep scores: 12 values
   Peak Velocity: 1.45m/s
   Jerkiness: 0.234
```

And in ARKitSPARCAnalyzer:
```
📊 [ARKitSPARC] Analysis complete: score=-1.23 smooth=75% vel=1.45m/s jerk=0.234
```

The key is **smooth=75%** showing a 0-100 value.

---

## Related Code

### SPARCPoint Definition
```swift
struct SPARCPoint: Codable {
    let sparc: Double  // Should always be 0-100 for display
    let timestamp: Date
}
```

### Chart Configuration in ResultsView
```swift
.chartYScale(domain: 0...100)
.chartYAxis { AxisMarks(position: .leading) { value in
    AxisValueLabel {
        if let v = value.as(Double.self) {
            Text("\(String(format: "%.0f", v))%")  // Shows percentage
                .foregroundColor(.white)
        }
    }
}}
```

---

## Build Status

✅ **BUILD SUCCEEDED**

---

## Summary

Fixed smoothness graph by converting SPARC timeline values from -3.0 to 0.0 range to proper 0-100 percentage range. Graph now displays correctly in ResultsView after games complete.

**Key Change:** Normalize jerk values and convert to 0-100 smoothness percentage before creating SPARCPoint objects.
