# Quick Reference: Engine-Driven Rep Detection

## What Changed?

**Before:** Manual rep detection scattered across multiple game files using different methods (IMU accelerometer, ROM thresholds, angle tracking).

**After:** Unified rep detection via `Universal3DROMEngine` with live callbacks for all handheld games.

---

## How It Works

### For Handheld Games (Fan the Flame, Follow Circle, Fruit Slicer, etc.)

```
ARKit Frame Update (60fps)
    ↓
Universal3DROMEngine.session(_:didUpdate:)
    ↓
detectLiveRep(position:timestamp:) ← NEW METHOD
    ↓ (if movement exceeds threshold)
onLiveRepDetected?(repIndex, repROM) ← FIRES CALLBACK
    ↓
SimpleMotionService.onRepDetected
    ↓
Game receives updated currentReps via @Published property
```

### For Camera Games (Balloon Pop, Wall Climbers, Constellation)

**No changes** - still using manual angle-based rep detection via `VisionPoseProvider`.

---

## Key Code Snippets

### Setting Up in a Game

```swift
// Your game already has this (no changes needed):
@StateObject private var motionService = SimpleMotionService.shared

// Motion service automatically wires engine callbacks in init()
// Just observe the published property:
.onReceive(motionService.$currentReps) { newReps in
    // React to rep changes
    self.reps = newReps
}
```

### Accessing Rep Data

```swift
// Current rep count (real-time)
let reps = motionService.currentReps

// Current ROM (real-time)
let rom = motionService.currentROM

// Per-rep ROM history
let romPerRep = motionService.romPerRep.allElements

// SPARC data points (with real timestamps)
let sparcData = motionService.sparcService.getSPARCDataPoints()
```

---

## Rep Detection Thresholds

### Universal3DROMEngine Defaults
```swift
minRepLength = 15           // samples (~0.25s at 60fps)
minTimeBetweenReps = 0.35   // seconds
minDistance = max(0.12, armLength * 0.12)  // 12cm or 12% of arm
```

### Adjusting Thresholds (if needed)
Modify `detectLiveRep` method in `Universal3DROMEngine.swift` lines 295-335.

**Example: Make rep detection more sensitive**
```swift
let minRepLength = 10           // was 15
let minTimeBetweenReps = 0.25   // was 0.35
let minDistance = max(0.08, armLength * 0.10)  // was 0.12
```

---

## SPARC Timing

### X-Axis = Real Elapsed Time ✅
```swift
// SPARCDataPoint structure
struct SPARCDataPoint: Codable {
    let timestamp: Date              // ← Real date/time
    let sparcValue: Double
    let movementPhase: String
    let jointAngles: [String: Double]
}
```

### How to Graph SPARC
```swift
let sparcPoints = motionService.sparcService.getSPARCDataPoints()
let sessionStart = sparcPoints.first?.timestamp ?? Date()

for point in sparcPoints {
    let elapsed = point.timestamp.timeIntervalSince(sessionStart)
    // Plot (x: elapsed, y: point.sparcValue)
}
```

---

## Debugging Rep Detection

### Enable Universal3D Debug Logs
```swift
// In Universal3DROMEngine.swift (line 99)
var enableSegmentationDebug: Bool = true  // was false
```

**Console output:**
```
🎯 [Universal3D Live] Rep #1 detected — distance=0.245m ROM=42.3°
🎯 [Universal3D Live] Rep #2 detected — distance=0.318m ROM=58.7°
```

### Check SimpleMotionService Logs
```
🎯 [Universal3D] Rep #1 stored — ROM=42.3° SPARC=67.8
🎯 [Universal3D] Rep #2 stored — ROM=58.7° SPARC=72.1
```

---

## Common Issues & Solutions

### Issue: No reps detected
**Cause:** Movement too small or slow  
**Solution:**
1. Check calibration (Settings → Calibrate Arm)
2. Verify ARKit tracking quality (check `motionService.isARKitRunning`)
3. Ensure movement exceeds 12cm (or 12% of arm length)

### Issue: Too many reps (false positives)
**Cause:** Threshold too sensitive or jittery tracking  
**Solution:**
1. Increase `minTimeBetweenReps` from 0.35 to 0.5
2. Increase `minDistance` from 0.12 to 0.15
3. Check lighting conditions (ARKit needs good lighting)

### Issue: SPARC graph x-axis wrong
**Cause:** Using array indices instead of timestamps  
**Solution:**
```swift
// ❌ WRONG
for (index, sparc) in sparcHistory.enumerated() {
    // x = index (frame count)
}

// ✅ CORRECT
let sparcPoints = sparcService.getSPARCDataPoints()
let start = sparcPoints.first?.timestamp ?? Date()
for point in sparcPoints {
    // x = point.timestamp.timeIntervalSince(start)
}
```

---

## Performance Tips

### Memory Management ✅
- Live rep buffer automatically resets after each rep
- Sliding window prevents unbounded growth (max 60 positions)
- No memory leaks with current implementation

### Frame Rate Optimization
```swift
// ARKit already optimized for 60fps
// If experiencing frame drops:
1. Check device capabilities (ARKit requires A9+ chip)
2. Reduce other CPU-intensive operations during gameplay
3. Use Instruments Time Profiler to identify bottlenecks
```

---

## Testing Checklist

### Physical Device Required ⚠️
ARKit does not work properly on simulator. Rep detection will fail or be inaccurate.

**Minimum Requirements:**
- iOS 15.0+
- Device with A9 chip or newer (iPhone 6s and later)
- Good lighting conditions
- Calibrated arm length

### Test Procedure
1. Complete calibration flow
2. Start handheld game (Fan the Flame, Follow Circle, or Fruit Slicer)
3. Perform clear, deliberate movements
4. Verify rep count increments in real-time (< 0.5s latency)
5. Complete session and check results:
   - Rep count matches actual movements
   - ROM values reasonable (30-90° range)
   - SPARC graph x-axis shows elapsed time (0 to duration)

---

## Migration Guide (for other games)

If adding a new handheld game:

### Step 1: Start Session
```swift
motionService.startGameSession(gameType: .yourNewGame)
```

### Step 2: Observe Reps
```swift
.onReceive(motionService.$currentReps) { newReps in
    self.reps = newReps
    // Update game state based on new rep
}
```

### Step 3: End Session
```swift
motionService.stopSession()
let sessionData = motionService.getFullSessionData()
// Navigate to analyzing/results
```

### Step 4: NO MANUAL REP DETECTION NEEDED
❌ Do NOT add custom rep detection logic  
✅ Trust Universal3D engine callbacks

---

## API Reference

### Universal3DROMEngine

#### Properties
```swift
var onLiveRepDetected: ((Int, Double) -> Void)?
@Published private(set) var liveRepCount: Int
```

#### Methods
```swift
func startDataCollection(gameType: GameType)
func stop()
private func detectLiveRep(position: SIMD3<Double>, timestamp: TimeInterval)
```

### SimpleMotionService

#### Observing Reps
```swift
@Published var currentReps: Int
@Published var currentROM: Double
@Published var maxROM: Double
```

#### Session Control
```swift
func startGameSession(gameType: GameType)
func stopSession()
func getFullSessionData() -> (score: Int, reps: Int, ...)
```

---

## Support

**Issues?** Check:
1. `ENGINE_REP_DETECTION_UPGRADE.md` - Full documentation
2. `test_checklist.md` - Testing procedures
3. `.github/copilot-instructions.md` - Architecture overview
4. Console logs with FlexaLog (enable debug level)

**Still stuck?** Review recent commits:
```bash
git log --oneline -10 -- Services/Universal3DROMEngine.swift
```
