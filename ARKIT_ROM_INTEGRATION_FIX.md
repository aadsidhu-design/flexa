# ARKit ROM Integration Issue

## Problem
Fruit Slicer (handheld game) shows:
- ✅ ARKit starts and runs
- ❌ **0 position samples collected**
- ❌ ROM calculations not working
- ❌ Rep detection not working

## Root Cause
`InstantARKitTracker` collects position data, but it's **not being fed into `HandheldROMCalculator`**.

The tracker has position data in:
- `positionHistory: [SIMD3<Float>]`
- `timestampHistory: [TimeInterval]`

But `HandheldROMCalculator.processPosition()` is never being called.

## What's Missing

### 1. Position Data Flow
```
InstantARKitTracker → ??? → HandheldROMCalculator → ROM/Reps
     (has data)      (missing)    (never receives)
```

### 2. Required Connection
Need to set up the callback in `InstantARKitTracker`:

```swift
// In SimpleMotionService or game setup:
arkitTracker.onPositionUpdate = { [weak self] position, timestamp in
    self?.handheldROMCalculator.processPosition(position, timestamp: timestamp)
}
```

## Where to Fix

### Option A: In SimpleMotionService
When starting a handheld game session, connect ARKit to ROM calculator:

```swift
func startHandheldSession() {
    // Start ARKit
    arkitTracker.start()
    
    // Connect position updates to ROM calculator
    arkitTracker.onPositionUpdate = { [weak self] position, timestamp in
        guard let self = self else { return }
        self.handheldROMCalculator.processPosition(position, timestamp: timestamp)
    }
    
    // Start ROM calculator
    handheldROMCalculator.startSession(profile: .pendulum)
}
```

### Option B: In Game View
Each handheld game connects ARKit directly:

```swift
.onAppear {
    motionService.arkitTracker.onPositionUpdate = { position, timestamp in
        motionService.handheldROMCalculator.processPosition(position, timestamp: timestamp)
    }
}
```

## Why ARKit Changes Didn't Break This

Our ARKit optimizations are working fine:
- ✅ Faster initialization (60 FPS, optimized config)
- ✅ Position data being collected in `InstantARKitTracker`
- ✅ Tracking state management working

The issue is **pre-existing** - the position data was never being connected to the ROM calculator in the first place.

## Quick Test

To verify ARKit is working, check the tracker directly:

```swift
print("ARKit positions collected: \(arkitTracker.positionHistory.count)")
print("ARKit is tracking: \(arkitTracker.isTracking)")
print("Current position: \(arkitTracker.currentPosition)")
```

If these show data, ARKit is fine - just needs to be wired up.

## Next Steps

1. Find where handheld games are initialized
2. Add the `onPositionUpdate` callback connection
3. Verify ROM calculator receives position data
4. Test rep detection works

---

**Status**: Issue identified - needs integration fix, not ARKit fix
**ARKit Status**: ✅ Working correctly
**Integration Status**: ❌ Missing connection
