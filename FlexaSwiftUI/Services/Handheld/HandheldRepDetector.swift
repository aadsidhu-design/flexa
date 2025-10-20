import Foundation
import simd
import Combine

/// Unified direction-change rep detector for handheld games
/// - Simple sign change detection on primary axis
/// - ROM calculated AFTER rep detection using variance-based 2D plane selection
/// - No rolling buffers, no duplicate detection
final class HandheldRepDetector: ObservableObject {
    
    // MARK: - Game Type
    
    enum GameType {
        case fruitSlicer      // Forward/backward pendulum swings
        case fanOutFlame      // Side-to-side pendulum swings
        case followCircle     // Circular motion tracking
        case witchBrew        // Circular stirring motion
        case makeYourOwn      // Custom exercises
    }
    
    // MARK: - Published State
    
    @Published private(set) var currentReps: Int = 0
    @Published private(set) var lastRepTimestamp: TimeInterval = 0
    
    // MARK: - Configuration
    private let cooldownPeriod: TimeInterval = 0.3
    private let minimumDisplacement: Float = 0.05  // meters
    
    // MARK: - State
    private var gameType: GameType = .fruitSlicer
    private var internalLastRepTimestamp: TimeInterval = 0
    private var lastDirection: Int = 0  // -1, 0, or 1
    private var repStartPosition: SIMD3<Float>?
    private var repPeakPosition: SIMD3<Float>?
    private var positionHistory: [(position: SIMD3<Float>, timestamp: TimeInterval)] = []
    
    // Circular motion tracking (Follow Circle, Witch Brew)
    private var circleCenter: SIMD3<Float>?
    private var lastAngle: Float = 0
    private var angleAccumulator: Float = 0
    private var circleAxisPrimary: SIMD3<Float>?
    private var circleAxisSecondary: SIMD3<Float>?
    private var circleNormal: SIMD3<Float>?
    private var lastPosition: SIMD3<Float>?
    
    /// Thread safety
    private let queue = DispatchQueue(label: "com.flexa.rep.detector", qos: .userInitiated)
    
    // MARK: - Callbacks
    
    var onRepDetected: ((Int, TimeInterval) -> Void)?
    var romProvider: (() -> Double)?
    var romResetCallback: (() -> Void)?
    
    // MARK: - Public API
    
    /// Start new detection session
    func startSession(gameType: GameType) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            self.gameType = gameType
            self.reset()
            
            let gameTypeName: String
            switch gameType {
            case .fruitSlicer: gameTypeName = "FruitSlicer"
            case .fanOutFlame: gameTypeName = "FanOutFlame"
            case .followCircle: gameTypeName = "FollowCircle"
            case .witchBrew: gameTypeName = "WitchBrew"
            case .makeYourOwn: gameTypeName = "MakeYourOwn"
            }
            FlexaLog.motion.info("🔁 [UnifiedRep] Started for game: \(gameTypeName)")
        }
    }
    
    /// Process new position data
    func processPosition(_ position: SIMD3<Float>, timestamp: TimeInterval) {
        queue.async { [weak self] in
            guard let self = self else { return }

            switch self.gameType {
            case .fruitSlicer, .fanOutFlame:
                // REMOVE all rep detection for these games. Gyro-based logic will be used elsewhere.
                return
            case .makeYourOwn:
                self.detectDirectionChangeRep(position: position, timestamp: timestamp)
            case .followCircle, .witchBrew:
                self.detectCircularRep(position: position, timestamp: timestamp)
            }
        }
    }
    
    /// End session and return rep count
    func endSession() -> Int {
        return queue.sync {
            let finalReps = currentReps
            FlexaLog.motion.info("🔁 [UnifiedRep] Session ended. Final reps: \(finalReps)")
            return finalReps
        }
    }
    
    /// Reset all state
    func reset() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.currentReps = 0
                self.lastRepTimestamp = 0
            }
            
            self.internalLastRepTimestamp = 0
            self.lastDirection = 0
            self.repStartPosition = nil
            self.repPeakPosition = nil
            self.positionHistory.removeAll()

            self.circleCenter = nil
            self.lastAngle = 0
            self.angleAccumulator = 0
            self.circleAxisPrimary = nil
            self.circleAxisSecondary = nil
            self.circleNormal = nil
            self.lastPosition = nil
            
            FlexaLog.motion.info("🔄 [UnifiedRep] Reset complete")
        }
    }
    
    // MARK: - Direction Change Rep Detection
    
    /// Simple direction-change detection for Fruit Slicer and Fan the Flame
    /// - Detects when primary axis changes direction
    /// - Calculates ROM AFTER rep is detected using variance-based 2D plane selection
    private func detectDirectionChangeRep(position: SIMD3<Float>, timestamp: TimeInterval) {
        // Store position for ROM calculation
        positionHistory.append((position, timestamp))
        
        // Keep only last 2 seconds of data
        let cutoff = timestamp - 2.0
        positionHistory.removeAll { $0.timestamp < cutoff }
        
        // Need at least 2 positions to detect direction
        guard positionHistory.count >= 2 else { return }
        
        // Get previous position
        let prevPosition = positionHistory[positionHistory.count - 2].position
        
        // Calculate displacement vector
        let displacement = position - prevPosition
        
        // Determine primary axis (axis with most movement)
        let absX = abs(displacement.x)
        let absY = abs(displacement.y)
        let absZ = abs(displacement.z)
        
        let primaryValue: Float
        if absY >= absX && absY >= absZ {
            primaryValue = displacement.y  // Y is primary
        } else if absX >= absZ {
            primaryValue = displacement.x  // X is primary
        } else {
            primaryValue = displacement.z  // Z is primary
        }
        
        // Determine current direction
        let currentDirection = primaryValue > 0 ? 1 : (primaryValue < 0 ? -1 : 0)
        
        // Detect direction change
        if lastDirection != 0 && currentDirection != 0 && currentDirection != lastDirection {
            // Direction changed! Check if it's a valid rep
            if let startPos = repStartPosition, let peakPos = repPeakPosition {
                let totalDisplacement = distance(startPos, peakPos)
                
                // Check minimum displacement and cooldown
                if totalDisplacement >= minimumDisplacement && 
                   (timestamp - internalLastRepTimestamp) >= cooldownPeriod {
                    
                    // Valid rep detected! Calculate ROM
                    let rom = calculateROMForRep(startPos: startPos, peakPos: peakPos)
                    
                    incrementRep(timestamp: timestamp, rom: rom)
                }
            }
            
            // Start new rep cycle
            repStartPosition = position
            repPeakPosition = position
        } else {
            // Same direction, update peak if needed
            if repStartPosition == nil {
                repStartPosition = position
                repPeakPosition = position
            } else if let startPos = repStartPosition {
                let currentDist = distance(startPos, position)
                let peakDist = distance(startPos, repPeakPosition ?? startPos)
                if currentDist > peakDist {
                    repPeakPosition = position
                }
            }
        }
        
        lastDirection = currentDirection
    }
    
    // MARK: - ROM Calculation
    
    /// Calculate ROM using variance-based 2D plane selection
    /// This is called AFTER a rep is detected, using the rep's position data
    private func calculateROMForRep(startPos: SIMD3<Float>, peakPos: SIMD3<Float>) -> Double {
        // Calculate displacement vector
        let displacement = peakPos - startPos
        
        // Calculate variance on each axis to determine best 2D plane
        let varX = displacement.x * displacement.x
        let varY = displacement.y * displacement.y
        let varZ = displacement.z * displacement.z
        
        // Select the 2 axes with highest variance
        let axes = [
            (axis: "X", variance: varX, value: displacement.x),
            (axis: "Y", variance: varY, value: displacement.y),
            (axis: "Z", variance: varZ, value: displacement.z)
        ].sorted { $0.variance > $1.variance }
        
        // Use top 2 axes for 2D plane
        let axis1 = axes[0]
        let axis2 = axes[1]
        
        // Calculate angle in 2D plane
        let magnitude = sqrt(axis1.value * axis1.value + axis2.value * axis2.value)
        
        // Convert to degrees (assuming 1 meter = ~90 degrees of shoulder ROM)
        // This is a rough approximation - can be calibrated per user
        let romDegrees = Double(magnitude) * 90.0
        
        FlexaLog.motion.debug("📐 [UnifiedRep] ROM calc - Primary axes: \(axis1.axis)(\(String(format: "%.3f", axis1.value))), \(axis2.axis)(\(String(format: "%.3f", axis2.value))) → \(String(format: "%.1f", romDegrees))°")
        
        return min(180.0, max(0.0, romDegrees))
    }

    // MARK: - Circular Rep Detection
    
    /// Detects circle completion for Follow Circle and Witch Brew games
    private func detectCircularRep(position: SIMD3<Float>, timestamp: TimeInterval) {
        let circleCenterDrift: Float = 0.08
        let circleRadiusThreshold: Float = 0.02
        let axisSmoothing: Float = 0.15
        let maxAngleStep: Float = .pi / 3
        
        // Step 1: Establish circle center using moving average
        if circleCenter == nil {
            circleCenter = position
            lastPosition = position
            FlexaLog.motion.debug("🔁 [UnifiedRep][Circular] Circle center initialized")
            return
        }

        guard var center = circleCenter else { return }

        // Update center using exponential moving average
        center = center * (1.0 - circleCenterDrift) + position * circleCenterDrift
        circleCenter = center

        // Calculate position relative to center
        let currentRelative = position - center
        let radius = length(currentRelative)

        // Require minimum radius to avoid noise at center
        guard radius >= circleRadiusThreshold else { return }

        guard let previousPosition = lastPosition else {
            lastPosition = position
            return
        }

        // Normalize current relative position
        guard let normalizedRelative = normalizeOrNil(currentRelative) else {
            lastPosition = position
            return
        }

        // Initialize coordinate system on first valid sample
        if circleAxisPrimary == nil {
            circleAxisPrimary = normalizedRelative
            let fallbackNormal = normalizeOrNil(cross(normalizedRelative, SIMD3<Float>(0, 1, 0))) ?? SIMD3<Float>(0, 1, 0)
            circleNormal = fallbackNormal
            circleAxisSecondary = normalizeOrNil(cross(fallbackNormal, normalizedRelative)) ?? SIMD3<Float>(0, 0, 1)
            lastPosition = position
            FlexaLog.motion.debug("🔁 [UnifiedRep][Circular] Coordinate system initialized")
            return
        }

        guard var axisPrimary = circleAxisPrimary, var axisSecondary = circleAxisSecondary else { return }

        // Smooth coordinate system to handle 3D motion
        if let blendedPrimary = normalizeOrNil(axisPrimary * (1.0 - axisSmoothing) + normalizedRelative * axisSmoothing) {
            axisPrimary = blendedPrimary
        }

        let projectedSecondary = currentRelative - axisPrimary * dot(currentRelative, axisPrimary)
        if let normalizedSecondary = normalizeOrNil(projectedSecondary) {
            if let blendedSecondary = normalizeOrNil(axisSecondary * (1.0 - axisSmoothing) + normalizedSecondary * axisSmoothing) {
                axisSecondary = blendedSecondary
            }
        }

        if let normal = normalizeOrNil(cross(axisPrimary, axisSecondary)) {
            circleNormal = normal
            if let correctedSecondary = normalizeOrNil(cross(normal, axisPrimary)) {
                axisSecondary = correctedSecondary
            }
        }

        circleAxisPrimary = axisPrimary
        circleAxisSecondary = axisSecondary

        // Calculate angle from center for each position
        let prevRelative = previousPosition - center
        let currentAngle = atan2(dot(currentRelative, axisSecondary), dot(currentRelative, axisPrimary))
        let previousAngle = atan2(dot(prevRelative, axisSecondary), dot(prevRelative, axisPrimary))

        // Calculate angle change, handling wraparound
        var angleDelta = currentAngle - previousAngle
        if angleDelta > Float.pi {
            angleDelta -= 2 * Float.pi
        } else if angleDelta < -Float.pi {
            angleDelta += 2 * Float.pi
        }

        // Clamp large angle steps to avoid noise
        if abs(angleDelta) > maxAngleStep {
            angleDelta = max(-maxAngleStep, min(maxAngleStep, angleDelta))
        }

        // Accumulate angle changes
        angleAccumulator += angleDelta

        // Detect completion when accumulated angle >= 2π
        let fullCircle: Float = 2 * .pi
        if (timestamp - internalLastRepTimestamp) >= cooldownPeriod && abs(angleAccumulator) >= fullCircle {
            let rom = self.romProvider?() ?? 0.0
            incrementRep(timestamp: timestamp, rom: rom)

            // Reset accumulator, keeping any excess rotation
            angleAccumulator -= fullCircle * (angleAccumulator >= 0 ? 1 : -1)
        }

        lastAngle = currentAngle
        lastPosition = position
    }
    
    // MARK: - Helper Methods
    
    private func normalizeOrNil(_ vector: SIMD3<Float>) -> SIMD3<Float>? {
        let magnitude = length(vector)
        guard magnitude > 1e-4 else { return nil }
        return vector / magnitude
    }
    
    private func incrementRep(timestamp: TimeInterval, rom: Double) {
        internalLastRepTimestamp = timestamp

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentReps += 1
            self.lastRepTimestamp = timestamp
            FlexaLog.motion.info("✅ [UnifiedRep] Rep #\(self.currentReps) detected - ROM: \(String(format: "%.1f", rom))°")
            self.onRepDetected?(self.currentReps, timestamp)
        }
    }
}
