# Handheld Rep Detection Improvements

## Summary
Fixed false positive rep detection issues in handheld games (Fruit Slicer, Fan Out Flame) by improving the IMU-based rep detection system.

## Problems Fixed

### 1. False Positives at Session Start
**Issue**: Many false "0 reps" were being detected at the start of sessions before everything was initialized.

**Solution**: Added initialization gate that skips the first accelerometer reading to allow ARKit and IMU sensors to stabilize.

### 2. Accelerometer Already Used (Not Gyroscope)
**Confirmed**: The system was already using accelerometer (`userAcceleration`) for direction change detection, not gyroscope. This is the correct approach for pendulum-style movements.

### 3. Minimum ROM Threshold
**Issue**: Small movements (< 5 degrees) were being counted as reps.

**Solution**: Added 5-degree minimum ROM threshold. The detector now:
- Tracks peak acceleration in each direction
- Estimates ROM from acceleration magnitude
- Only counts reps that exceed 5 degrees of movement

### 4. ARKit Readiness Gate
**Issue**: Rep detection could start before ARKit tracking was stable.

**Solution**: 
- Rep detection only processes data when `arkitReady` flag is true
- ARKit must be in "Normal" tracking state for 0.5 seconds before readiness
- `arkitReady` flag is now properly reset when ARKit stops

## Technical Changes

### IMUDirectionRepDetector.swift
```swift
// Added properties:
- isInitialized: Bool = false          // Skip first reading
- accelerationThreshold: 0.25          // Increased from 0.15
- minimumROMThreshold: 5.0             // New ROM filter
- peakPositiveAccel: Double = 0        // Track movement magnitude
- peakNegativeAccel: Double = 0        // Track movement magnitude

// Enhanced processAcceleration():
1. Skip first reading for initialization
2. Track peak acceleration in each direction
3. Estimate ROM from acceleration magnitude
4. Filter out reps below 5-degree threshold
5. Log rejected reps for debugging
```

### SimpleMotionService.swift
```swift
// Enhanced updateIsARKitRunning():
- Reset arkitReady flag when ARKit stops
- Reset arkitReadySince timestamp
- Prevents false positives on session restart
```

## How It Works Now

1. **Session Start**: 
   - ARKit starts tracking
   - IMU rep detector resets (including initialization flag)
   - `arkitReady` = false

2. **Initialization Period**:
   - First accelerometer reading is skipped
   - ARKit must achieve "Normal" tracking for 0.5s
   - Once stable, `arkitReady` = true

3. **Rep Detection Active**:
   - Accelerometer tracks dominant axis movement
   - Peak acceleration recorded in each direction
   - On direction reversal:
     - Estimate ROM from peak accelerations
     - If ROM >= 5°, count as rep
     - If ROM < 5°, ignore and log

4. **Session End**:
   - ARKit stops
   - `arkitReady` reset to false
   - Ready for clean restart

## Expected Behavior

### Before Fix
- ❌ False "Rep #0" detections at start
- ❌ Tiny movements counted as reps
- ❌ Inconsistent rep counting

### After Fix
- ✅ Clean session start with no false positives
- ✅ Only meaningful movements (>5°) count as reps
- ✅ Stable rep detection after initialization
- ✅ Better logging for debugging

## Testing Recommendations

1. **Start Session Test**:
   - Start Fruit Slicer or Fan Out Flame
   - Hold phone still for 2 seconds
   - Should see "Initialized" log but no rep counts

2. **Small Movement Test**:
   - Make tiny wrist movements
   - Should see "ROM too small" rejection logs
   - No reps should be counted

3. **Normal Rep Test**:
   - Make full pendulum swings
   - Should count reps normally
   - ROM should be reasonable (20-60°)

4. **Restart Test**:
   - Complete a session
   - Start new session immediately
   - Should not carry over any state from previous session

## Debug Logs to Watch

```
🔄 [IMU-Rep] Initialized - starting rep detection
🔄 [IMU-Rep] Direction change detected! -1 → 1 | Rep #1 | ROM: 35.2° | Accel: 0.450 m/s²
🔄 [IMU-Rep] Direction change ignored - ROM too small (3.8° < 5.0°)
📍 [InstantARKit] ARKit ready — enabling handheld ROM/rep processing
```

## Files Modified
- `FlexaSwiftUI/Services/IMUDirectionRepDetector.swift`
- `FlexaSwiftUI/Services/SimpleMotionService.swift`

## Date
October 14, 2025
