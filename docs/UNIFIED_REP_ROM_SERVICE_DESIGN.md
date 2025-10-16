# Unified Rep & ROM Detection System - Architecture Design 🏗️

**Date**: October 4, 2025  
**Goal**: ONE service, medically accurate, game-tuned, SUPER SIMPLE

---

## 1. Core Principle: Medical-Grade Simplicity

### Single Source of Truth
```
┌─────────────────────────────────────────┐
│     UnifiedRepROMService (One Ring)     │
│  ┌──────────────────────────────────┐   │
│  │  Sensor Fusion Engine            │   │
│  │  • IMU (accel + gyro)           │   │
│  │  • ARKit (spatial positions)     │   │
│  │  • Vision (joint angles)         │   │
│  └──────────────────────────────────┘   │
│  ┌──────────────────────────────────┐   │
│  │  Game-Specific Profiles          │   │
│  │  • Thresholds per game           │   │
│  │  │  • Movement patterns           │   │
│  │  • ROM calculation method        │   │
│  └──────────────────────────────────┘   │
│  ┌──────────────────────────────────┐   │
│  │  Medical-Grade Validation        │   │
│  │  • Anatomical constraints        │   │
│  │  • Outlier rejection             │   │
│  │  • Calibration-aware ROM         │   │
│  └──────────────────────────────────┘   │
└─────────────────────────────────────────┘
           ↓ Single Callback
    @Published currentReps
    @Published currentROM
    @Published maxROM
```

---

## 2. Game Detection Matrix

| Game | Sensor | Detection Method | ROM Calculation | Rep Trigger |
|------|--------|------------------|-----------------|-------------|
| **Fruit Slicer** | IMU Accel | Direction reversal | ARKit spatial angle | Accel peak → opposite dir |
| **Follow Circle** | IMU Gyro | Yaw rotation accumulation | ARKit circular ROM | 350° rotation complete |
| **Fan Flame** | IMU Gyro | Yaw direction reversal | ARKit lateral ROM | Gyro peak → opposite dir |
| **Balloon Pop** | Vision | Elbow angle threshold | Joint angle (elbow) | Extension > 150° |
| **Wall Climbers** | Vision | Shoulder elevation | Joint angle (shoulder) | Elevation > 140° |
| **Constellation** | Vision | Wrist position targets | Arm raise ROM | Target reached |
| **Make Your Own** | User-selected | Configurable | Configurable | Configurable |
| **Test ROM** | ARKit | Manual capture | ARKit segment ROM | Manual stop |

---

## 3. Medical Accuracy Requirements

### Anatomical ROM Ranges (Based on AAOS Standards)

```swift
enum JointROMRange {
    case shoulderFlexion          // 0-180° (overhead reach)
    case shoulderAbduction        // 0-180° (side raise)
    case shoulderRotation         // 0-90° (internal/external)
    case elbowFlexion            // 0-150° (bicep curl)
    case forearmRotation         // 0-90° (pronation/supination)
    case scapularRetraction      // 0-45° (squeeze shoulder blades)
    
    var normalRange: ClosedRange<Double> {
        switch self {
        case .shoulderFlexion: return 0...180
        case .shoulderAbduction: return 0...180
        case .shoulderRotation: return 0...90
        case .elbowFlexion: return 0...150
        case .forearmRotation: return 0...90
        case .scapularRetraction: return 0...45
        }
    }
    
    var therapeuticMinimum: Double {
        // Minimum ROM for therapy benefit (APTA guidelines)
        switch self {
        case .shoulderFlexion: return 30
        case .shoulderAbduction: return 30
        case .shoulderRotation: return 20
        case .elbowFlexion: return 20
        case .forearmRotation: return 15
        case .scapularRetraction: return 10
        }
    }
}
```

### Game-to-Anatomy Mapping

```swift
enum GameExerciseType {
    case fruitSlicer        // Shoulder flexion/extension pendulum
    case followCircle       // Shoulder circumduction (multi-plane)
    case fanFlame          // Scapular retraction + protraction
    case balloonPop        // Elbow extension
    case wallClimbers      // Shoulder elevation + abduction
    case constellation     // Multi-directional shoulder reach
    
    var primaryJoint: JointROMRange {
        switch self {
        case .fruitSlicer: return .shoulderFlexion
        case .followCircle: return .shoulderAbduction
        case .fanFlame: return .scapularRetraction
        case .balloonPop: return .elbowFlexion
        case .wallClimbers: return .shoulderFlexion
        case .constellation: return .shoulderAbduction
        }
    }
}
```

---

## 4. Unified Service API

### Public Interface (SUPER SIMPLE)

```swift
final class UnifiedRepROMService: ObservableObject {
    // MARK: - Published State (Observable by UI)
    @Published private(set) var currentReps: Int = 0
    @Published private(set) var currentROM: Double = 0.0
    @Published private(set) var maxROM: Double = 0.0
    @Published private(set) var romPerRep: [Double] = []
    @Published private(set) var isCalibrated: Bool = false
    
    // MARK: - Simple Public API
    
    /// Start tracking for a specific game
    func startSession(gameType: GameType)
    
    /// Feed sensor data (automatic routing)
    func processSensorData(_ data: SensorData)
    
    /// Stop tracking and return final metrics
    func endSession() -> SessionMetrics
    
    /// Reset all state
    func reset()
}
```

### Internal Sensor Abstraction

```swift
enum SensorData {
    case imu(motion: CMDeviceMotion, timestamp: TimeInterval)
    case arkit(position: SIMD3<Double>, timestamp: TimeInterval)
    case vision(pose: SimplifiedPoseKeypoints, timestamp: TimeInterval)
}

struct SessionMetrics {
    let totalReps: Int
    let averageROM: Double
    let maxROM: Double
    let romHistory: [Double]
    let duration: TimeInterval
    let exerciseQuality: ExerciseQuality
}

struct ExerciseQuality {
    let consistencyScore: Double    // 0-100: ROM variance
    let completionRate: Double      // % reps meeting therapeutic minimum
    let smoothnessScore: Double     // SPARC-based
    let medicalGrade: MedicalGrade
}

enum MedicalGrade {
    case excellent      // >90% reps therapeutic, low variance
    case good          // >75% reps therapeutic
    case fair          // >50% reps therapeutic
    case needsImprovement  // <50% reps therapeutic
}
```

---

## 5. Game-Specific Detection Profiles

### Configuration per Game

```swift
struct GameDetectionProfile {
    // Rep Detection
    let repDetectionMethod: RepDetectionMethod
    let repThreshold: Double
    let debounceInterval: TimeInterval
    let minRepLength: Int  // samples
    
    // ROM Calculation
    let romCalculationMethod: ROMCalculationMethod
    let romJoint: JointROMRange
    let romAxis: ROMAxis
    
    // Quality Gates
    let minimumROM: Double  // Don't count rep if ROM < this
    let maximumROM: Double  // Clamp outliers
    let requiresCalibration: Bool
}

enum RepDetectionMethod {
    case accelerometerReversal      // Fruit Slicer
    case gyroRotationAccumulation   // Follow Circle
    case gyroDirectionReversal      // Fan Flame
    case visionAngleThreshold       // Balloon Pop, Wall Climbers
    case visionTargetReach          // Constellation
    case manualTrigger              // Test ROM
}

enum ROMCalculationMethod {
    case arkitSpatialAngle          // 3D position → 2D projection → angle
    case visionJointAngle           // Direct from pose keypoints
    case imuIntegratedRotation      // Gyro integration (drift-corrected)
    case calibratedArmLength        // Spatial distance → angle via trig
}

enum ROMAxis {
    case sagittal       // Forward/backward (Fruit Slicer)
    case frontal        // Side-to-side (Fan Flame)
    case transverse     // Rotation (Follow Circle)
    case multiPlane     // Combined (Constellation)
}
```

### Predefined Profiles

```swift
extension GameDetectionProfile {
    static let fruitSlicer = GameDetectionProfile(
        repDetectionMethod: .accelerometerReversal,
        repThreshold: 0.18,  // g-units
        debounceInterval: 0.28,
        minRepLength: 10,
        romCalculationMethod: .arkitSpatialAngle,
        romJoint: .shoulderFlexion,
        romAxis: .sagittal,
        minimumROM: 10,  // Therapeutic minimum for pendulum
        maximumROM: 180,
        requiresCalibration: true
    )
    
    static let followCircle = GameDetectionProfile(
        repDetectionMethod: .gyroRotationAccumulation,
        repThreshold: 350,  // degrees of rotation
        debounceInterval: 0.6,
        minRepLength: 25,
        romCalculationMethod: .arkitSpatialAngle,
        romJoint: .shoulderAbduction,
        romAxis: .multiPlane,
        minimumROM: 20,
        maximumROM: 180,
        requiresCalibration: true
    )
    
    static let balloonPop = GameDetectionProfile(
        repDetectionMethod: .visionAngleThreshold,
        repThreshold: 150,  // degrees elbow extension
        debounceInterval: 0.5,
        minRepLength: 15,
        romCalculationMethod: .visionJointAngle,
        romJoint: .elbowFlexion,
        romAxis: .sagittal,
        minimumROM: 20,
        maximumROM: 150,
        requiresCalibration: false
    )
    
    // ... profiles for all 8 games
}
```

---

## 6. Sensor Fusion Strategy

### Priority Hierarchy (Per Game)

```
1. Primary Sensor (for rep detection)
   ↓
2. Secondary Sensor (for ROM calculation)
   ↓
3. Validation Sensor (for outlier rejection)
```

**Example: Fruit Slicer**
```
Rep Detection: IMU Accelerometer (primary)
ROM Calculation: ARKit Spatial (secondary)
Validation: Check ROM anatomical plausibility (tertiary)
```

**Example: Balloon Pop**
```
Rep Detection: Vision Elbow Angle (primary)
ROM Calculation: Vision Elbow Angle (same as primary)
Validation: Check angle within 0-150° range (tertiary)
```

### Fallback Strategy

```swift
// If primary sensor fails:
if primarySensorTimeout || primarySensorQualityLow {
    // Attempt fallback to secondary
    if secondarySensorAvailable {
        useFallbackDetection()
    } else {
        enterDegradedMode()  // Log warning, continue with reduced accuracy
    }
}
```

---

## 7. Medical Validation Layer

### Anatomical Plausibility Checks

```swift
func validateROM(_ rom: Double, for joint: JointROMRange) -> ValidatedROM {
    let range = joint.normalRange
    
    // Outlier rejection: Physiologically impossible
    if rom < range.lowerBound {
        FlexaLog.motion.warning("ROM below anatomical min: \(rom)° < \(range.lowerBound)°")
        return .clamped(rom: range.lowerBound)
    }
    if rom > range.upperBound {
        FlexaLog.motion.warning("ROM exceeds anatomical max: \(rom)° > \(range.upperBound)°")
        return .clamped(rom: range.upperBound)
    }
    
    // Check therapeutic minimum
    if rom < joint.therapeuticMinimum {
        return .subTherapeutic(rom: rom)
    }
    
    return .valid(rom: rom)
}

enum ValidatedROM {
    case valid(rom: Double)
    case subTherapeutic(rom: Double)  // Count rep but flag quality
    case clamped(rom: Double)         // Corrected outlier
}
```

### Calibration-Aware ROM

```swift
func calculateCalibratedROM(
    spatialDistance: Double,
    armLength: Double,
    gripOffset: Double
) -> Double {
    // Convert spatial distance to angular ROM using calibrated measurements
    let effectiveArmLength = armLength - gripOffset
    let theta = asin(min(spatialDistance / effectiveArmLength, 1.0))
    let romDegrees = theta * 180 / .pi
    return romDegrees
}
```

---

## 8. Implementation Plan

### Phase 1: Core Service (4 hours)
1. Create `UnifiedRepROMService.swift`
2. Define sensor abstraction (`SensorData` enum)
3. Implement game profile system
4. Build medical validation layer

### Phase 2: Detection Engines (6 hours)
1. IMU detection engine (accelerometer + gyro)
2. ARKit ROM calculation engine
3. Vision detection engine
4. Sensor fusion coordinator

### Phase 3: Integration (4 hours)
1. Replace all callbacks in `SimpleMotionService`
2. Delete legacy detectors:
   - `FruitSlicerRepDetector.swift`
   - `FanTheFlameRepDetector.swift`
   - `UnifiedRepDetectionService.swift`
   - Universal3D rep detection code
3. Wire unified service into motion update loops

### Phase 4: Testing (2 hours)
1. Unit tests for each game profile
2. Medical validation tests
3. Device testing for accuracy

---

## 9. Migration Path

### Before (Complex)
```
SimpleMotionService
├── FruitSlicerDetector → callback
├── FanTheFlameDetector → callback
├── Universal3DEngine.onLiveRepDetected → callback
├── Vision pose updates → callback
└── Manual rep completion → currentReps++
```

### After (SUPER SIMPLE)
```
SimpleMotionService
└── UnifiedRepROMService
    └── processSensorData() → auto-updates @Published state
```

### Code Changes
```swift
// OLD (multiple systems):
fruitSlicerDetector.onRepDetected = { ... }
fanTheFlameDetector.onRepDetected = { ... }
universal3DEngine.onLiveRepDetected = { ... }

// NEW (one system):
unifiedService.startSession(gameType: .fruitSlicer)
unifiedService.processSensorData(.imu(motion, timestamp))
// That's it! Reps & ROM auto-update via @Published
```

---

## 10. Success Criteria

### Medical Accuracy
- ✅ ROM values within ±5° of manual goniometer measurements
- ✅ Therapeutic minimum thresholds enforced per APTA guidelines
- ✅ Anatomical constraints validated per AAOS standards
- ✅ Outlier rejection for physically impossible values

### Simplicity
- ✅ ONE service, ONE API, ONE callback pattern
- ✅ Games only read `@Published` properties
- ✅ Zero direct manipulation of rep/ROM state by games
- ✅ Automatic sensor routing based on game type

### Reliability
- ✅ Fallback detection if primary sensor fails
- ✅ Graceful degradation instead of crashes
- ✅ Consistent behavior across all 8 games
- ✅ No double-counting, no missed reps

---

## Next Steps

1. **Build Core Service** → `UnifiedRepROMService.swift`
2. **Implement Detection Engines** → IMU, ARKit, Vision
3. **Wire into SimpleMotionService** → Replace all callbacks
4. **Delete Legacy Code** → 4 detector files removed
5. **Test on Device** → Validate medical accuracy

**Estimated Time**: 16 hours total  
**Complexity Reduction**: 80% fewer lines of detection code  
**Accuracy Improvement**: Medical-grade validation layer

---

**Let's build this! 🚀**
