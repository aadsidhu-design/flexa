import Foundation
import CoreGraphics

/// Handles rep validation logic for camera-based games to prevent duplicate counts.
final class CameraRepDetector {
    enum Evaluation {
        case accept
        case belowThreshold
        case cooldown(elapsed: TimeInterval, required: TimeInterval)
    }
    
    // MARK: - Hysteresis-Based Peak Detection State
    private var isPeakActive: Bool = false
    private var peakAcceleration: Double = 0.0
    private var lastForwardMagnitude: Double = 0.0
    private let peakThreshold: Double = 0.18  // Minimum acceleration for peak
    private let valleyThreshold: Double = 0.3  // Relative to threshold for valley detection
    
    // MARK: - Wall Climbers State
    enum ClimbingPhase {
        case waitingToStart
        case goingUp
        case goingDown
    }
    
    private var climbingPhase: ClimbingPhase = .waitingToStart
    private var currentRepStartY: CGFloat = 0
    private var currentRepPeakY: CGFloat = 0
    private var peakROM: Double = 0
    private let minimumDistance: CGFloat = 100  // Minimum pixel distance for valid rep
    
    // MARK: - Elbow Extension State
    enum ExtensionPhase {
        case waitingToStart
        case extending
        case flexing
    }
    
    private var extensionPhase: ExtensionPhase = .waitingToStart
    private var extensionStartAngle: Double = 0
    private var peakExtensionAngle: Double = 0
    
    // MARK: - Constellation State
    enum ConstellationPattern {
        case triangle
        case rectangle
        case circle
    }
    
    // MARK: - General State
    private let minimumInterval: TimeInterval
    private var lastRepTimestamp: TimeInterval = 0

    init(minimumInterval: TimeInterval) {
        self.minimumInterval = minimumInterval
    }

    func reset() {
        lastRepTimestamp = 0
        resetWallClimbersState()
        resetElbowExtensionState()
        resetHysteresisState()
    }
    
    // MARK: - Hysteresis Peak Detection
    
    /// Reset hysteresis-based peak detection state
    private func resetHysteresisState() {
        isPeakActive = false
        peakAcceleration = 0.0
        lastForwardMagnitude = 0.0
    }
    
    /// Process movement with hysteresis-based peak detection
    /// - Parameters:
    ///   - forwardMagnitude: Current forward acceleration magnitude
    ///   - threshold: Base threshold for movement detection
    ///   - onRepDetected: Callback when valid rep is detected
    /// - Returns: True if rep was detected
    func processHysteresisPeakDetection(
        forwardMagnitude: Double,
        threshold: Double,
        onRepDetected: () -> Void
    ) -> Bool {
        // ✅ CORRECT: Hysteresis-based peak detection
        if !isPeakActive {
            // Look for significant acceleration peak
            if forwardMagnitude >= max(threshold * 1.8, peakThreshold) {
                isPeakActive = true
                peakAcceleration = forwardMagnitude
            }
        } else {
            // Update peak if we see higher acceleration
            if forwardMagnitude > peakAcceleration {
                peakAcceleration = forwardMagnitude
            }
            
            // Look for direction reversal through valley
            let directionChanged = forwardMagnitude < lastForwardMagnitude
            if directionChanged && forwardMagnitude < threshold * valleyThreshold {
                // Strict validation: peak must be significant
                if peakAcceleration >= threshold * 1.98 {
                    onRepDetected()  // ✅ Valid rep!
                    resetHysteresisState()
                    return true
                } else {
                    // Peak too small, reset and wait for next
                    resetHysteresisState()
                }
            }
        }
        
        lastForwardMagnitude = forwardMagnitude
        return false
    }
    
    // MARK: - Wall Climbers Rep Detection
    
    /// Reset Wall Climbers tracking state
    func resetWallClimbersState() {
        climbingPhase = .waitingToStart
        currentRepStartY = 0
        currentRepPeakY = 0
        peakROM = 0
    }
    
    /// Process wrist position for Wall Climbers upward motion detection
    /// - Parameters:
    ///   - wristY: Current wrist Y position in screen pixels
    ///   - rom: Current ROM angle
    ///   - threshold: Movement threshold (as fraction of screen height)
    ///   - screenHeight: Screen height in pixels
    /// - Returns: Tuple of (repDetected, distanceTraveled, peakROM)
    func processWallClimbersMotion(
        wristY: CGFloat,
        rom: Double,
        threshold: CGFloat,
        screenHeight: CGFloat
    ) -> (repDetected: Bool, distanceTraveled: CGFloat, peakROM: Double) {
        
        _ = wristY - (climbingPhase == .waitingToStart ? wristY : currentRepStartY)
        let movementThreshold = threshold * screenHeight
        
        switch climbingPhase {
        case .waitingToStart:
            // Detect upward movement (negative deltaY = moving up on screen)
            if wristY < currentRepStartY - movementThreshold || currentRepStartY == 0 {
                climbingPhase = .goingUp
                currentRepStartY = wristY
                currentRepPeakY = wristY
                peakROM = rom
            }
            return (false, 0, 0)
            
        case .goingUp:
            // Track peak Y position (lowest Y value = highest on screen)
            if wristY < currentRepPeakY {
                currentRepPeakY = wristY
                peakROM = max(peakROM, rom)
            }
            
            // Detect downward movement (positive deltaY = moving down on screen)
            if wristY > currentRepPeakY + movementThreshold {
                climbingPhase = .goingDown
                
                // Calculate distance traveled upward
                let distanceTraveled = currentRepStartY - currentRepPeakY
                
                // Check if distance meets minimum threshold
                if distanceTraveled >= minimumDistance {
                    // Valid rep detected
                    let detectedROM = peakROM
                    resetWallClimbersState()
                    return (true, distanceTraveled, detectedROM)
                } else {
                    // Distance too small, reset and wait for next attempt
                    resetWallClimbersState()
                }
            }
            return (false, 0, 0)
            
        case .goingDown:
            // Wait for arm to stabilize or start going up again
            if wristY < currentRepStartY - movementThreshold {
                // Starting new upward movement
                climbingPhase = .goingUp
                currentRepStartY = wristY
                currentRepPeakY = wristY
                peakROM = rom
            } else if abs(wristY - currentRepStartY) < movementThreshold * 0.5 {
                // Arm stabilized at rest
                climbingPhase = .waitingToStart
                currentRepStartY = wristY
            }
            return (false, 0, 0)
        }
    }
    
    // MARK: - Elbow Extension Rep Detection
    
    /// Reset elbow extension tracking state
    func resetElbowExtensionState() {
        extensionPhase = .waitingToStart
        extensionStartAngle = 0
        peakExtensionAngle = 0
    }
    
    /// Process elbow angle for extension cycle detection
    /// - Parameters:
    ///   - elbowAngle: Current elbow angle in degrees (0° = bent, 180° = extended)
    ///   - minimumROM: Minimum ROM threshold for valid rep
    /// - Returns: Tuple of (repDetected, rom)
    func processElbowExtension(
        elbowAngle: Double,
        minimumROM: Double
    ) -> (repDetected: Bool, rom: Double) {
        
        let extensionThreshold: Double = 140  // Angle above which extension starts
        let flexionThreshold: Double = 90     // Angle below which flexion is detected
        
        switch extensionPhase {
        case .waitingToStart:
            // Detect extension start (angle > 140°)
            if elbowAngle > extensionThreshold {
                extensionPhase = .extending
                extensionStartAngle = elbowAngle
                peakExtensionAngle = elbowAngle
            }
            return (false, 0)
            
        case .extending:
            // Track peak extension angle
            if elbowAngle > peakExtensionAngle {
                peakExtensionAngle = elbowAngle
            }
            
            // Detect flexion return (angle < 90°)
            if elbowAngle < flexionThreshold {
                extensionPhase = .waitingToStart
                
                // Calculate ROM (peak - start)
                let rom = peakExtensionAngle - flexionThreshold
                
                // Check if ROM meets minimum threshold
                if rom >= minimumROM {
                    // Valid rep detected
                    resetElbowExtensionState()
                    return (true, rom)
                } else {
                    // ROM too small
                    resetElbowExtensionState()
                }
            }
            return (false, 0)
            
        case .flexing:
            // This state is not used in the simplified algorithm
            // but kept for potential future enhancements
            return (false, 0)
        }
    }

    // MARK: - Constellation Dot Connection Validation
    
    /// Validate if a connection between two dots is valid for the given pattern
    /// - Parameters:
    ///   - from: Index of the starting dot
    ///   - to: Index of the target dot
    ///   - pattern: The constellation pattern type
    ///   - connectedPoints: Array of already connected point indices
    ///   - totalPoints: Total number of points in the pattern
    /// - Returns: True if the connection is valid, false otherwise
    func validateConstellationConnection(
        from: Int,
        to: Int,
        pattern: ConstellationPattern,
        connectedPoints: [Int],
        totalPoints: Int
    ) -> Bool {
        // Can't connect to the same point
        guard from != to else { return false }
        
        // Can't connect to an already connected point (except for closing triangle)
        if connectedPoints.contains(to) {
            // Special case: Triangle can close the loop by connecting back to first point
            if pattern == .triangle && to == connectedPoints.first {
                return true
            }
            return false
        }
        
        switch pattern {
        case .triangle:
            // Triangle: allow any unconnected point
            // Must close loop at end (handled above)
            return true
            
        case .rectangle:
            // Rectangle: only allow adjacent connections (no diagonals)
            let diff = abs(from - to)
            // Adjacent: diff = 1 (next point) or diff = 3 (opposite side for 4-point rectangle)
            return diff == 1 || diff == 3
            
        case .circle:
            // Circle: only allow left/right adjacent connections
            let diff = abs(from - to)
            // Adjacent: diff = 1 (next point) or diff = totalPoints - 1 (wrap around)
            return diff == 1 || diff == totalPoints - 1
        }
    }
    
    /// Check if a constellation pattern is complete
    /// - Parameters:
    ///   - pattern: The constellation pattern type
    ///   - connectedPoints: Array of connected point indices
    ///   - totalPoints: Total number of points in the pattern
    /// - Returns: True if the pattern is complete
    func isConstellationComplete(
        pattern: ConstellationPattern,
        connectedPoints: [Int],
        totalPoints: Int
    ) -> Bool {
        switch pattern {
        case .triangle:
            // Triangle is complete only when all distinct points are connected AND
            // the final connection closes the loop back to the first point.
            // This requires totalPoints distinct entries plus the closing entry equal to the first.
            guard connectedPoints.count >= totalPoints + 1 else { return false }
            return connectedPoints.first == connectedPoints.last
            
        case .rectangle, .circle:
            // Rectangle and Circle are complete when all points are connected in order
            return connectedPoints.count >= totalPoints
        }
    }

    // MARK: - Legacy Evaluation Method
    
    func evaluateRepCandidate(rom: Double, threshold: Double, timestamp: TimeInterval) -> Evaluation {
        guard rom >= threshold else { return .belowThreshold }

        if lastRepTimestamp > 0 {
            let elapsed = timestamp - lastRepTimestamp
            if elapsed < minimumInterval {
                return .cooldown(elapsed: elapsed, required: minimumInterval)
            }
        }

        lastRepTimestamp = timestamp
        return .accept
    }
}
