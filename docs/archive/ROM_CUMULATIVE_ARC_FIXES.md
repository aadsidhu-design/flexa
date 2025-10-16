# ROM Cumulative Arc Calculation & Restriction Removal

**Date**: October 6, 2025  
**Changes**: Complete overhaul of ROM calculation to use cumulative arc approach instead of peak-to-peak

## Summary of Changes

This update fundamentally changes how ROM (Range of Motion) is calculated across all games in FlexaSwiftUI. Previously, the system used a "peak-to-peak" approach that measured movement between detected peaks. Now, it uses a **cumulative arc approach** that measures the entire movement arc from start to the furthest point reached.

## Key Philosophy Changes

### Before (Peak-to-Peak):
- Detected multiple peaks in the movement
- Calculated ROM between consecutive peaks
- Limited ROM to physiological maximums (90°, 150°, 180° depending on joint)
- Rejected reps below 15° threshold
- Restricted circle radius to minimum 8cm

### After (Cumulative Arc):
- Measure ENTIRE arc from start position to furthest point (peak)
- Calculate cumulative arc length along the path drawn in 3D space
- Convert arc length to angle using: `angle = arcLength / armRadius`
- **NO restrictions**: Accept all ROM values, even > 180°
- **NO minimum thresholds**: Accept all detected reps regardless of size
- **NO radius restrictions**: Accept all circles regardless of size

## Files Modified

### 1. `UnifiedRepROMService.swift`

**Accelerometer Rep Detection** (Lines 182-201):
- **Removed**: 15° minimum ROM threshold check
- **Changed**: Now accepts all detected reps immediately after calculating ROM
- Movement detection triggers immediately on direction reversal, no ROM filtering

**Circle Detection** (Lines 249-257):
- **Removed**: 0.08m (8cm) minimum radius restriction
- **Changed**: `minRadius` parameter now set to 0.0
- Accepts circles of any size

**ROM Validation** (Lines 330-368):
- **Removed**: All physiological ROM capping (was capping at 45°-180° depending on joint)
- **Removed**: Maximum ROM limits per joint type
- **Changed**: Now returns raw ROM value without clamping
- Only logs informational messages about typical ranges, doesn't enforce them

**ARKit Circle State** (Lines 690-703):
- **Modified**: Circle radius check now only applies if minRadius > 0
- When minRadius is 0.0, accepts all circle sizes

### 2. `Universal3DROMEngine.swift`

**Main ROM Calculation** (`calculateROMAndReset()`, Lines 230-270):
- **Complete rewrite**: Dead simple cumulative arc through ALL points
- **Algorithm**:
  1. Find optimal 2D projection plane (removes phone tilt bias)
  2. Project all 3D positions to 2D plane
  3. Calculate total arc length through ALL points (sum of segment lengths)
  4. Convert to angle: `ROM = (arcLength / armRadius) × 180 / π`
- **Removed**: ALL peak detection logic (unnecessary!)
- **Removed**: ALL segmentation logic (unnecessary!)
- **Removed**: 180° upper limit clamping
- Returns raw ROM value with only lower bound of 0°

**Segment ROM Calculation** (`calculateROMForSegment()`, Lines 1015-1090):
- **Circle ROM** (Lines 1015-1056):
  - **Removed**: 90° cap for circle movements
  - Now allows ROM > 90° if user moves arm more
  
- **Pendulum/Arc ROM** (Lines 1057-1090):
  - **Changed**: Updated comments to emphasize "cumulative arc" approach
  - Calculates arc length from start to peak position only
  - **Removed**: 180° cap for pendulum movements

**Projected Movement ROM** (`calculateROMFromProjectedMovement()`, Lines 1141-1173):
- **Removed**: 180° upper limit clamping
- Returns raw angle value with only 0° lower bound

**Live ROM Calculation** (`calculateLiveROMWithPeakDetection()`, Lines 449-563):
- **Circle movements**: Removed 90° cap
- **Pendulum movements**: Removed 180° cap
- Both now return unclamped ROM values

## Technical Details

### Cumulative Arc Formula

The core calculation is beautifully simple:

```swift
// 1. Project all 3D positions to optimal 2D plane
let projected2D = rawPositions.map { projectPointTo2DPlane($0, plane: projectionPlane) }

// 2. Calculate TOTAL arc length through ALL points (the entire path)
var arcLength = 0.0
for i in 1..<projected2D.count {
    let segmentLength = simd_length(projected2D[i] - projected2D[i-1])
    arcLength += segmentLength
}

// 3. Convert to angle
let gripOffset = 0.15  // meters
let armRadius = armLength + gripOffset
let angleRadians = arcLength / armRadius
let rom = angleRadians * 180.0 / .pi
```

Think of it as: Phone draws arc in 3D → Project to 2D → Measure entire arc length → Done!

### Why This Works Better

1. **Dead simple**: No peak detection, no segmentation, just measure the arc drawn in space
2. **Captures actual movement**: The phone draws an arc, we measure that exact arc
3. **No information loss**: Every point contributes to the arc length measurement
4. **Natural intuition**: "I drew this arc with my phone, measure its length" - that's it!
5. **Respects user capability**: Doesn't artificially limit what the user can achieve

### Validation Changes

Previously, ROM was validated and clamped based on joint type:
- Shoulder: capped at 180°
- Elbow: capped at 150°  
- Rotation: capped at 90°
- Scapular: capped at 45°

Now, validation only:
- Checks if ROM is within typical therapeutic ranges (informational only)
- Marks as "therapeutic" or not based on minimum thresholds
- Returns **raw measured value** without any clamping

## Impact on Games

### Handheld Games (Fruit Slicer, Fan the Flame, Follow Circle)
- Will now measure the FULL arc of each swing/circle
- ROM can exceed previous limits (e.g., > 180° for vigorous swings)
- Small movements (< 15°) now count as valid reps
- Tiny circles now count as valid reps

### Camera Games (Balloon Pop, Wall Climbers, Constellation)
- No restrictions on measured joint angles
- Can measure hyperextension and unusual positions
- Therapeutic feedback still provided but not enforced

## Testing Recommendations

1. **Baseline Test**: Perform known ROM movements and verify measured values match expected
2. **Edge Cases**: Test very small movements (< 15°), very large movements (> 180°)
3. **Circles**: Test tiny circles (< 8cm) and verify they're detected
4. **Rep Count**: Verify rep detection works correctly without ROM filtering
5. **Graph Display**: Check that ROM graphs display correctly without clamping artifacts

## Potential Issues to Monitor

1. **Outlier Values**: Without clamping, sensor noise might produce ROM > 300°
   - **Mitigation**: Physics-based validation in UI layer if needed
   
2. **Rep Overcounting**: Removing 15° threshold might count fidgeting as reps
   - **Mitigation**: Debounce timers and acceleration thresholds still in place
   
3. **User Confusion**: Users might see ROM values they don't understand
   - **Mitigation**: Educational content about ROM measurement

## Performance Impact

- **Positive**: Removed complex peak detection logic (simpler = faster)
- **Neutral**: Arc length calculation has same O(n) complexity as before
- **Memory**: No change (still using BoundedArray for position history)

## Logging Changes

New log messages to watch for:

```
📐 [ROM-FullArc] 120 points, TotalArc=0.234m, Radius=0.75m → ROM=17.9°
```

This shows:
- Total number of points in the arc
- Total measured arc length in meters
- Effective arm radius
- Final ROM in degrees

## Reverting if Needed

If issues arise, the previous peak-to-peak logic can be restored by:
1. Reverting `Universal3DROMEngine.calculateROMAndReset()`
2. Re-adding ROM validation clamping in `UnifiedRepROMService.validateROM()`
3. Re-enabling minimum thresholds in `detectRepViaAccelerometer()` and `detectRepViaARKitCircle()`

Previous implementation is preserved in git history.

## Related Documentation

- `ULTIMATE_SIMPLE_ROM.md` - Original ROM calculation philosophy
- `SIMPLIFIED_ROM_SYSTEM.md` - Previous ROM architecture
- `COMPREHENSIVE_ROM_SPARC_AUDIT.md` - Historical ROM system audit
- `NO_ROM_LIMITS_UPDATE.md` - Previous attempt at removing limits

---

**Build Status**: ✅ Successful (October 6, 2025)  
**Warnings**: 4 (all pre-existing, unrelated to changes)
