# Copilot Instructions for FlexaSwiftUI

## Project Overview
FlexaSwiftUI is an iOS physical therapy app providing gamified shoulder rehabilitation exercises using **dual motion tracking**: camera-based pose detection (Apple Vision) and IMU/ARKit sensors for handheld games. The app measures Range of Motion (ROM), provides real-time feedback, and uses SPARC analysis for movement quality assessment.

## Architecture Essentials

### Dual Tracking System (Critical to Understand)
The app uses **two completely different tracking modes** coordinated by `SimpleMotionService`:

**Camera Games** (Balloon Pop, Wall Climbers, Constellation):
- Front-facing camera + Apple Vision body pose detection
- Tracks shoulder elevation, elbow flexion, wrist position
- ROM calculated from joint angles (armpit or elbow)
- Requires `NSCameraUsageDescription` in Info.plist
- Service: `VisionPoseProvider` publishes `SimplifiedPoseKeypoints`

**Handheld Games** (Fruit Slicer, Fan the Flame, Witch Brew, Follow Circle):
- Device motion sensors (`CMMotionManager`) + ARKit world tracking
- Tracks pendulum motion, circular movements, 3D orientation
- ROM calculated from 3D spatial movements via `Universal3DROMEngine`
- Requires `NSMotionUsageDescription` in Info.plist
- Uses calibrated arm length + grip offset compensation

### Service Architecture (MVVM + ObservableObject)
**Core Services** (all SwiftUI `ObservableObject`):
- `SimpleMotionService.shared` - Singleton coordinating all motion tracking, ROM, reps
- `BackendService` - Firebase authentication, session uploads (delegates to `FirebaseService`)
- `CalibrationDataManager.shared` - Persists arm calibration via UserDefaults
- `NavigationCoordinator.shared` - Game flow: Game → Analyzing → Results → Survey → Home

**Key Pattern**: Services use `@Published` properties; views observe via `@StateObject` or `@EnvironmentObject`. App entry point (`FlexaSwiftUIApp.swift`) injects services into environment.

### Memory Management Strategy (Critical Performance Fix)
**BoundedArray Pattern**: Motion services use `BoundedArray<T>` (thread-safe circular buffer) to prevent unbounded array growth:
```swift
private var sparcHistory = BoundedArray<Double>(maxSize: 2000)
private var romPerRep = BoundedArray<Double>(maxSize: 1000)
```
**Why**: Prevents memory leaks during long gameplay sessions. See `FlexaSwiftUI/Utilities/BoundedArray.swift`.

**Timer Cleanup**: Games must invalidate timers in `onDisappear` to prevent leaks. Prefer Combine publishers over `Timer.scheduledTimer`.

### Navigation Flow (Non-Standard Pattern)
Navigation uses **hybrid approach**:
1. Main app: `NavigationStack` with `NavigationCoordinator.path` (SwiftUI navigation)
2. Game flow: Coordinator pushes views programmatically: `.showAnalyzing()` → `.showResults()` → `.showPostSurvey()`
3. Returns to home: `NavigationCoordinator.shared.clearAll()` resets stack

**DO NOT** use multiple `.sheet()` or `.fullScreenCover()` in games—use coordinator pattern to avoid navigation conflicts.

## Development Workflows

### Building & Testing
```bash
# Build for simulator (camera/ARKit have limitations)
xcodebuild -project FlexaSwiftUI.xcodeproj -scheme FlexaSwiftUI \
  -destination 'platform=iOS Simulator,name=iPhone 15' build

# Physical device testing (required for accurate motion sensors)
xcodebuild -project FlexaSwiftUI.xcodeproj -scheme FlexaSwiftUI \
  -destination 'generic/platform=iOS' build

# Clean build
xcodebuild clean -project FlexaSwiftUI.xcodeproj -scheme FlexaSwiftUI
```

**Critical**: Motion sensor accuracy requires physical devices—simulator provides synthetic data.

### Logging Pattern (Structured Logging)
Use `FlexaLog` (wrapper around `os.Logger`) for categorized logging:
```swift
FlexaLog.motion.info("ROM updated: \(currentROM)")
FlexaLog.backend.error("Upload failed: \(error)")
FlexaLog.gemini.debug("AI analysis started")
```
Categories: `.motion`, `.vision`, `.backend`, `.game`, `.lifecycle`, `.security`, `.ui`, `.notifications`

**Mask secrets**: `FlexaLog.mask(apiKey, prefix: 4, suffix: 2)` → `AIza…4A`

### Firebase Configuration (Critical Setup)
1. `GoogleService-Info.plist` must exist in project bundle
2. API keys stored in `Config/Info.plist` under `FIREBASE_PROJECT_ID` and `FIREBASE_WEB_API_KEY`
3. Anonymous auth via `BackendService.signInAnonymously()`
4. Sessions uploaded to Firestore via `FirebaseService` (offline queue supported)

### Calibration System
Users calibrate once to establish:
- Arm segment lengths (upper arm, forearm)
- Grip offset (phone-to-forearm alignment)
- Baseline ARKit transforms for 3D tracking

Calibration data persists across launches via `CalibrationDataManager.shared`. Check calibration status with `CalibrationCheckService.shared.isCalibrated`.

## Code Conventions

### Game Implementation Pattern
Games should NOT directly manipulate `SimpleMotionService` rep/ROM state. Instead:
1. Service automatically tracks ROM and reps via `UnifiedRepDetectionService`
2. Games observe `@Published` properties: `.currentROM`, `.currentReps`, `.maxROM`
3. On game end, call `motionService.endSession()` to finalize data
4. Navigate via `NavigationCoordinator.shared.showAnalyzing(sessionData:)`

**Deprecated**: `motionService.addRomPerRep(_:)` and `motionService.addSparcHistory(_:)` are no-ops—data tracked automatically.

### Permission Handling
Required permissions in `Config/Info.plist`:
- `NSCameraUsageDescription` - "Camera is used for pose tracking and ARKit..."
- `NSMotionUsageDescription` - "Motion data is used to track reps..."

Request at app launch via `FlexaSwiftUIApp.requestPermissions()`.

### Orientation Lock
App is **portrait-only** for camera games (prevents coordinate mapping issues):
- `UISupportedInterfaceOrientations` = `[UIInterfaceOrientationPortrait]`
- Camera preview locked: `connection.videoOrientation = .portrait`

### Dark Mode Preference
App enforces dark mode: `.preferredColorScheme(.dark)` in `ContentView`.

## Key File Map

**Core Services**:
- `Services/SimpleMotionService.swift` (2056 lines) - Motion coordination hub
- `Services/VisionPoseProvider.swift` - Apple Vision pose detection
- `Services/Universal3DROMEngine.swift` - ARKit 3D ROM tracking
- `Services/BackendService.swift` - Firebase facade
- `Services/SPARCCalculationService.swift` - Movement smoothness analysis

**Game Infrastructure**:
- `Games/FollowCircleGameView.swift` - Example game with cursor smoothing pattern
- `Navigation/NavigationManager.swift` - Tab navigation (legacy, prefer `NavigationCoordinator`)

**Utilities**:
- `Utilities/BoundedArray.swift` - Thread-safe circular buffer (prevents memory leaks)
- `Utilities/FlexaLog.swift` - Structured logging facade
- `Utilities/CoordinateMapper.swift` - Screen-to-world coordinate transformations

**Models**:
- `Models/ExerciseSessionData.swift` - Session data structure for Firebase upload

**Configuration**:
- `Config/Info.plist` - Firebase config, permissions, orientation
- `FlexaSwiftUIApp.swift` - App entry point, service injection

## Common Pitfalls

1. **DO NOT** create multiple `CMMotionManager` instances—use `SimpleMotionService.shared.currentDeviceMotion`
2. **DO NOT** append to unbounded arrays in motion loops—use `BoundedArray`
3. **DO NOT** forget to call `motionService.endSession()` before navigating to results
4. **DO NOT** use `.sheet()` for game navigation—use `NavigationCoordinator` pattern
5. **DO NOT** test motion accuracy on simulator—requires physical device
6. **DO NOT** commit `GoogleService-Info.plist` or API keys to git
7. **DO NOT** override `preferredCameraJoint` unless game specifically requires elbow tracking (default: armpit)

## Testing Checklist Reference
See `test_checklist.md` for validation steps covering:
- Handheld vs camera game tracking modes
- Navigation flow correctness
- Data persistence (local JSON + Firebase)
- Performance (60fps, no leaks)

## Performance Monitoring
Use Xcode Instruments for profiling:
- **Allocations**: Check for BoundedArray effectiveness, timer cleanup
- **Time Profiler**: Motion update loop should be <16ms (60fps)
- **Energy Log**: ARKit + camera can drain battery quickly

See `PERFORMANCE_OPTIMIZATION_GUIDE.md` for known issues and fix patterns.
