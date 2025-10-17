# False Rep Detection Fix

**Date:** October 15, 2024  
**Issue:** Rep detector misfiring - many tiny ROM values (0.0, 1.2, 3.7...)  
**Status:** ⚙️ IN PROGRESS

---

## Problem Analysis

**ROM per Rep data shows false reps:**
```
0.0, 10.8, 23.7, 51.2, 84.9, 1.2, 89.8, 92.6, 3.7, 82.0, 0.0, 83.9, 1.3, 37.4, 41.0, 27.8, 42.6, 14.8, 85.1, 36.7, 51.8, 1.4, 78.9, 8.3, 47.6, 23.6, 5.7, 73.0, 74.1, 7.4, 73.8, 6.9, 56.9, 7.3...
```

**Many values < 15°:**
- 0.0, 1.2, 3.7, 0.0, 1.3, 1.4, 8.3, 5.7, 7.4, 6.9, 7.3, 0.0, 8.7, 1.6, 7.2, 1.0, 2.1, 0.0...

**This suggests:**
- Rep detector triggering when no actual rep occurred
- Phone jitter/drift being counted as direction changes
- Thresholds too sensitive

---

## Root Cause

**Kalman IMU detector was too sensitive:**

**OLD Thresholds:**
```swift
velocityThreshold = 0.3 rad/s    // Direction change threshold
minRepAmplitude = 0.8 rad/s      // Minimum velocity swing
repCooldown = 0.25s              // Time between reps
```

**Problem:** Small movements (phone adjustments, hand tremor) were exceeding thresholds and being counted as reps.

---

## Solution Applied

### Increased Thresholds

**NEW Thresholds:**
```swift
velocityThreshold = 0.4 rad/s    // +33% - less sensitive to drift
minRepAmplitude = 1.2 rad/s      // +50% - requires larger movement
repCooldown = 0.35s              // +40% - more time between reps
```

**Impact:**
- Requires more deliberate movement to count as rep
- Filters out phone adjustments and hand tremor
- Prevents rapid-fire false reps

### Added Detailed Logging

**Track why reps are detected:**
```swift
// In KalmanIMURepDetector
FlexaLog.motion.debug("🔄 [KalmanIMU] Rep #\(reps) detected - amplitude: \(String(format: "%.2f", amplitude)) rad/s")

// In HandheldROMCalculator
FlexaLog.motion.info("📐 [ROMCalculator] Rep completed - ROM: \(String(format: "%.1f°", repROM)), samples: \(sampleCount), arcLength: \(String(format: "%.3f", arcLength))m")

// Warn on suspicious reps
if repROM < 15.0 {
    FlexaLog.motion.warning("⚠️ [ROMCalculator] Low ROM detected (\(String(format: "%.1f°", repROM))) - possible false rep!")
}
```

**This will show:**
- Gyroscope amplitude when rep detected
- Number of position samples collected
- Arc length traveled
- Warnings for suspicious low ROM values

---

## Expected Behavior After Fix

### Clean ROM Values

**Should see:**
```
45.3, 48.1, 42.7, 51.2, 46.8, 49.3, 44.5, 47.9, 50.1, 43.2...
```

**Should NOT see:**
```
45.3, 1.2, 48.1, 0.0, 3.7, 42.7, 8.3...  ← False reps!
```

### Log Patterns

**Good (Real Rep):**
```
🔄 [KalmanIMU] Rep #1 detected - amplitude: 1.85 rad/s
📐 [ROMCalculator] Rep completed - ROM: 45.3°, samples: 87, arcLength: 0.325m
```

**Bad (False Rep):**
```
🔄 [KalmanIMU] Rep #2 detected - amplitude: 0.95 rad/s  ← Barely above threshold!
📐 [ROMCalculator] Rep completed - ROM: 3.7°, samples: 12, arcLength: 0.015m
⚠️ [ROMCalculator] Low ROM detected (3.7°) - possible false rep!
```

---

## Threshold Tuning Guide

### If Still Too Many False Reps

**Increase thresholds further:**
```swift
velocityThreshold = 0.5 rad/s    // Even less sensitive
minRepAmplitude = 1.5 rad/s      // Require even larger movement
repCooldown = 0.4s               // More spacing
```

### If Missing Real Reps

**Decrease thresholds slightly:**
```swift
velocityThreshold = 0.35 rad/s   // Slightly more sensitive
minRepAmplitude = 1.0 rad/s      // Allow smaller movements
repCooldown = 0.3s               // Less spacing
```

### Optimal Range

| Threshold | Too Low | Optimal | Too High |
|-----------|---------|---------|----------|
| **velocityThreshold** | 0.2-0.3 | **0.4-0.5** | 0.6+ |
| **minRepAmplitude** | 0.5-0.8 | **1.2-1.5** | 2.0+ |
| **repCooldown** | 0.15-0.2s | **0.35-0.4s** | 0.5s+ |

---

## SPARC Issue (Separate)

**Also noticed: SPARC = 0.0**

This is a separate issue from false reps. The SPARC calculation depends on ARKit position data being collected properly.

**Check:**
1. Are ARKit positions being collected? (`arkitPositionHistory`)
2. Is ARKitSPARCAnalyzer being called?
3. Is timeline being generated correctly?

**Log to check:**
```
📊 [AnalyzingView] Calculating ARKit-based SPARC from X position samples
```

If X = 0 or very low, ARKit positions aren't being collected.

---

## Files Modified

1. **KalmanIMURepDetector.swift**
   - Line 87-90: Increased thresholds
   - Logging added

2. **HandheldROMCalculator.swift**
   - Lines 201-210: Added detailed logging and warnings

---

## Next Steps

1. **Test with logging enabled**
   - Play Fruit Slicer
   - Check logs for false rep warnings
   - Verify ROM values are consistent (no tiny values)

2. **If false reps persist:**
   - Increase thresholds further
   - Consider adding minimum sample count requirement

3. **Fix SPARC calculation:**
   - Verify ARKit positions collecting
   - Check analyzer being called
   - Ensure timeline generated

---

## Build Status

✅ **BUILD SUCCEEDED**

---

## Summary

Increased Kalman IMU detection thresholds by 33-50% to reduce false rep detection. Added detailed logging to track amplitude, sample counts, and arc lengths. This should eliminate the tiny ROM values (0.0, 1.2, 3.7...) caused by phone jitter being misdetected as reps.

**Key Changes:**
- velocityThreshold: 0.3 → 0.4 rad/s
- minRepAmplitude: 0.8 → 1.2 rad/s
- repCooldown: 0.25s → 0.35s

Test and adjust as needed based on log output.
