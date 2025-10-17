# Smoothness Goal Circle Fix & Firebase Metrics Documentation

## Issue: Smoothness Goal Circle Not Updating

### Root Cause
The smoothness goal circle in `ActivityRingsView` displays `goalsService.todayProgress.bestSmoothness`, which is calculated in `GoalsAndStreaksService.calculateProgress()` from:

```swift
let todaySmoothnessValues = todaySessions.compactMap { $0.sparcScore > 0 ? $0.sparcScore : nil }
let todayAvgSmoothness = todaySmoothnessValues.isEmpty ? 0 : todaySmoothnessValues.reduce(0, +) / Double(todaySmoothnessValues.count)
```

This pulls from `ComprehensiveSessionData.sparcScore`, which should be populated from `ExerciseSessionData.sparcScore`.

### Verification Needed
Check if `ExerciseSessionData.sparcScore` is being populated correctly when sessions end. The value should be:
- Calculated from SPARC history
- In the range 0-100
- Stored in the session data

### Quick Fix
If `sparcScore` is 0 or not being set, the smoothness goal will show 0/target. The fix is to ensure `sparcScore` is calculated and stored when the session ends.

**Check in `SimpleMotionService.createSessionDataSnapshot()`** - this method should calculate `sparcScore` from `sparcHistory`:

```swift
let sparcScore = sparcHistory.isEmpty ? 0 : sparcHistory.allElements.reduce(0, +) / Double(sparcHistory.count)
```

---

## All Metrics Sent to Firebase/Appwrite

Based on `BackendService.saveSession()`, here's the complete list of metrics uploaded:

### Core Session Metrics
```swift
"userId": String                    // Anonymous user ID
"sessionId": String                 // Unique session identifier
"exerciseName": String              // Game/exercise type name
"score": Int                        // Game score
"reps": Int                         // Number of reps completed
"maxROM": Double                    // Maximum ROM achieved (degrees)
"averageROM": Double                // Average ROM across all reps (degrees)
"duration": TimeInterval            // Session duration (seconds)
"timestamp": Date                   // Session start time
"sessionNumber": Int                // Sequential session number
"updatedAt": Date                   // Upload timestamp
```

### Movement Quality Metrics
```swift
"sparcScore": Double                // Average SPARC smoothness (0-100)
"formScore": Double                 // Form quality score
"consistency": Double               // Movement consistency score
"peakVelocity": Double              // Peak movement velocity
"motionSmoothnessScore": Double     // Overall smoothness score
```

### Detailed Time-Series Data
```swift
"romPerRep": [Double]               // ROM value for each rep (degrees)
"sparcHistory": [Double]            // SPARC values over time (0-100)
"romData": [[String: Any]]          // Detailed ROM data with timestamps
    // Each entry: { "angle": Double, "timestamp": Date }
"sparcTimeline": [[String: Any]]    // Detailed SPARC data with timestamps
    // Each entry: { "timestamp": Date, "sparc": Double }
```

### IMU Sensor Data (Optional)
```swift
"accelAvgMagnitude": Double?        // Average accelerometer magnitude
"accelPeakMagnitude": Double?       // Peak accelerometer magnitude
"gyroAvgMagnitude": Double?         // Average gyroscope magnitude
"gyroPeakMagnitude": Double?        // Peak gyroscope magnitude
```

### AI & Survey Data (Optional)
```swift
"aiScore": Int?                     // AI-generated performance score
"aiFeedback": String?               // AI-generated feedback text
"painPre": Int?                     // Pre-exercise pain level (0-10)
"painPost": Int?                    // Post-exercise pain level (0-10)
```

### Goals & Raw Data (Optional)
```swift
"goalsAfter": [String: Any]?        // User goals after session
    // Encoded UserGoals object
"rawSessionFile": [String: Any]?    // Complete raw session data
    // SessionFile.toDictionary()
"comprehensive": [String: Any]?     // Full comprehensive session data
    // ComprehensiveSessionData.toDictionary()
```

---

## Data Flow Summary

### Session End → Firebase Upload
1. **Game ends** → `SimpleMotionService.createSessionDataSnapshot()`
2. **Session data created** with all metrics calculated
3. **Analyzing screen** → User sees session analysis
4. **Post-survey** (optional) → Pain levels collected
5. **BackendService.saveSession()** → Upload to Firebase
6. **Local cache updated** → `LocalDataManager` stores session
7. **Goals refreshed** → `GoalsAndStreaksService.calculateProgress()`
8. **UI updates** → Activity rings show new progress

### Key Calculation Points

**SPARC Score** (smoothness):
- Calculated continuously during session
- Stored in `sparcHistory` array
- Average calculated at session end
- Range: 0-100 (higher = smoother)

**ROM Values**:
- Calculated per rep
- Stored in `romPerRep` array
- Max and average calculated at session end
- Range: 0-180 degrees

**Rep Count**:
- Incremented by rep detector (handheld) or rep detection logic (camera)
- Final count stored in session data

---

## Troubleshooting Smoothness Goal

### If smoothness goal shows 0/target:

1. **Check session data**:
   ```swift
   print("SPARC Score: \(sessionData.sparcScore)")
   print("SPARC History: \(sessionData.sparcHistory)")
   ```

2. **Check comprehensive data**:
   ```swift
   let comps = LocalDataManager.shared.getCachedComprehensiveSessions()
   print("Today's SPARC scores: \(comps.map { $0.sparcScore })")
   ```

3. **Check goals service**:
   ```swift
   print("Best Smoothness: \(goalsService.todayProgress.bestSmoothness)")
   print("Target Smoothness: \(goalsService.currentGoals.targetSmoothness * 100)")
   ```

### Expected Values

- **Handheld games**: SPARC calculated from ARKit position trajectories
- **Camera games**: SPARC calculated from wrist position trajectories
- **Range**: 0-100 (typically 40-90 for real movements)
- **Update frequency**: After each session completes

---

## Summary

**Smoothness Goal Issue**: Likely caused by `sparcScore` not being calculated or being 0 in session data.

**Firebase Metrics**: 20+ metrics uploaded per session, including:
- Core metrics (ROM, reps, duration)
- Quality metrics (SPARC, form, consistency)
- Time-series data (ROM per rep, SPARC timeline)
- Optional data (IMU sensors, AI feedback, surveys)

**Fix Priority**: Verify `sparcScore` calculation in `SimpleMotionService.createSessionDataSnapshot()`.
