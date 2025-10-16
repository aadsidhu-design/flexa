import Foundation
import CoreMotion
import simd

/// Adaptive rep detection service for custom user-defined exercises
/// Dynamically adjusts detection logic based on AI-analyzed exercise parameters
class CustomRepDetector: ObservableObject {
    @Published private(set) var currentReps: Int = 0
    @Published private(set) var currentROM: Double = 0
    
    private var exercise: CustomExercise?
    private var isActive: Bool = false
    
    // State tracking
    private var repState: RepState = .idle
    private var lastRepTimestamp: TimeInterval = 0
    private var peakValue: Double = 0
    private var valleyValue: Double = 0
    private var lastValue: Double = 0
    
    // Circular motion tracking (for circular exercises)
    private var circularLastAngle: Double?
    private var circularAngleAccumulator: Double = 0
    private var circularDirection: Int = 0
    private var circularMaxRadius: Double = 0

    // Metrics & smoothing
    private var romPerRep: [Double] = []
    private var smoothedValue: Double = 0
    private var hasSmoothedValue: Bool = false
    
    // Velocity filtering for more accurate rep detection
    private var lastTimestamp: TimeInterval = 0
    private var velocity: Double = 0
    private var minVelocityThreshold: Double = 0.02 // m/s for handheld, degrees/s for camera
    
    enum RepState {
        case idle
        case ascending      // Moving toward peak
        case descending     // Moving toward valley
        case peakHold       // At peak, waiting for descent
    }
    
    // MARK: - Lifecycle
    
    func startSession(exercise: CustomExercise) {
        self.exercise = exercise
        self.isActive = true
        self.currentReps = 0
        self.currentROM = 0
        self.repState = .idle
        self.lastRepTimestamp = 0
        self.peakValue = 0
        self.valleyValue = 0
        self.lastValue = 0
        self.circularLastAngle = nil
        self.circularAngleAccumulator = 0
        self.circularDirection = 0
        self.circularMaxRadius = 0
        self.romPerRep.removeAll()
        self.smoothedValue = 0
        self.hasSmoothedValue = false
        self.lastTimestamp = 0
        self.velocity = 0
        self.minVelocityThreshold = exercise.trackingMode == .handheld ? 0.02 : 5.0
        
        FlexaLog.motion.info("🎯 [CustomRep] Session started for '\(exercise.name)' — \(exercise.trackingMode.rawValue) | \(exercise.repParameters.movementType.rawValue)")
    }
    
    func stopSession() {
        self.isActive = false
        self.exercise = nil
        FlexaLog.motion.info("🎯 [CustomRep] Session stopped — final reps: \(self.currentReps)")
    }
    
    func reset() {
        currentReps = 0
        currentROM = 0
        repState = .idle
        peakValue = 0
        valleyValue = 0
        lastValue = 0
        circularLastAngle = nil
        circularAngleAccumulator = 0
        circularDirection = 0
        circularMaxRadius = 0
        romPerRep.removeAll()
        smoothedValue = 0
        hasSmoothedValue = false
        lastTimestamp = 0
        velocity = 0
    }
    
    // MARK: - Rep Detection (Handheld Mode)
    
    /// Process ARKit position update for handheld exercises
    func processHandheldPosition(_ position: simd_float3, timestamp: TimeInterval) {
        guard isActive,
              let exercise = exercise,
              exercise.trackingMode == .handheld else { return }
        
        let movementType = exercise.repParameters.movementType
        
        switch movementType {
        case .pendulum:
            detectPendulumRep(position: position, timestamp: timestamp)
        case .circular:
            detectCircularRep(position: position, timestamp: timestamp)
        case .vertical:
            detectVerticalRep(position: position, timestamp: timestamp)
        case .horizontal:
            detectHorizontalRep(position: position, timestamp: timestamp)
        case .straightening, .mixed:
            // Use generic amplitude-based detection
            detectAmplitudeRep(position: position, timestamp: timestamp)
        }
    }
    
    private func detectPendulumRep(position: simd_float3, timestamp: TimeInterval) {
        guard let exercise = exercise else { return }
        
        // Pendulum is primarily Z-axis (forward/backward)
        let value = Double(position.z) * 100 // Convert to cm
        
        detectPeakValleyRep(
            value: value,
            timestamp: timestamp,
            threshold: exercise.repParameters.minimumDistanceThreshold ?? 30,
            cooldown: exercise.repParameters.repCooldown,
            directionality: exercise.repParameters.directionality
        )
    }
    
    private func detectCircularRep(position: simd_float3, timestamp: TimeInterval) {
        guard let exercise = exercise else { return }

        let x = Double(position.x)
        let z = Double(position.z)
        let radiusMeters = sqrt(x * x + z * z)

        guard radiusMeters.isFinite else { return }

        let radiusCentimeters = radiusMeters * 100
        if radiusCentimeters > currentROM {
            currentROM = radiusCentimeters
        }

        let angle = atan2(z, x)

        // Initialize baseline angle and radius
        guard let lastAngle = circularLastAngle else {
            circularLastAngle = angle
            circularMaxRadius = radiusMeters
            return
        }

    let delta = shortestAngleDifference(from: lastAngle, to: angle)
        let maxStep = Double.pi * 0.75 // Ignore erratic jumps >135° between samples
        if abs(delta) > maxStep {
            circularLastAngle = angle
            return
        }

        if abs(delta) < 0.01 { // Motion too small to accumulate
            circularLastAngle = angle
            return
        }

        let direction = delta > 0 ? 1 : -1
        if circularDirection == 0 {
            circularDirection = direction
        } else if direction != circularDirection {
            circularDirection = direction
            circularAngleAccumulator = 0
            circularMaxRadius = radiusMeters
        }

        circularAngleAccumulator += delta
        circularMaxRadius = max(circularMaxRadius, radiusMeters)

        let fullRotation = 2 * Double.pi
        if abs(circularAngleAccumulator) >= fullRotation {
            let romValue = circularMaxRadius * 100
            if attemptRep(romValue: romValue,
                          timestamp: timestamp,
                          cooldown: exercise.repParameters.repCooldown,
                          context: "Circular") {
                circularAngleAccumulator = 0
                circularMaxRadius = 0
            }
        }

        circularLastAngle = angle
    }
    
    private func detectVerticalRep(position: simd_float3, timestamp: TimeInterval) {
        guard let exercise = exercise else { return }
        
        // Vertical is Y-axis
        let value = Double(position.y) * 100 // Convert to cm
        
        detectPeakValleyRep(
            value: value,
            timestamp: timestamp,
            threshold: exercise.repParameters.minimumDistanceThreshold ?? 30,
            cooldown: exercise.repParameters.repCooldown,
            directionality: exercise.repParameters.directionality
        )
    }
    
    private func detectHorizontalRep(position: simd_float3, timestamp: TimeInterval) {
        guard let exercise = exercise else { return }
        
        // Horizontal is X-axis (side-to-side)
        let value = Double(position.x) * 100 // Convert to cm
        
        detectPeakValleyRep(
            value: value,
            timestamp: timestamp,
            threshold: exercise.repParameters.minimumDistanceThreshold ?? 30,
            cooldown: exercise.repParameters.repCooldown,
            directionality: exercise.repParameters.directionality
        )
    }
    
    private func detectAmplitudeRep(position: simd_float3, timestamp: TimeInterval) {
        guard let exercise = exercise else { return }
        
        // Use magnitude of position vector as amplitude
        let amplitude = sqrt(Double(position.x * position.x + position.y * position.y + position.z * position.z)) * 100
        
        detectPeakValleyRep(
            value: amplitude,
            timestamp: timestamp,
            threshold: exercise.repParameters.minimumDistanceThreshold ?? 30,
            cooldown: exercise.repParameters.repCooldown,
            directionality: exercise.repParameters.directionality
        )
    }
    
    // MARK: - Rep Detection (Camera Mode)
    
    /// Process camera keypoints update for camera-based exercises
    func processCameraKeypoints(_ keypoints: SimplifiedPoseKeypoints, timestamp: TimeInterval) {
        guard isActive,
              let exercise = exercise,
              exercise.trackingMode == .camera else { return }
        
        let activeSide = keypoints.phoneArm
        
        // Get ROM value based on joint being tracked
        let romValue: Double
        switch exercise.jointToTrack {
        case .armpit:
            romValue = keypoints.getArmpitROM(side: activeSide)
        case .elbow:
            // Get elbow angle based on side
            if activeSide == .left {
                romValue = keypoints.getLeftElbowAngle() ?? 0
            } else {
                romValue = keypoints.getRightElbowAngle() ?? 0
            }
        case .none:
            romValue = keypoints.getArmpitROM(side: activeSide) // Default to armpit
        }
        
        // Update current ROM
        if romValue > currentROM {
            currentROM = romValue
        }
        
        // Detect reps based on ROM threshold
        detectPeakValleyRep(
            value: romValue,
            timestamp: timestamp,
            threshold: exercise.repParameters.minimumROMThreshold,
            cooldown: exercise.repParameters.repCooldown,
            directionality: exercise.repParameters.directionality
        )
    }
    
    // MARK: - Generic Peak-Valley Detection
    
    private func detectPeakValleyRep(value: Double, timestamp: TimeInterval, threshold: Double, cooldown: Double, directionality: CustomExercise.RepParameters.Directionality) {
        // Apply exponential smoothing for noise reduction
        let smoothingFactor = 0.15 // Lower = more smoothing
        let currentSmoothedValue: Double
        if hasSmoothedValue {
            currentSmoothedValue = smoothingFactor * value + (1 - smoothingFactor) * smoothedValue
        } else {
            currentSmoothedValue = value
            hasSmoothedValue = true
        }
        smoothedValue = currentSmoothedValue
        
        let romThreshold = max(threshold, 5)
        let filtered = currentSmoothedValue
        let magnitude = abs(filtered)
        if magnitude > currentROM {
            currentROM = magnitude
        }

        // Calculate velocity for better motion detection
        let dt = timestamp - lastTimestamp
        if dt > 0 && lastTimestamp > 0 {
            velocity = abs(filtered - lastValue) / dt
        }
        lastTimestamp = timestamp

        let delta = filtered - lastValue
        let deltaThreshold = max(romThreshold * 0.08, 1.25)
        
        // Require minimum velocity to count as real movement (filters drift/noise)
        let isSignificantMovement = abs(delta) > deltaThreshold && velocity > minVelocityThreshold

        switch repState {
        case .idle:
            if isSignificantMovement {
                if delta > 0 {
                    repState = .ascending
                    valleyValue = filtered
                    peakValue = filtered
                } else {
                    repState = .descending
                    peakValue = filtered
                    valleyValue = filtered
                }
            }

        case .ascending:
            peakValue = max(peakValue, filtered)

            if isSignificantMovement && delta < 0 {
                let amplitude = peakValue - valleyValue

                if amplitude >= romThreshold {
                    if directionality == .unidirectional {
                        _ = attemptRep(romValue: peakValue,
                                        timestamp: timestamp,
                                        cooldown: cooldown,
                                        context: "Unidirectional")
                    }
                    repState = .descending
                    valleyValue = filtered
                } else {
                    repState = .idle
                }
            }

        case .descending:
            valleyValue = min(valleyValue, filtered)

            if isSignificantMovement && delta > 0 {
                let amplitude = peakValue - valleyValue

                if amplitude >= romThreshold {
                    if directionality == .bidirectional || directionality == .cyclical {
                        let label = directionality == .cyclical ? "Cycle" : "Bidirectional"
                        _ = attemptRep(romValue: amplitude,
                                        timestamp: timestamp,
                                        cooldown: cooldown,
                                        context: label)
                    }
                    repState = .ascending
                    peakValue = filtered
                } else {
                    repState = .idle
                    peakValue = filtered
                    valleyValue = filtered
                }
            }

        case .peakHold:
            repState = .idle
        }

        lastValue = filtered
    }

    private func smoothValue(_ newValue: Double) -> Double {
        let alpha = 0.25
        if !hasSmoothedValue {
            hasSmoothedValue = true
            smoothedValue = newValue
            return newValue
        }

        smoothedValue += alpha * (newValue - smoothedValue)
        return smoothedValue
    }

    @discardableResult
    private func attemptRep(romValue: Double, timestamp: TimeInterval, cooldown: Double, context: String) -> Bool {
        guard timestamp - lastRepTimestamp >= cooldown else { return false }

        let sanitizedROM = max(romValue, 0)
        guard sanitizedROM.isFinite else { return false }

        currentReps += 1
        lastRepTimestamp = timestamp

        if sanitizedROM > currentROM {
            currentROM = sanitizedROM
        }

        romPerRep.append(sanitizedROM)

        FlexaLog.motion.info("🎯 [CustomRep] \(context) rep #\(self.currentReps) — ROM=\(String(format: "%.1f", sanitizedROM))")
        return true
    }

    private func shortestAngleDifference(from: Double, to: Double) -> Double {
        var delta = to - from
        while delta > Double.pi { delta -= 2 * Double.pi }
        while delta < -Double.pi { delta += 2 * Double.pi }
        return delta
    }

    func sessionSummary() -> (reps: Int, maxROM: Double, romHistory: [Double]) {
        return (currentReps, currentROM, romPerRep)
    }
}
