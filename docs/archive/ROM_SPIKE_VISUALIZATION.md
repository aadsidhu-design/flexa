# ROM Graph Spike Issue - Visual Explanation

## What You Saw in the Logs

```
📐 [ROM-Arc] Peak at index 150/151, Arc=2.949m / Radius=0.67m = 180.0°
🍎 [ROM Normalize] Fruit Slicer passthrough → ROM=180.0°
🍎 [ROM Normalize] Fruit Slicer passthrough → ROM=180.0°
🍎 [ROM Normalize] Fruit Slicer passthrough → ROM=95.6°
📐 [ROM-Arc] Peak at index 150/151, Arc=2.949m / Radius=0.67m = 180.0°
🍎 [ROM Normalize] Fruit Slicer passthrough → ROM=180.0°
```

The ROM was hitting 180° (the cap), then suddenly dropping to lower values, creating the spike pattern you described.

## The Problem Visualized

### Your Movement (Pendulum Swing):
```
Front (0°) → Overhead (90°) → Back to Front (0°) → Overhead (90°) ...
```

### What Was Being Measured (BEFORE FIX):

```
Time Window (2.5 seconds of accumulated positions):

Position Array: [1, 2, 3, ... 40, 41, 42, ... 100]
                 ←Forward→  ←Peak  ←Backward→

Arc Calculation:
- Measures path from 1 → 2 → 3 → ... → 40 (forward swing)
- THEN adds 40 → 41 → 42 → ... → 100 (backward swing)
- Total arc length = forward path + backward path
- Result: ROM = 180° (way too high!)

Visualization:
         Peak (40)
            *
           /  \
          /    \
         /      \
Start  *        * Current (100)
(1)              
        
Arc measured: ~~~~~~~~ (entire curved path, both directions)
ROM calculated: 180° ❌ WRONG - Should be 90°
```

### What Should Be Measured (AFTER FIX):

```
Time Window (same 2.5 seconds):

Position Array: [1, 2, 3, ... 40, 41, 42, ... 100]
                 ←Forward→  ←Peak

Peak Detection:
- Finds position 40 as furthest from start (position 1)
- IGNORES positions after the peak (41-100)
- Only measures path from 1 → 40

Arc Calculation:
- Measures path from 1 → 2 → 3 → ... → 40 (forward swing ONLY)
- Result: ROM = 90° (correct!)

Visualization:
         Peak (40)
            *
           /
          /
         /
Start  *
(1)              
        
Arc measured: ~~~~~ (only up to peak, ignores return path)
ROM calculated: 90° ✅ CORRECT
```

## The Graph Spike Pattern Explained

### Before Fix:
```
ROM Graph Over Time:
180° |     *       *       *
     |    / \     / \     / \
90°  |   /   \   /   \   /   \
     |  /     \ /     \ /     \
0°   |_/       *       *       *
     └─────────────────────────→ Time
        Rep 1   Rep 2   Rep 3

Why the spikes?
- Forward swing: ROM climbs from 0° → 90°
- Keep swinging: Arc accumulates → ROM hits 180° cap
- Rep detected: Position array resets → ROM drops to 0°
- Repeat: Creates saw-tooth pattern
```

### After Fix:
```
ROM Graph Over Time:
180° |
     |
90°  |___________________
     |~~~~~~~~~~~~~~~~~~~  ← Stable around 90°
     |
0°   |_____________________
     └─────────────────────→ Time
        Rep 1   Rep 2   Rep 3

Why it's flat now?
- Forward swing: ROM climbs to 90°
- Peak detected: Arc measured only to peak = 90°
- Swinging back: Peak stays at 90° (ignores return)
- Result: Flat line around 90° ✅
```

## Real-World Example

### Your Exercise:
- **Movement**: Arm from front → overhead → front
- **Expected ROM**: ~90° each direction
- **What you saw**: Graph spiking 0° → 90° → 180° → 0° → 90° → 180°

### Why It Was Wrong:
The code was measuring like this:
```
"How far did you travel in the last 2.5 seconds?"
Instead of:
"How far did you reach from your starting point?"
```

It's like measuring a road trip:
- **Wrong way**: Add up all miles driven (including backtracking) = 180 miles
- **Right way**: Measure furthest distance from home = 90 miles

### Fix Applied:
Now it correctly measures:
```
"What's the furthest you reached from start?"
```

This matches real-world ROM measurement:
- Physical therapist watches you swing
- They note the **peak** of your swing
- They don't care that you swung back afterward
- Result: Accurate 90° ROM measurement

## Technical Details

### The Sliding Window:
- Duration: 2.5 seconds
- Sample rate: ~60 Hz (ARKit updates)
- Positions collected: ~150 samples per window
- Window pruning: Removes old samples beyond 2.5s

### Peak Detection Algorithm:
```swift
// Find the furthest point from start
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

// Only measure up to the peak
let relevantPath = Array(projected2DPath[0...peakIndex])
```

This ensures ROM reflects the **maximum reach**, not the **total path traveled**.

## What This Means for You

✅ **Now**: Graph will show flat, stable ROM around 90° for pendulum swings
✅ **Before**: Graph was spiking wildly between 0° and 180°

The fix makes the live ROM calculation match the per-rep ROM calculation, which already had peak detection implemented correctly.

## Verification Steps

Test the fix:
1. Do pendulum swing exercise (front → overhead → front)
2. Watch the ROM display during gameplay
3. Check the analyzing screen graph
4. ROM should stay around 90° (not spike to 180°)

Expected result:
```
Graph: _________________ (flat line around 90°)
NOT:   /\/\/\/\/\/\/\  (spiky pattern)
```
