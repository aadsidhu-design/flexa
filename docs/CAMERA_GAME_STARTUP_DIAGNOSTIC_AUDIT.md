# Camera Games Startup Diagnostic Audit

## Date: October 2, 2025

## Problem Statement

Camera games (Arm Raises, Balloon Pop, Wall Climbers, Constellation) are **not starting** on device. The games fail silently with no visible error or loading state.

### User Report
> "camera games takes a long time to startup for some reaons. like really slowly it doesnt evne startup so investiagte this THROOUGHLY im trynn fdo arm raises."

## Investigation Findings

### Critical Discovery: Silent Failure in startGameSession
Looking at the user's console logs from an attempted Balloon Pop game launch:
```
🔍 [BalloonPop] setupGame called - starting game session
🔍 [BalloonPop] Game session started
```

**Problem**: These logs show `BalloonPopGameView.setupGame()` calling `motionService.startGameSession(.balloonPop)`, but there are **ZERO** logs from `SimpleMotionService.startGameSession()`!

### Root Cause Analysis

#### Expected Log Flow (What Should Happen)
```
1. 🎮 [SESSION-START] startGameSession called for: Balloon Pop
2. 🎮 [SESSION-START] Error handler reset complete
3. 🎮 [SESSION-START] Main queue async block executing
4. 🎮 [SESSION-START] Checking system health: healthy
5. 🎮 [SESSION-START] ✅ System health check passed
6. 🎮 [SESSION-START] startSession(gameType:) called
7. 🎮 [SESSION-START] Game type: Balloon Pop, isCameraExercise: true
8. 🎮 [SESSION-START] → Calling startCameraGameSession
9. 📹 [CAMERA-GAME] Starting camera game session for Balloon Pop
10. 📹 [CAMERA] ========== startCamera called ==========
11. 📹 [CAMERA-STARTUP] ========== performCameraStartup ENTERED ==========
12. 📹 [CAMERA-STARTUP] Phase 0: Starting camera initialization...
... [10 phases of camera startup] ...
```

#### Actual Log Flow (What's Happening)
```
🔍 [BalloonPop] setupGame called - starting game session
🔍 [BalloonPop] Game session started
[SILENCE - NO LOGS FROM SimpleMotionService AT ALL]
```

### Hypothesis: Silent Failure Points

Based on the code audit, there are **three potential failure points** where execution could silently abort:

#### 1. DispatchQueue.main.async Block Never Executes
**Location**: `SimpleMotionService.swift:962`
```swift
func startGameSession(gameType: GameType) {
    FlexaLog.motion.info("🎮 [SESSION-START] startGameSession called for: \(gameType.displayName)")
    errorHandler.resetForNewSession()
    FlexaLog.motion.info("🎮 [SESSION-START] Error handler reset complete")
    
    DispatchQueue.main.async { [weak self] in  // ← MIGHT NOT EXECUTE
        FlexaLog.motion.info("🎮 [SESSION-START] Main queue async block executing")
        // ...
    }
}
```

**Possible Cause**: Main thread blocked, app in background, or memory pressure causing immediate deallocation.

#### 2. System Health Guard Silently Fails
**Location**: `SimpleMotionService.swift:970`
```swift
guard self.errorHandler.systemHealth != .failed else {
    FlexaLog.motion.error("🎮 [SESSION-START] ❌ Cannot start session - system health failed")
    return  // ← SILENT EXIT
}
```

**Possible Cause**: `errorHandler.resetForNewSession()` may not be setting state correctly, or a race condition causes `systemHealth == .failed` despite the reset.

#### 3. Exception in do-catch Block
**Location**: `SimpleMotionService.swift:985-998`
```swift
do {
    if self.isCameraExercise {
        try self.startCameraGameSession(gameType: gameType)
    } else {
        try self.startHandheldGameSession(gameType: gameType)
    }
} catch {
    FlexaLog.motion.error("🎮 [SESSION-START] ❌ Exception caught: \(error.localizedDescription)")
    self.errorHandler.handleError(.sessionCorrupted)
    // ← EXCEPTION HANDLED BUT GAME NEVER STARTS
}
```

**Possible Cause**: `startCameraGameSession()` throws an exception that's being caught and swallowed.

---

## Diagnostic Logging Added

To diagnose this issue on device, we've added **comprehensive logging at every execution point**:

### Entry Point Logging
```swift
// Line 958
FlexaLog.motion.info("🎮 [SESSION-START] startGameSession called for: \(gameType.displayName)")
FlexaLog.motion.info("🎮 [SESSION-START] Error handler reset complete")
```

### Async Block Entry Logging
```swift
// Line 962
DispatchQueue.main.async { [weak self] in
    FlexaLog.motion.info("🎮 [SESSION-START] Main queue async block executing")
    guard let self = self else {
        FlexaLog.motion.error("🎮 [SESSION-START] ❌ self is nil, aborting")
        return
    }
    // ...
}
```

### System Health Check Logging
```swift
// Line 968
FlexaLog.motion.info("🎮 [SESSION-START] Checking system health: \(String(describing: self.errorHandler.systemHealth))")
guard self.errorHandler.systemHealth != .failed else {
    FlexaLog.motion.error("🎮 [SESSION-START] ❌ Cannot start session - system health failed")
    return
}
FlexaLog.motion.info("🎮 [SESSION-START] ✅ System health check passed")
```

### Branch Decision Logging
```swift
// Line 983
FlexaLog.motion.info("🎮 [SESSION-START] Game type: \(gameType.displayName), isCameraExercise: \(self.isCameraExercise)")

do {
    if self.isCameraExercise {
        FlexaLog.motion.info("🎮 [SESSION-START] → Calling startCameraGameSession")
        try self.startCameraGameSession(gameType: gameType)
    } else {
        FlexaLog.motion.info("🎮 [SESSION-START] → Calling startHandheldGameSession")
        try self.startHandheldGameSession(gameType: gameType)
    }
} catch {
    FlexaLog.motion.error("🎮 [SESSION-START] ❌ Exception caught: \(error.localizedDescription)")
    self.errorHandler.handleError(.sessionCorrupted)
}
```

### Camera Startup Logging
```swift
// Line 1498 - startCamera()
FlexaLog.motion.info("📹 [CAMERA] ========== startCamera called ==========")
FlexaLog.motion.info("📹 [CAMERA] Current thread: \(Thread.current.isMainThread ? "MAIN" : "BACKGROUND")")
FlexaLog.motion.info("📹 [CAMERA] Status check: isStartingCamera=\(alreadyStarting), existingSession=\(existingSession != nil ? "YES" : "NO")")

// Line 1574 - performCameraStartup()
FlexaLog.motion.info("📹 [CAMERA-STARTUP] ========== performCameraStartup ENTERED ==========")
FlexaLog.motion.info("📹 [CAMERA-STARTUP] Phase 0: Starting camera initialization at \(startupStartTime)")
```

---

## Next Steps for Device Testing

### Test Procedure
1. **Clean build and install on physical device**
   ```bash
   xcodebuild clean -project FlexaSwiftUI.xcodeproj -scheme FlexaSwiftUI
   xcodebuild -project FlexaSwiftUI.xcodeproj -scheme FlexaSwiftUI \
     -destination 'id=YOUR_DEVICE_ID' build
   ```

2. **Open Console.app on Mac**
   - Filter for process: `FlexaSwiftUI`
   - Add subsystem filter: `com.flexa.motion` (if using os_log subsystems)

3. **Launch Balloon Pop game**
   - Navigate: Home → Games → Balloon Pop → Start
   - Watch Console logs in real-time

4. **Identify failure point** by checking which log appears last:

   **If logs stop after:**
   - `[SESSION-START] startGameSession called` → Function entered but async block never ran
   - `[SESSION-START] Error handler reset complete` → Async dispatch failed
   - `[SESSION-START] Main queue async block executing` → `self` is nil or system health failed
   - `[SESSION-START] Checking system health` → Guard check failed
   - `[SESSION-START] ✅ System health check passed` → Issue in `startSession(gameType:)` call
   - `[SESSION-START] → Calling startCameraGameSession` → Exception thrown in `startCameraGameSession()`
   - `[CAMERA-GAME] Starting camera game session` → Issue in camera initialization
   - `[CAMERA] startCamera called` → Camera permission or startup failure

### Expected Diagnostic Output Patterns

#### Pattern A: System Health Failure
```
🎮 [SESSION-START] startGameSession called for: Balloon Pop
🎮 [SESSION-START] Error handler reset complete
🎮 [SESSION-START] Main queue async block executing
🎮 [SESSION-START] Checking system health: failed
🎮 [SESSION-START] ❌ Cannot start session - system health failed
```
**Solution**: Fix error handler reset logic or investigate why health is `.failed`

#### Pattern B: Exception in startCameraGameSession
```
🎮 [SESSION-START] → Calling startCameraGameSession
🎮 [SESSION-START] ❌ Exception caught: <error description>
```
**Solution**: Fix the specific error thrown by camera session setup

#### Pattern C: Camera Permission Issue
```
📹 [CAMERA] ========== startCamera called ==========
📹 [CAMERA] Current thread: MAIN
📹 [CAMERA-STARTUP] Phase 1: Checking permissions...
[App requests permission]
```
**Solution**: Ensure `NSCameraUsageDescription` in Info.plist, check Settings

#### Pattern D: Camera Startup Slowness
```
📹 [CAMERA-STARTUP] Phase 0: Starting camera initialization (0.000s)
📹 [CAMERA-STARTUP] Phase 1: Checking permissions... (0.005s)
📹 [CAMERA-STARTUP] Phase 2: Creating AVCaptureSession... (0.010s)
📹 [CAMERA-STARTUP] Phase 3: Beginning session configuration... (0.015s)
📹 [CAMERA-STARTUP] Phase 4: Session preset set to VGA 640x480 (0.020s)
[Long delay here]
📹 [CAMERA-STARTUP] Phase 7: Committing session configuration... (5.200s) ← SLOW!
```
**Solution**: Identify which phase is slow and optimize that specific step

---

## Code Files Modified

### SimpleMotionService.swift
**Lines Changed**: 
- 958-1002 (startGameSession logging)
- 1498-1540 (startCamera logging)
- 1574-1580 (performCameraStartup logging)

**Changes Made**:
1. Entry point logging with game type
2. Error handler reset confirmation
3. Async block execution confirmation
4. System health check verbose logging
5. Branch decision logging (camera vs handheld)
6. Exception handling verbose logging
7. Camera startup phase logging
8. Thread detection logging
9. Session state logging

---

## Build Status

✅ **BUILD SUCCEEDED**

All diagnostic logging compiled successfully with no errors or warnings.

---

## Known Issues & Limitations

### Issue 1: ROMErrorHandler.SystemHealth Non-Descriptive
**Problem**: `SystemHealth` enum doesn't conform to `CustomStringConvertible`
**Workaround**: Using `String(describing:)` for logging
**Fix**: Add conformance in future refactor

### Issue 2: No Loading State in Game Views
**Problem**: Games don't show loading indicator while camera initializes
**Impact**: User sees blank screen during 0.5-2s camera warmup
**Fix**: Add loading overlay that waits for camera session ready notification

### Issue 3: No Error UI for Camera Failures
**Problem**: If camera fails, game just shows blank screen
**Impact**: User has no way to know what failed or how to fix it
**Fix**: Add error overlay with troubleshooting steps

---

## Testing Checklist

### Pre-Test Verification
- [ ] Build succeeded with no errors
- [ ] Device connected and unlocked
- [ ] Console.app open and filtered for FlexaSwiftUI
- [ ] Camera permission granted in Settings → Privacy

### Camera Game Test Cases
- [ ] Balloon Pop startup (front camera)
- [ ] Wall Climbers startup (front camera)
- [ ] Arm Raises/Constellation startup (front camera)
- [ ] Permission request flow (revoke and re-grant)
- [ ] Background app → foreground camera resume
- [ ] Multiple game launches in succession

### Log Verification
- [ ] All `[SESSION-START]` logs appear
- [ ] All `[CAMERA]` logs appear
- [ ] All `[CAMERA-STARTUP]` Phase 0-10 logs appear
- [ ] Phase timing shows reasonable durations (<2s total)
- [ ] No silent failures or missing log sections

### Performance Validation
- [ ] Camera preview appears within 2 seconds
- [ ] No memory warnings in Console
- [ ] No "FigCapture" errors in system logs
- [ ] Pose detection starts immediately after preview visible

---

## Potential Root Causes (Ranked by Likelihood)

### 1. Main Thread Deadlock (HIGH PROBABILITY)
**Symptoms**: No logs appear after `startGameSession` entry
**Cause**: `DispatchQueue.main.async` never executes because main thread is blocked
**Debug**: Check if game view's `onAppear` blocks main thread

### 2. System Health Race Condition (MEDIUM PROBABILITY)
**Symptoms**: Logs stop at "Checking system health"
**Cause**: `errorHandler.resetForNewSession()` doesn't properly reset `systemHealth`
**Debug**: Add logging inside `ROMErrorHandler.resetForNewSession()`

### 3. Camera Permission Denied (LOW PROBABILITY)
**Symptoms**: Logs reach camera startup but fail at Phase 1
**Cause**: User denied camera permission or system restriction
**Debug**: Check Settings → Privacy & Security → Camera → FlexaSwiftUI

### 4. AVCaptureSession XPC Failure (LOW PROBABILITY)
**Symptoms**: FigCapture errors in system logs, camera never starts
**Cause**: iOS system service failure, rare but possible
**Debug**: Restart device, check for iOS updates

---

## Resolution Strategy

### Phase 1: Identify Failure Point (Device Testing Required)
1. Run game on physical device
2. Watch Console.app logs in real-time
3. Note which log appears last
4. Match to diagnostic output patterns above

### Phase 2: Apply Targeted Fix
Based on failure point identified:
- **Async block failure** → Ensure main thread not blocked
- **System health failure** → Fix error handler reset
- **Exception thrown** → Add specific error handling
- **Camera permission** → Add UI prompt
- **Camera startup slow** → Optimize slow phase

### Phase 3: Add User-Facing Improvements
- Loading state overlay during camera warmup
- Error overlay with troubleshooting steps
- Permission request UI with Settings deep link
- Retry button for failed camera initialization

---

## Success Criteria

✅ **Logs show complete flow from game launch to camera running**
✅ **Camera preview visible within 2 seconds**
✅ **Pose detection active (reps incrementing)**
✅ **No FigCapture errors in system logs**
✅ **Game playable with smooth performance (60fps)**

---

## Additional Notes

### ARKit vs AVFoundation Interaction
Camera games use **AVFoundation** for capture (front camera pose detection), not ARKit. However, if a previous handheld game was running, ARKit may still be active. The code correctly stops ARKit before starting camera:

```swift
// Line 1006-1010
if isARKitRunning {
    FlexaLog.motion.info("📹 [CAMERA-GAME] Stopping ARKit for camera-only mode")
    universal3DEngine.stop()
    isARKitRunning = false
}
```

### Camera Session Reuse
The code attempts to reuse existing camera sessions for faster startup:
```swift
// Line 1509-1520
if let existingSession = captureSession {
    if existingSession.isRunning {
        // Instant preview - just update UI
    } else {
        // Resume session - faster than full recreation
    }
}
```

This optimization should make subsequent launches faster, but first launch will still take 0.5-2s for full camera initialization.

### Thread Safety
Camera setup runs on background queue (`DispatchQueue.global(qos: .userInitiated)`) to avoid blocking main thread, but preview updates happen on main queue. This is correct per AVFoundation best practices.

---

## Conclusion

The camera game startup issue requires **device testing with comprehensive logging** to diagnose. We've instrumented every critical execution path with verbose logging that will pinpoint the exact failure point. Once identified, targeted fixes can be applied based on the specific failure mode.

**Next action**: Build to device, launch Balloon Pop, and capture Console logs to identify where execution stops.
