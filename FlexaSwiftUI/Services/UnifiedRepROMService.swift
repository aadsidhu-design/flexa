/*
 Legacy UnifiedRepROMService has been retired.
 Handheld tracking now uses InstantARKitTracker, HandheldRepDetector, and HandheldROMCalculator.

//  UnifiedRepROMService.swift
//  FlexaSwiftUI
//
//  Created by GitHub Copilot on 10/4/25.
//
//  🎯 ONE SERVICE FOR ALL REP & ROM DETECTION
//  Medical-grade accuracy, game-specific tuning, sensor fusion
//

import Foundation
import CoreMotion
import ARKit
import simd
import Combine

/// The single source of truth for rep counting and ROM measurement across ALL games.
/// Replaces FruitSlicerDetector, FanTheFlameDetector, Universal3D rep detection, and UnifiedRepDetectionService.
final class UnifiedRepROMService: ObservableObject {
    
    // MARK: - Published State (Observable by UI)
    
    @Published private(set) var currentReps: Int = 0
    @Published private(set) var currentROM: Double = 0.0
    @Published private(set) var maxROM: Double = 0.0
    @Published private(set) var romPerRep: [Double] = []
    @Published private(set) var romPerRepTimestamps: [TimeInterval] = []
    @Published private(set) var isCalibrated: Bool = false
    @Published private(set) var lastRepROM: Double = 0.0
    
    // MARK: - Private State
    
    private var currentGameType: SimpleMotionService.GameType = .fruitSlicer
    private var currentProfile: GameDetectionProfile!
    private var sessionStartTime: TimeInterval = 0
    private var lastRepTime: TimeInterval = 0
    
    // Detection state machines
    private var imuDetectionState = IMUDetectionState()
    private var arkitDetectionState = ARKitDetectionState()
    private var visionDetectionState = VisionDetectionState()
    
    // Calibration data
    private var armLength: Double {
        CalibrationDataManager.shared.currentCalibration?.armLength ?? 0.7
    }
    
    // Thread safety
    private let processingQueue = DispatchQueue(label: "com.flexa.unifiedrep", qos: .userInitiated)
    
    // MARK: - Public API
    
    /// Start tracking session for a specific game
    func startSession(gameType: SimpleMotionService.GameType) {
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.currentGameType = gameType
            self.currentProfile = GameDetectionProfile.profile(for: gameType)
            self.sessionStartTime = Date().timeIntervalSince1970
            self.lastRepTime = self.sessionStartTime
            
            // Reset all state
            self.resetState()
            
            // Check calibration requirement
            DispatchQueue.main.async {
                self.isCalibrated = !self.currentProfile.requiresCalibration ||
                                    CalibrationDataManager.shared.isCalibrated
            }
            
            FlexaLog.motion.info("🎯 [UnifiedRep] Session started: \(gameType.displayName)")
            FlexaLog.motion.info("🎯 [UnifiedRep] Profile: method=\(self.currentProfile.repDetectionMethod) ROM=\(self.currentProfile.romCalculationMethod)")
        }
    }
    
    /// Process incoming sensor data (automatic routing based on game profile)
    func processSensorData(_ data: SensorData) {
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            switch data {
            case .imu(let motion, let timestamp):
                self.processIMU(motion: motion, timestamp: timestamp)
                
            case .arkit(let position, let timestamp):
                self.processARKit(position: position, timestamp: timestamp)
                
            case .vision(let pose, let timestamp):
                self.processVision(pose: pose, timestamp: timestamp)
            }
        }
    }
    
    /// End session and return final metrics
    func endSession() -> SessionMetrics {
        let duration = Date().timeIntervalSince1970 - sessionStartTime
        let avgROM = self.romPerRep.isEmpty ? 0 : self.romPerRep.reduce(0, +) / Double(self.romPerRep.count)
        
        let quality = calculateExerciseQuality()
        
        FlexaLog.motion.info("🎯 [UnifiedRep] Session ended: reps=\(self.currentReps) avgROM=\(String(format: "%.1f", avgROM))° maxROM=\(String(format: "%.1f", self.maxROM))°")
        
        return SessionMetrics(
            totalReps: self.currentReps,
            averageROM: avgROM,
            maxROM: self.maxROM,
            romHistory: romPerRep,
            duration: duration,
            exerciseQuality: quality
        )
    }
    
    /// Reset all tracking state
    func reset() {
        processingQueue.async { [weak self] in
            self?.resetState()
        }
    }
    
    // MARK: - Private Processing
    
    private func processIMU(motion: CMDeviceMotion, timestamp: TimeInterval) {
        // Update IMU state
        imuDetectionState.addSample(motion: motion, timestamp: timestamp)
        
        // Route to appropriate detection method
        switch currentProfile.repDetectionMethod {
        case .accelerometerReversal:
            detectRepViaAccelerometer(timestamp: timestamp)
        case .gyroRotationAccumulation:
            detectRepViaGyroAccumulation(timestamp: timestamp)
        case .gyroDirectionReversal:
            detectRepViaGyroReversal(timestamp: timestamp)
        default:
            break
        }
        
        // ❌ DISABLED: Do NOT calculate live ROM from IMU
        // Live ROM is not accurate from IMU sensors
        // Per-rep ROM is calculated from ARKit positions only via Universal3DEngine.calculateROMAndReset()
        // if currentProfile.romCalculationMethod == .imuIntegratedRotation {
        //     updateROMFromIMU()
        // }
    }
    
    private func processARKit(position: SIMD3<Double>, timestamp: TimeInterval) {
        // Update ARKit state
        arkitDetectionState.addPosition(position, timestamp: timestamp, armLength: armLength)
        
        // ARKit-based rep detection (for circular motion games)
        if currentProfile.repDetectionMethod == .arkitCircleComplete {
            detectRepViaARKitCircle(timestamp: timestamp)
        }
        
        // ❌ DISABLED: Do NOT calculate live ROM here
        // Live ROM calculations are not needed and can be inaccurate
        // Per-rep ROM is calculated from ARKit positions only via Universal3DEngine.calculateROMAndReset()
        // This is called when a rep is detected and gives accurate full-arc ROM
        // if currentProfile.romCalculationMethod == .arkitSpatialAngle {
        //     updateROMFromARKit()
        // }
    }
    
    private func processVision(pose: SimplifiedPoseKeypoints, timestamp: TimeInterval) {
        // Update vision state
        visionDetectionState.addPose(pose, timestamp: timestamp)
        
        // Vision-based rep detection
        switch currentProfile.repDetectionMethod {
        case .visionAngleThreshold:
            detectRepViaVisionAngle(timestamp: timestamp)
        case .visionTargetReach:
            detectRepViaVisionTarget(timestamp: timestamp)
        default:
            break
        }
        
        // Calculate ROM if vision is ROM source
        if currentProfile.romCalculationMethod == .visionJointAngle {
            updateROMFromVision()
        }
    }
    
    // MARK: - Rep Detection Methods
    
    private func detectRepViaAccelerometer(timestamp: TimeInterval) {
        guard let result = imuDetectionState.detectAccelerometerReversal(
            threshold: currentProfile.repThreshold,
            debounce: currentProfile.debounceInterval,
            lastRepTime: lastRepTime
        ) else { return }
        
        // Calculate cumulative ROM for the entire arc from start to peak
        // This captures the WHOLE movement arc, not peak-to-peak distance
        let rom = SimpleMotionService.shared.universal3DEngine.calculateROMAndReset()
        
        // NO MINIMUM ROM THRESHOLD - accept all reps regardless of ROM size
        // Users should see their actual movement, even if small
        
        // Register the rep with the calculated ROM (full arc)
        // Each direction change = 1 rep (forward swing = 1 rep, backward swing = 1 rep)
        registerRep(rom: rom, timestamp: timestamp, method: "Accelerometer")
    }
    
    private func detectRepViaGyroAccumulation(timestamp: TimeInterval) {
        guard let result = imuDetectionState.detectGyroRotationComplete(
            targetRotation: currentProfile.repThreshold,
            debounce: currentProfile.debounceInterval,
            lastRepTime: lastRepTime
        ) else { return }
        
        // FOR HANDHELD GAMES: Calculate ROM from Universal3D position data
        // Get ROM for current rep AND reset position array for next rep
        let rom = SimpleMotionService.shared.universal3DEngine.calculateROMAndReset()
        
        registerRep(rom: rom, timestamp: timestamp, method: "Gyro-Accumulation")
    }
    
    private func detectRepViaGyroReversal(timestamp: TimeInterval) {
        guard let result = imuDetectionState.detectGyroDirectionReversal(
            threshold: currentProfile.repThreshold,
            debounce: currentProfile.debounceInterval,
            lastRepTime: lastRepTime
        ) else { return }
        
        registerRep(rom: result.rom, timestamp: timestamp, method: "Gyro-Reversal")
    }
    
    private func detectRepViaVisionAngle(timestamp: TimeInterval) {
        guard let result = visionDetectionState.detectAngleThreshold(
            threshold: currentProfile.repThreshold,
            debounce: currentProfile.debounceInterval,
            lastRepTime: lastRepTime,
            joint: currentProfile.romJoint
        ) else { return }
        
        registerRep(rom: result.rom, timestamp: timestamp, method: "Vision-Angle")
    }
    
    private func detectRepViaVisionTarget(timestamp: TimeInterval) {
        guard let result = visionDetectionState.detectTargetReach(
            debounce: currentProfile.debounceInterval,
            lastRepTime: lastRepTime
        ) else { return }
        
        registerRep(rom: result.rom, timestamp: timestamp, method: "Vision-Target")
    }
    
    private func detectRepViaARKitCircle(timestamp: TimeInterval) {
        guard let result = arkitDetectionState.detectCircleComplete(
            debounce: currentProfile.debounceInterval,
            lastRepTime: lastRepTime,
            minRadius: 0.0  // NO minimum radius - accept all circles
        ) else { return }
        
        registerRep(rom: result.rom, timestamp: timestamp, method: "ARKit-Circle")
    }
    
    // MARK: - ROM Update Methods
    
    private func updateROMFromIMU() {
        let rom = imuDetectionState.calculateCurrentROM()
        let validated = validateROM(rom)
        
        DispatchQueue.main.async {
            self.currentROM = validated.value
            if validated.value > self.maxROM {
                self.maxROM = validated.value
            }
        }
    }
    
    private func updateROMFromARKit() {
        let rom = arkitDetectionState.calculateCurrentROM(axis: currentProfile.romAxis)
        let validated = validateROM(rom)
        
        DispatchQueue.main.async {
            self.currentROM = validated.value
            if validated.value > self.maxROM {
                self.maxROM = validated.value
            }
        }
    }
    
    private func updateROMFromVision() {
        let rom = visionDetectionState.calculateCurrentROM(joint: currentProfile.romJoint)
        let validated = validateROM(rom)
        
        DispatchQueue.main.async {
            self.currentROM = validated.value
            if validated.value > self.maxROM {
                self.maxROM = validated.value
            }
        }
    }
    
    // MARK: - Rep Registration
    
    private func registerRep(rom: Double, timestamp: TimeInterval, method: String) {
        // For handheld games: ROM comes from ARKit segment analysis (full arc), not real-time calculation
        // During game: Just detect reps and collect raw positions
        // On analyzing screen: Calculate ROM from position segments
        
        let validated = validateROM(rom)
        
        // NO MINIMUM ROM THRESHOLD - accept all detected movements
        // Let users decide what's therapeutically meaningful
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentReps += 1
            self.romPerRep.append(validated.value)
            self.romPerRepTimestamps.append(timestamp)
            self.lastRepROM = validated.value
            
            if validated.value > self.maxROM {
                self.maxROM = validated.value
            }
            
            let grade = validated.isTherapeutic ? "✅" : "⚠️"
            FlexaLog.motion.info("🎯 [UnifiedRep] \(grade) Rep #\(self.currentReps) [\(method)] ROM=\(String(format: "%.1f", validated.value))°")
        }
        
        lastRepTime = timestamp
        
        // Reset detection state for next rep
        resetDetectionState()
    }
    
    // MARK: - Medical Validation
    
    private func validateROM(_ rom: Double) -> ValidatedROM {
        // NO ROM RESTRICTIONS - accept all measured values
        // Remove physiological clamping to allow full range of motion measurement
        // Users can achieve ROM greater than typical ranges with effort
        
        let range = currentProfile.romJoint.normalRange
        let isOutsideNormal = (rom < range.lowerBound || rom > range.upperBound)
        
        if isOutsideNormal {
            FlexaLog.motion.debug("🎯 [UnifiedRep] ROM outside typical range: \(String(format: "%.1f", rom))° (typical: \(range.lowerBound)-\(range.upperBound)°)")
        }
        
        // Check therapeutic threshold (for informational purposes only)
        let isTherapeutic = rom >= currentProfile.romJoint.therapeuticMinimum
        
        return ValidatedROM(
            value: rom,  // NO CLAMPING - use raw ROM value
            isTherapeutic: isTherapeutic,
            wasClamped: false  // Never clamp anymore
        )
    }
    
    private func calculateExerciseQuality() -> ExerciseQuality {
        guard !romPerRep.isEmpty else {
            return ExerciseQuality(
                consistencyScore: 0,
                completionRate: 0,
                smoothnessScore: 0,
                medicalGrade: .needsImprovement
            )
        }
        
        // Consistency: Low variance = high score
        let avgROM = romPerRep.reduce(0, +) / Double(romPerRep.count)
        let variance = romPerRep.map { pow($0 - avgROM, 2) }.reduce(0, +) / Double(romPerRep.count)
        let stdDev = sqrt(variance)
        let consistencyScore = max(0, 100 - (stdDev * 2))  // Lower stdDev = higher score
        
        // Completion: % reps meeting therapeutic minimum
        let therapeuticReps = romPerRep.filter { $0 >= currentProfile.romJoint.therapeuticMinimum }.count
        let completionRate = (Double(therapeuticReps) / Double(romPerRep.count)) * 100
        
        // Medical grade
        let medicalGrade: MedicalGrade
        if completionRate >= 90 && consistencyScore >= 80 {
            medicalGrade = .excellent
        } else if completionRate >= 75 {
            medicalGrade = .good
        } else if completionRate >= 50 {
            medicalGrade = .fair
        } else {
            medicalGrade = .needsImprovement
        }
        
        return ExerciseQuality(
            consistencyScore: consistencyScore,
            completionRate: completionRate,
            smoothnessScore: 85,  // TODO: Integrate SPARC
            medicalGrade: medicalGrade
        )
    }
    
    private func resetState() {
        DispatchQueue.main.async {
            self.currentReps = 0
            self.currentROM = 0
            self.maxROM = 0
            self.romPerRep.removeAll()
            self.romPerRepTimestamps.removeAll()
            self.lastRepROM = 0
        }
        
        resetDetectionState()
    }
    
    private func resetDetectionState() {
        imuDetectionState.reset()
        arkitDetectionState.reset()
        visionDetectionState.reset()
    }
}

// MARK: - Supporting Types

enum SensorData {
    case imu(motion: CMDeviceMotion, timestamp: TimeInterval)
    case arkit(position: SIMD3<Double>, timestamp: TimeInterval)
    case cameraPose(pose: SimplifiedPoseKeypoints, timestamp: TimeInterval)
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

enum MedicalGrade: String {
    case excellent = "Excellent"
    case good = "Good"
    case fair = "Fair"
    case needsImprovement = "Needs Improvement"
}

struct ValidatedROM {
    let value: Double
    let isTherapeutic: Bool
    let wasClamped: Bool
}

// MARK: - Anatomical ROM Ranges

enum JointROMRange {
    case shoulderFlexion
    case shoulderAbduction
    case shoulderRotation
    case elbowFlexion
    case forearmRotation
    case scapularRetraction
    
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

enum ROMAxis {
    case sagittal       // Forward/backward
    case frontal        // Side-to-side
    case transverse     // Rotation
    case multiPlane     // Combined
}

// MARK: - Detection State Machines

/// IMU (accelerometer + gyro) detection state
struct IMUDetectionState {
    private var motionSamples: [(CMDeviceMotion, TimeInterval)] = []
    private var accumulatedRotation: Double = 0
    private var lastDirection: SIMD3<Double>?
    private var peakAcceleration: Double = 0
    private var isPeakActive: Bool = false
    
    private let maxSamples = 180  // ~3 seconds at 60Hz
    
    mutating func addSample(motion: CMDeviceMotion, timestamp: TimeInterval) {
        motionSamples.append((motion, timestamp))
        if motionSamples.count > maxSamples {
            motionSamples.removeFirst()
        }
    }
    
    mutating func detectAccelerometerReversal(threshold: Double, debounce: TimeInterval, lastRepTime: TimeInterval) -> (rom: Double, direction: String)? {
        guard motionSamples.count >= 5 else { return nil }  // Minimal samples
        guard motionSamples.last!.1 - lastRepTime >= debounce else { return nil }
        
        // ULTRA SIMPLE: Direction change = rep. No thresholds!
        // Move arm up = rep, move arm down = rep
        // No matter orientation, no minimum movement
        
        let recentSamples = Array(motionSamples.suffix(5))
        let newMotion = recentSamples.last!.0
        let newAccel = SIMD3<Double>(newMotion.userAcceleration.x, newMotion.userAcceleration.y, newMotion.userAcceleration.z)
        
        // Use Z-axis (forward/backward) for pendulum motion
        let currentDirection = newAccel.z
        
        // Get sign: positive or negative
        let currentSign = currentDirection > 0 ? 1.0 : -1.0
        
        // First time - initialize direction
        if lastDirection == nil {
            lastDirection = SIMD3<Double>(0, 0, currentSign)
            return nil
        }
        
        // Check for direction change (sign flip)
        if let prevDir = lastDirection {
            let prevSign = prevDir.z > 0 ? 1.0 : -1.0
            
            // Direction changed! (+ to - or - to +)
            if prevSign != currentSign {
                // Rep detected! Update direction for next change
                lastDirection = SIMD3<Double>(0, 0, currentSign)
                
                return (rom: 0, direction: currentSign > 0 ? "→" : "←")
            }
        }
        
        return nil
    }
    
    mutating func detectGyroRotationComplete(targetRotation: Double, debounce: TimeInterval, lastRepTime: TimeInterval) -> (rom: Double, direction: String)? {
        guard motionSamples.count >= 25 else { return nil }
        guard motionSamples.last!.1 - lastRepTime >= debounce else { return nil }
        
        // Integrate yaw rotation
        for i in 1..<motionSamples.count {
            let dt = motionSamples[i].1 - motionSamples[i-1].1
            let yawRate = motionSamples[i].0.rotationRate.z
            accumulatedRotation += abs(yawRate) * dt * (180 / .pi)
        }
        
        if accumulatedRotation >= targetRotation {
            let rom = accumulatedRotation
            accumulatedRotation = 0
            return (rom: rom, direction: "🔄")
        }
        
        return nil
    }
    
    mutating func detectGyroDirectionReversal(threshold: Double, debounce: TimeInterval, lastRepTime: TimeInterval) -> (rom: Double, direction: String)? {
        guard motionSamples.count >= 10 else { return nil }
        guard motionSamples.last!.1 - lastRepTime >= debounce else { return nil }
        
        let recent = Array(motionSamples.suffix(8))
        let yawRate = recent.last!.0.rotationRate.z
        
        if !isPeakActive && abs(yawRate) >= threshold {
            isPeakActive = true
            peakAcceleration = abs(yawRate)
            lastDirection = SIMD3<Double>(0, 0, yawRate)
            return nil
        }
        
        if isPeakActive, let prevDir = lastDirection {
            let currentDir = SIMD3<Double>(0, 0, yawRate)
            let dotProduct = simd_dot(simd_normalize(currentDir), simd_normalize(prevDir))
            
            if dotProduct < -0.3 {
                let rom = peakAcceleration * 30  // Convert rad/s to degrees
                isPeakActive = false
                peakAcceleration = 0
                return (rom: rom, direction: yawRate > 0 ? "→" : "←")
            }
        }
        
        return nil
    }
    
    func calculateCurrentROM() -> Double {
        guard motionSamples.count >= 2 else { return 0 }
        // Simplified: Use peak gyro magnitude as ROM proxy
        let maxYaw = motionSamples.map { abs($0.0.rotationRate.z) }.max() ?? 0
        return maxYaw * 30
    }
    
    mutating func reset() {
        accumulatedRotation = 0
        lastDirection = nil
        peakAcceleration = 0
        isPeakActive = false
    }
}

/// ARKit spatial position detection state
struct ARKitDetectionState {
    private var positions: [SIMD3<Double>] = []
    private var timestamps: [TimeInterval] = []
    private let maxSamples = 200
    
    // Circular motion detection state
    private var circleStartAngle: Double?
    private var lastAngle: Double?
    private var accumulatedAngle: Double = 0
    private var circleCenter: SIMD3<Double>?
    private var circleStartPos: SIMD3<Double>?
    
    mutating func addPosition(_ position: SIMD3<Double>, timestamp: TimeInterval, armLength: Double) {
        positions.append(position)
        timestamps.append(timestamp)
        
        if positions.count > maxSamples {
            positions.removeFirst()
            timestamps.removeFirst()
        }
    }
    
    /// Detect complete circular motion - returns true when a full circle is completed
    mutating func detectCircleComplete(debounce: TimeInterval, lastRepTime: TimeInterval, minRadius: Double = 0.08) -> (rom: Double, direction: String)? {
        guard positions.count >= 30 else { return nil }
        guard timestamps.last! - lastRepTime >= debounce else { return nil }
        
        // Calculate center of recent positions (sliding window)
        let recentWindow = min(60, positions.count)
        let recentPositions = Array(positions.suffix(recentWindow))
        
        // Calculate center point as average of recent positions
        var centerSum = SIMD3<Double>(0, 0, 0)
        for pos in recentPositions {
            centerSum += pos
        }
        let center = centerSum / Double(recentPositions.count)
        
        // Get current position
        let currentPos = positions.last!
        
        // Calculate vector from center to current position (in XZ plane - horizontal circle)
        let toCurrentVec = SIMD2<Double>(currentPos.x - center.x, currentPos.z - center.z)
        let radius = simd_length(toCurrentVec)
        
        // NO minimum radius restriction - accept all circles
        // Only reset if we're hovering at an impossibly small radius (< 1cm)
        if minRadius > 0 && radius < minRadius {
            // Reset if we're just hovering at center
            if circleStartAngle != nil {
                circleStartAngle = nil
                lastAngle = nil
                accumulatedAngle = 0
                circleStartPos = nil
            }
            return nil
        }
        
        // Calculate angle relative to center (0 to 2π)
        let currentAngle = atan2(toCurrentVec.y, toCurrentVec.x)
        
        // Initialize tracking on first valid position
        if circleStartAngle == nil {
            circleStartAngle = currentAngle
            lastAngle = currentAngle
            circleCenter = center
            circleStartPos = currentPos
            accumulatedAngle = 0
            return nil
        }
        
        // Track angular change
        if let prevAngle = lastAngle {
            var deltaAngle = currentAngle - prevAngle
            
            // Handle wraparound at -π/π boundary
            if deltaAngle > .pi {
                deltaAngle -= 2 * .pi
            } else if deltaAngle < -.pi {
                deltaAngle += 2 * .pi
            }
            
            // Accumulate angle (tracks total rotation)
            accumulatedAngle += deltaAngle
        }
        
        lastAngle = currentAngle
        
        // Check if we've completed a full circle (360 degrees = 2π radians)
        let absAccumulated = abs(accumulatedAngle)
        if absAccumulated >= 2 * .pi * 0.85 {  // 85% of full circle to be forgiving
            // Additional validation: check if we're close to start position
            if let startPos = circleStartPos {
                let distanceToStart = simd_length(SIMD2<Double>(currentPos.x - startPos.x, currentPos.z - startPos.z))
                let circleSize = radius * 2
                
                // Must return close to start position (within 40% of circle diameter)
                if distanceToStart < circleSize * 0.4 {
                    // Circle completed!
                    let degrees = absAccumulated * (180 / .pi)
                    let direction = accumulatedAngle > 0 ? "🔄" : "🔃"
                    
                    // Reset for next circle
                    circleStartAngle = currentAngle
                    lastAngle = currentAngle
                    circleStartPos = currentPos
                    accumulatedAngle = 0
                    
                    // ROM is the diameter of the circle (spatial extent)
                    let romDegrees = radius * 100  // Scale radius to reasonable ROM range
                    return (rom: min(romDegrees, 180), direction: direction)
                }
            }
        }
        
        // Reset if accumulated angle is way too high (likely noise/drift)
        if absAccumulated > 4 * .pi {
            circleStartAngle = currentAngle
            lastAngle = currentAngle
            circleStartPos = currentPos
            accumulatedAngle = 0
        }
        
        return nil
    }
    
    func calculateCurrentROM(axis: ROMAxis) -> Double {
        guard positions.count >= 2 else { return 0 }
        
        let startPos = positions.first!
        let endPos = positions.last!
        let distance = simd_length(endPos - startPos)
        
        // Convert spatial distance to angle (simplified)
        return min(distance * 100, 180)  // Rough conversion
    }
    
    mutating func reset() {
        // Keep some history for continuity
        if positions.count > 20 {
            positions = Array(positions.suffix(10))
            timestamps = Array(timestamps.suffix(10))
        }
        
        // Reset circle tracking
        circleStartAngle = nil
        lastAngle = nil
        accumulatedAngle = 0
        circleCenter = nil
        circleStartPos = nil
    }
}

/// Vision pose detection state
struct VisionDetectionState {
    private var poses: [(SimplifiedPoseKeypoints, TimeInterval)] = []
    private var lastAngle: Double = 0
    private var peakAngle: Double = 0
    private let maxSamples = 120
    
    mutating func addPose(_ pose: SimplifiedPoseKeypoints, timestamp: TimeInterval) {
        poses.append((pose, timestamp))
        if poses.count > maxSamples {
            poses.removeFirst()
        }
    }
    
    mutating func detectAngleThreshold(threshold: Double, debounce: TimeInterval, lastRepTime: TimeInterval, joint: JointROMRange) -> (rom: Double, direction: String)? {
        guard let last = poses.last else { return nil }
        guard last.1 - lastRepTime >= debounce else { return nil }
        
        let angle = calculateJointAngle(pose: last.0, joint: joint)
        
        if angle >= threshold && lastAngle < threshold {
            let rom = angle
            lastAngle = angle
            return (rom: rom, direction: "↑")
        }
        
        lastAngle = angle
        return nil
    }
    
    mutating func detectTargetReach(debounce: TimeInterval, lastRepTime: TimeInterval) -> (rom: Double, direction: String)? {
        guard let last = poses.last else { return nil }
        guard last.1 - lastRepTime >= debounce else { return nil }
        
        // Simplified: Detect if wrist reached a target
        // TODO: Implement actual target logic
        return nil
    }
    
    func calculateCurrentROM(joint: JointROMRange) -> Double {
        guard let last = poses.last else { return 0 }
        return calculateJointAngle(pose: last.0, joint: joint)
    }
    
    private func calculateJointAngle(pose: SimplifiedPoseKeypoints, joint: JointROMRange) -> Double {
        switch joint {
        case .elbowFlexion:
            // Calculate elbow angle from shoulder-elbow-wrist
            guard let rightShoulder = pose.rightShoulder,
                  let rightElbow = pose.rightElbow,
                  let rightWrist = pose.rightWrist else { return 0 }
            
            let shoulder = SIMD2<Double>(Double(rightShoulder.x), Double(rightShoulder.y))
            let elbow = SIMD2<Double>(Double(rightElbow.x), Double(rightElbow.y))
            let wrist = SIMD2<Double>(Double(rightWrist.x), Double(rightWrist.y))
            
            let v1 = shoulder - elbow
            let v2 = wrist - elbow
            let dot = simd_dot(v1, v2)
            let mag1 = simd_length(v1)
            let mag2 = simd_length(v2)
            
            guard mag1 > 0.01, mag2 > 0.01 else { return 0 }
            
            let cosAngle = dot / (mag1 * mag2)
            let angleRad = acos(max(-1, min(1, cosAngle)))
            return angleRad * 180 / .pi
            
        case .shoulderFlexion, .shoulderAbduction:
            // Calculate shoulder elevation
            guard let rightShoulder = pose.rightShoulder,
                  let rightElbow = pose.rightElbow else { return 0 }
            
            let shoulder = SIMD2<Double>(Double(rightShoulder.x), Double(rightShoulder.y))
            let elbow = SIMD2<Double>(Double(rightElbow.x), Double(rightElbow.y))
            let vertical = SIMD2<Double>(0, 1)
            
            let armVector = elbow - shoulder
            let dot = simd_dot(armVector, vertical)
            let mag = simd_length(armVector)
            
            guard mag > 0.01 else { return 0 }
            
            let cosAngle = dot / mag
            let angleRad = acos(max(-1, min(1, cosAngle)))
            return angleRad * 180 / .pi
            
        default:
            return 0
        }
    }
    
    mutating func reset() {
        lastAngle = 0
        peakAngle = 0
    }
}

// MARK: - Game Detection Profiles

struct GameDetectionProfile {
    let repDetectionMethod: RepDetectionMethod
    let repThreshold: Double
    let debounceInterval: TimeInterval
    let minRepLength: Int
    let romCalculationMethod: ROMCalculationMethod
    let romJoint: JointROMRange
    let romAxis: ROMAxis
    let minimumROM: Double
    let maximumROM: Double
    let requiresCalibration: Bool
    
    static func profile(for gameType: SimpleMotionService.GameType) -> GameDetectionProfile {
        switch gameType {
        case .fruitSlicer:
            return GameDetectionProfile(
                repDetectionMethod: .accelerometerReversal,
                repThreshold: 0.12,  // Increased for stability (was 0.10)
                debounceInterval: 0.4,  // Longer debounce to prevent double-counting (was 0.25)
                minRepLength: 8,  // Require longer movements (was 6)
                romCalculationMethod: .arkitSpatialAngle,
                romJoint: .shoulderFlexion,
                romAxis: .sagittal,
                minimumROM: 0,
                maximumROM: 999,
                requiresCalibration: true
            )
            
        case .followCircle:
            return GameDetectionProfile(
                repDetectionMethod: .arkitCircleComplete,  // NEW: Proper circular motion detection
                repThreshold: 0,  // Not used for circle detection
                debounceInterval: 0.8,  // Prevent double-counting same circle
                minRepLength: 0,  // Not used for circle detection
                romCalculationMethod: .arkitSpatialAngle,
                romJoint: .shoulderAbduction,
                romAxis: .multiPlane,
                minimumROM: 0,  // NO MINIMUM - accept all measured ROM
                maximumROM: 999,  // NO MAXIMUM - accept all measured ROM
                requiresCalibration: true
            )
            
        case .fanOutFlame:
            return GameDetectionProfile(
                repDetectionMethod: .gyroDirectionReversal,
                repThreshold: 0.7,  // Lowered from 0.8 for better sensitivity
                debounceInterval: 0.25,  // Reduced for faster swings
                minRepLength: 12,  // Reduced to capture shorter movements
                romCalculationMethod: .arkitSpatialAngle,
                romJoint: .scapularRetraction,
                romAxis: .frontal,
                minimumROM: 0,  // NO MINIMUM - accept all measured ROM
                maximumROM: 999,  // NO MAXIMUM - accept all measured ROM
                requiresCalibration: true
            )
            
        case .balloonPop:
            return GameDetectionProfile(
                repDetectionMethod: .visionAngleThreshold,
                repThreshold: 150,
                debounceInterval: 0.5,
                minRepLength: 15,
                romCalculationMethod: .visionJointAngle,
                romJoint: .elbowFlexion,
                romAxis: .sagittal,
                minimumROM: 0,  // NO MINIMUM
                maximumROM: 999,  // NO MAXIMUM
                requiresCalibration: false
            )
            
        case .wallClimbers:
            return GameDetectionProfile(
                repDetectionMethod: .visionAngleThreshold,
                repThreshold: 140,
                debounceInterval: 0.6,
                minRepLength: 20,
                romCalculationMethod: .visionJointAngle,
                romJoint: .shoulderFlexion,
                romAxis: .sagittal,
                minimumROM: 0,  // NO MINIMUM
                maximumROM: 999,  // NO MAXIMUM
                requiresCalibration: false
            )
            
        case .constellation:
            return GameDetectionProfile(
                repDetectionMethod: .visionTargetReach,
                repThreshold: 0.1,
                debounceInterval: 0.5,
                minRepLength: 15,
                romCalculationMethod: .visionJointAngle,
                romJoint: .shoulderAbduction,
                romAxis: .multiPlane,
                minimumROM: 0,  // NO MINIMUM
                maximumROM: 999,  // NO MAXIMUM
                requiresCalibration: false
            )
            
        case .makeYourOwn:
            return GameDetectionProfile(
                repDetectionMethod: .accelerometerReversal,
                repThreshold: 0.18,
                debounceInterval: 0.4,
                minRepLength: 15,
                romCalculationMethod: .arkitSpatialAngle,
                romJoint: .shoulderFlexion,
                romAxis: .sagittal,
                minimumROM: 0,  // NO MINIMUM
                maximumROM: 999,  // NO MAXIMUM
                requiresCalibration: true
            )
        
        case .camera, .mountainClimber:
            // Use wall climbers profile for camera/mountain climber
            return GameDetectionProfile(
                repDetectionMethod: .visionAngleThreshold,
                repThreshold: 140,
                debounceInterval: 0.6,
                minRepLength: 20,
                romCalculationMethod: .visionJointAngle,
                romJoint: .shoulderFlexion,
                romAxis: .sagittal,
                minimumROM: 0,  // NO MINIMUM
                maximumROM: 999,  // NO MAXIMUM
                requiresCalibration: false
            )
        }
    }
}

enum RepDetectionMethod: CustomStringConvertible {
    case accelerometerReversal
    case gyroRotationAccumulation
    case gyroDirectionReversal
    case visionAngleThreshold
    case visionTargetReach
    case arkitCircleComplete  // New: detect complete circular motion via ARKit
    case manualTrigger
    
    var description: String {
        switch self {
        case .accelerometerReversal: return "Accel-Reversal"
        case .gyroRotationAccumulation: return "Gyro-Accumulation"
        case .gyroDirectionReversal: return "Gyro-Reversal"
        case .visionAngleThreshold: return "Vision-Angle"
        case .visionTargetReach: return "Vision-Target"
        case .arkitCircleComplete: return "ARKit-Circle"
        case .manualTrigger: return "Manual"
        }
    }
}

enum ROMCalculationMethod: CustomStringConvertible {
    case arkitSpatialAngle
    case visionJointAngle
    case imuIntegratedRotation
    case calibratedArmLength
    
    var description: String {
        switch self {
        case .arkitSpatialAngle: return "ARKit-Spatial"
        case .visionJointAngle: return "Vision-Joint"
        case .imuIntegratedRotation: return "IMU-Integrated"
        case .calibratedArmLength: return "Calibrated-Arm"
        }
    }
}

// UnifiedRepROMService has been retired.
// Handheld rep detection now flows through HandheldRepDetector and ROM is computed by HandheldROMCalculator.
*/
