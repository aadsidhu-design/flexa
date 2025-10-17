import Foundation
import simd
import Combine

/// Detects repetitions for handheld games using 3D position trajectory analysis
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
    
    // MARK: - Private State
    
    private struct DetectionParameters {
        let minMovementPerSample: Float
        let cooldown: TimeInterval
        let axisSmoothing: Float
        let scalarSmoothing: Float
        let minVelocity: Float
        let circleRadiusThreshold: Float
        let circleCenterDrift: Float
        let maxAngleStep: Float
        let rotationForRep: Float

        static func defaultParameters(for gameType: HandheldRepDetector.GameType) -> DetectionParameters {
            let fullRotation: Float = 2 * .pi
            switch gameType {
            case .fruitSlicer, .makeYourOwn:
                return .init(
                    minMovementPerSample: 0.003,
                    cooldown: 0.25,
                    axisSmoothing: 0.18,
                    scalarSmoothing: 0.22,
                    minVelocity: 0.0005,
                    circleRadiusThreshold: 0.02,
                    circleCenterDrift: 0.08,
                    maxAngleStep: .pi / 2,
                    rotationForRep: fullRotation / 2
                )
            case .fanOutFlame:
                return .init(
                    minMovementPerSample: 0.0015,
                    cooldown: 0.22,
                    axisSmoothing: 0.16,
                    scalarSmoothing: 0.18,
                    minVelocity: 0.0003,
                    circleRadiusThreshold: 0.02,
                    circleCenterDrift: 0.08,
                    maxAngleStep: .pi / 2,
                    rotationForRep: fullRotation / 2
                )
            case .followCircle:
                return .init(
                    minMovementPerSample: 0.002,
                    cooldown: 0.4,
                    axisSmoothing: 0.12,
                    scalarSmoothing: 0.18,
                    minVelocity: 0.0004,
                    circleRadiusThreshold: 0.02,
                    circleCenterDrift: 0.05,
                    maxAngleStep: .pi / 3,
                    rotationForRep: fullRotation
                )
            case .witchBrew:
                return .init(
                    minMovementPerSample: 0.0025,
                    cooldown: 0.38,
                    axisSmoothing: 0.15,
                    scalarSmoothing: 0.2,
                    minVelocity: 0.0004,
                    circleRadiusThreshold: 0.025,
                    circleCenterDrift: 0.05,
                    maxAngleStep: .pi / 3,
                    rotationForRep: fullRotation
                )
            }
        }
    }
    
    private var gameType: GameType = .fruitSlicer
    private var parameters: DetectionParameters = DetectionParameters.defaultParameters(for: .fruitSlicer)
    private var lastPosition: SIMD3<Float>?
    private var internalLastRepTimestamp: TimeInterval = 0
    private var pendulumLastPosition: SIMD3<Float>?
    private var pendulumLastDirection: SIMD3<Float>?

    private enum RepState: CustomStringConvertible {
        case idle
        case building
        case returning
        
        var description: String {
            switch self {
            case .idle: return "idle"
            case .building: return "building"
            case .returning: return "returning"
            }
        }
    }
    private var repState: RepState = .idle
    private var peakROM: Double = 0.0
    private var repStartROM: Double = 0.0
    private var repStartTimestamp: TimeInterval = 0
    private let romThreshold: Double = 4.0 // Minimum ROM (degrees) to consider a rep
    private let romReturnThreshold: Double = 2.0 // ROM must fall below this to finish a rep
    private let repCooldown: TimeInterval = 0.35 // Cooldown between reps (seconds)
    private let minimumRepDuration: TimeInterval = 0.25
    private let directionChangeDotThreshold: Float = -0.2
    var romProvider: (() -> Double)?
    private var lastLoggedROM: Double = 0
    private var lastROMLogTimestamp: TimeInterval = 0
    private let romLogInterval: TimeInterval = 0.25
    
    /// Circular motion tracking (Follow Circle, Witch Brew)
    private var circleCenter: SIMD3<Float>?
    private var lastAngle: Float = 0
    private var angleAccumulator: Float = 0
    private var circleRadiusEMA: Float = 0
    private var circleAxisPrimary: SIMD3<Float>?
    private var circleAxisSecondary: SIMD3<Float>?
    private var circleNormal: SIMD3<Float>?
    
    /// Thread safety
    private let queue = DispatchQueue(label: "com.flexa.rep.detector", qos: .userInitiated)
    
    // MARK: - Callbacks
    
    var onRepDetected: ((Int, TimeInterval) -> Void)?
    
    // MARK: - Public API
    
    /// Start new detection session
    func startSession(gameType: GameType) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            self.gameType = gameType
            self.parameters = DetectionParameters.defaultParameters(for: gameType)
            self.reset()
            
            let gameTypeName: String
            switch gameType {
            case .fruitSlicer: gameTypeName = "FruitSlicer"
            case .fanOutFlame: gameTypeName = "FanOutFlame"
            case .followCircle: gameTypeName = "FollowCircle"
            case .witchBrew: gameTypeName = "WitchBrew"
            case .makeYourOwn: gameTypeName = "MakeYourOwn"
            }
            FlexaLog.motion.info("🔁 [AUDIT] RepDetector started for game: \(gameTypeName). Cooldown: \(self.parameters.cooldown)s, Min Velocity: \(self.parameters.minVelocity)")
        }
    }
    
    /// Process new position data
    func processPosition(_ position: SIMD3<Float>, timestamp: TimeInterval) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let rom = self.romProvider?() ?? 0.0
            self.logLiveROMIfNeeded(rom: rom, timestamp: timestamp)

            switch self.gameType {
            case .fruitSlicer, .fanOutFlame, .makeYourOwn:
                self.detectPendulumRep(position: position, timestamp: timestamp, rom: rom)
            case .followCircle, .witchBrew:
                self.detectCircularRep(position: position, timestamp: timestamp)
            }
        }
    }
    
    /// End session and return rep count
    func endSession() -> Int {
        return queue.sync {
            let finalReps = currentReps
            FlexaLog.motion.info("🔁 [AUDIT] RepDetector session ended. Final reps: \(finalReps)")
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
            
            self.lastPosition = nil
            self.internalLastRepTimestamp = 0
            self.pendulumLastPosition = nil
            self.pendulumLastDirection = nil

            self.circleCenter = nil
            self.lastAngle = 0
            self.angleAccumulator = 0
            self.circleRadiusEMA = 0
            self.circleAxisPrimary = nil
            self.circleAxisSecondary = nil
            self.circleNormal = nil
            
            self.resetRepState()
        }
    }
    
    // MARK: - Pendulum Rep Detection
    
    private func detectPendulumRep(position: SIMD3<Float>, timestamp: TimeInterval, rom currentROM: Double) {
        let romValue = max(0.0, currentROM)

        if let previousPosition = pendulumLastPosition {
            let displacement = position - previousPosition
            let segmentLength = simd_length(displacement)
            if segmentLength >= parameters.minMovementPerSample {
                let currentDirection = displacement / segmentLength
                if let lastDirection = pendulumLastDirection {
                    let alignment = simd_dot(currentDirection, lastDirection)
                    if alignment <= directionChangeDotThreshold {
                        if timestamp - internalLastRepTimestamp > parameters.cooldown {
                            if romValue > romThreshold {
                                FlexaLog.motion.info("🔁 [HandheldRep][Pendulum] Rep completed — ROM=\(String(format: "%.1f", romValue))°")
                                incrementRep(timestamp: timestamp)
                            }
                        }
                    }
                }
                pendulumLastDirection = currentDirection
            }
        }
        pendulumLastPosition = position
    }
    
    // MARK: - Circular Rep Detection
    
    private func detectCircularRep(position: SIMD3<Float>, timestamp: TimeInterval) {
        if circleCenter == nil { circleCenter = position; lastPosition = position; return }
        guard var center = circleCenter else { return }

        center = center * (1.0 - parameters.circleCenterDrift) + position * parameters.circleCenterDrift
        circleCenter = center

        let currentRelative = position - center
        if length(currentRelative) < parameters.circleRadiusThreshold { return }

        guard let previousPosition = lastPosition, let normalizedRelative = normalizeOrNil(currentRelative) else {
            lastPosition = position
            return
        }

        if circleAxisPrimary == nil {
            circleAxisPrimary = normalizedRelative
            let fallbackNormal = normalizeOrNil(cross(normalizedRelative, SIMD3<Float>(0, 1, 0))) ?? SIMD3<Float>(0, 1, 0)
            circleNormal = fallbackNormal
            circleAxisSecondary = normalizeOrNil(cross(fallbackNormal, normalizedRelative)) ?? SIMD3<Float>(0, 0, 1)
            lastPosition = position
            return
        }

        guard var axisPrimary = circleAxisPrimary, var axisSecondary = circleAxisSecondary else { return }

        let axisAlpha = parameters.axisSmoothing
        if let blendedPrimary = normalizeOrNil(axisPrimary * (1.0 - axisAlpha) + normalizedRelative * axisAlpha) {
            axisPrimary = blendedPrimary
        }

        let projectedSecondary = currentRelative - axisPrimary * dot(currentRelative, axisPrimary)
        if let normalizedSecondary = normalizeOrNil(projectedSecondary) {
            if let blendedSecondary = normalizeOrNil(axisSecondary * (1.0 - axisAlpha) + normalizedSecondary * axisAlpha) {
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

        let prevRelative = previousPosition - center
        let currentAngle = atan2(dot(currentRelative, axisSecondary), dot(currentRelative, axisPrimary))
        let previousAngle = atan2(dot(prevRelative, axisSecondary), dot(prevRelative, axisPrimary))
        var angleDelta = currentAngle - previousAngle

        if angleDelta > Float.pi { angleDelta -= 2 * Float.pi } 
        else if angleDelta < -Float.pi { angleDelta += 2 * Float.pi }

        if abs(angleDelta) > parameters.maxAngleStep { angleDelta = max(-parameters.maxAngleStep, min(parameters.maxAngleStep, angleDelta)) }

        angleAccumulator += angleDelta
        let cooldownMet = (timestamp - internalLastRepTimestamp) >= parameters.cooldown

        if cooldownMet && abs(angleAccumulator) >= parameters.rotationForRep {
            let rotation = angleAccumulator
            FlexaLog.motion.info("🔁 [HandheldRep][Circular] Rep completed — rotation=\(String(format: "%.2f", rotation)) rad radiusEMA=\(String(format: "%.3f", self.circleRadiusEMA)) m")
            incrementRep(timestamp: timestamp)
            angleAccumulator -= parameters.rotationForRep * (angleAccumulator >= 0 ? 1 : -1)
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
    
    private func incrementRep(timestamp: TimeInterval) {
        internalLastRepTimestamp = timestamp
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentReps += 1
            self.lastRepTimestamp = timestamp
            FlexaLog.motion.info("🔁 [HandheldRep] Rep count incremented to \(self.currentReps)")
            self.onRepDetected?(self.currentReps, timestamp)
        }
    }

    private func resetRepState() {
        repState = .idle
        peakROM = 0
        repStartROM = 0
        repStartTimestamp = 0
        pendulumLastPosition = nil
        pendulumLastDirection = nil
    }

    private func logLiveROMIfNeeded(rom: Double, timestamp: TimeInterval) {
        guard timestamp - lastROMLogTimestamp >= romLogInterval else { return }
        lastROMLogTimestamp = timestamp
        lastLoggedROM = rom
        FlexaLog.motion.debug("📐 [HandheldROM][Live] ROM=\(String(format: "%.1f", rom))° state=\(self.repState)")
    }
}
