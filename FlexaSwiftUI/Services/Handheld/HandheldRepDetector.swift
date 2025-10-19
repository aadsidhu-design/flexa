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
                    minMovementPerSample: 0.004,  // Increased to avoid noise for slow movements
                    // Raise cooldown slightly to avoid double-counting on slow/soft swings
                    cooldown: 0.65,
                    axisSmoothing: 0.18,
                    scalarSmoothing: 0.22,
                    minVelocity: 0.0010,
                    circleRadiusThreshold: 0.02,
                    circleCenterDrift: 0.08,
                    maxAngleStep: .pi / 2,
                    rotationForRep: fullRotation / 2
                )
            case .fanOutFlame:
                return .init(
                    minMovementPerSample: 0.004,
                    // Slightly longer cooldown to reduce chatter on slow side-to-side fans
                    cooldown: 0.65,
                    axisSmoothing: 0.16,
                    scalarSmoothing: 0.18,
                    minVelocity: 0.001,
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
    // Extra safety: absolute minimum interval between reported reps regardless of detector
    private let minimumInterRepInterval: TimeInterval = 0.28
    private var pendulumLastPosition: SIMD3<Float>?
    private var pendulumLastDirection: SIMD3<Float>?

    // MARK: - Hysteresis-Based Peak Detection
    private var isPeakActive: Bool = false
    private var peakMagnitude: Float = 0.0
    private var lastMovementMagnitude: Float = 0.0
    private let peakActivationMultiplier: Float = 2.2  // Peak must be 2.2x threshold
    private let valleyThresholdMultiplier: Float = 0.28  // Valley is 0.28x threshold (tighter)
    private let strictPeakValidation: Float = 2.5  // Peak must be 2.5x threshold to count

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
    private let directionChangeDotThreshold: Float = -0.2
    // Persistent ROM baseline position
    private var romBaselinePosition: SIMD3<Float>?
    // Compatibility: external ROM provider (from HandheldROMCalculator) and reset callback
    var romProvider: (() -> Double)?
    var romResetCallback: (() -> Void)?
    
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
            
            // Use persistent baseline for ROM calculation
            if romBaselinePosition == nil {
                romBaselinePosition = position
            }
            // Prefer external ROM provider if available (higher fidelity)
            let rom: Double
            if let provider = self.romProvider {
                rom = provider()
            } else {
                // fallback: simple angular estimate using baseline and current pos
                rom = Self.simpleROMEstimate(from: romBaselinePosition!, to: position)
            }

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
    
    /// Detects direction changes for Fruit Slicer and Fan the Flame games using hysteresis-based peak detection
    /// Requirements: 1.1, 1.2, 3.1, 3.2
    /// Algorithm:
    /// 1. Calculate movement magnitude between positions
    /// 2. Detect significant acceleration peak (1.8x threshold)
    /// 3. Track peak magnitude during movement
    /// 4. Detect direction reversal through valley (0.3x threshold)
    /// 5. Validate peak was significant (1.98x threshold) before counting rep
    /// 6. Enforce 0.25s cooldown between reps
    private var lastProjectedValue: Float? = nil
    private var lastDirectionSign: Int = 0

    private func detectPendulumRep(position: SIMD3<Float>, timestamp: TimeInterval, rom currentROM: Double) {
            // ARKit-driven direction-change detection is implemented as a separate class-level method below.
        }

        /// Returns the principal axis of movement from a set of displacement vectors
        private func principalAxis(from diffs: [SIMD3<Float>]) -> SIMD3<Float> {
            // Simple PCA: take the direction with largest variance
            let xs = diffs.map { $0.x }
            let ys = diffs.map { $0.y }
            let zs = diffs.map { $0.z }
            let vx = variance(xs)
            let vy = variance(ys)
            let vz = variance(zs)
            let maxV = max(vx, vy, vz)
            if maxV == vx { return SIMD3<Float>(1,0,0) }
            if maxV == vy { return SIMD3<Float>(0,1,0) }
            return SIMD3<Float>(0,0,1)
        }

        private func variance(_ arr: [Float]) -> Float {
            let mean = arr.reduce(0, +) / Float(arr.count)
            return arr.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(arr.count)
        }

        /// Autocorrelation of a signal
        private func autocorrelation(_ arr: [Float]) -> [Float] {
            let n = arr.count
            var result = [Float](repeating: 0, count: n)
            for lag in 0..<n {
                var sum: Float = 0
                for i in 0..<(n-lag) {
                    sum += arr[i] * arr[i+lag]
                }
                result[lag] = sum / Float(n-lag)
            }
            return result
        }

        // MARK: - ARKit Direction Change Detection (Class-level)

        /// Try simpler ARKit-driven direction-change detection.
        /// Returns true when a rep was detected and handled.
        private func tryARKitDirectionChangeDetection(position: SIMD3<Float>, timestamp: TimeInterval, rom: Double) -> Bool {
            // Need at least last position
            guard let lastPos = pendulumLastPosition else { return false }

            // Compute displacement and find dominant axis from small history if available
            let disp = position - lastPos
            let movement = simd_length(disp)
            guard movement > 0.002 else { return false } // ignore micro-movements

            // Project displacement on principal axis (use simple heuristic X or Y or Z with largest variance)
            let axis = principalAxis(from: [disp])
            let projected = simd_dot(position, axis)

            if let lastVal = lastProjectedValue {
                let sign = projected >= lastVal ? 1 : -1
                if sign != lastDirectionSign && lastDirectionSign != 0 {
                    // Direction change detected
                    if timestamp - internalLastRepTimestamp > minimumInterRepInterval {
                        if rom >= 8.0 { // minimal ROM check for pendulum
                            FlexaLog.motion.info("✅ [ARKit-Dir] Direction-change rep detected. ROM=\(String(format: "%.1f", rom))°")
                            incrementRep(timestamp: timestamp, rom: rom)
                            lastDirectionSign = sign
                            lastProjectedValue = projected
                            return true
                        } else {
                            FlexaLog.motion.debug("🔁 [ARKit-Dir] Direction-change ignored due to low ROM=\(String(format: "%.1f", rom))°")
                        }
                    }
                }
                lastDirectionSign = sign
            } else {
                lastDirectionSign = 0
            }

            lastProjectedValue = projected
            return false
        }

        // MARK: - Circular Rep Detection

        /// Detects circle completion for Follow Circle and Witch Brew games
        /// Requirements: 2.1, 2.6
        /// Algorithm:
        /// 1. Establish circle center using moving average
        /// 2. Calculate angle from center for each position
        /// 3. Accumulate angle changes
        /// 4. Detect completion when accumulated angle >= 2π
        /// 5. Enforce 0.4s cooldown
        private func detectCircularRep(position: SIMD3<Float>, timestamp: TimeInterval) {
            // Step 1: Establish circle center using moving average
            if circleCenter == nil {
                // Initialize center at first position
                circleCenter = position
                lastPosition = position
                FlexaLog.motion.debug("🔁 [HandheldRep][Circular] Circle center initialized")
                return
            }

            guard var center = circleCenter else { return }

            // Update center using exponential moving average (drift parameter)
            center = center * (1.0 - parameters.circleCenterDrift) + position * parameters.circleCenterDrift
            circleCenter = center

            // Calculate position relative to center
            let currentRelative = position - center
            let radius = length(currentRelative)

            // Require minimum radius to avoid noise at center
            guard radius >= parameters.circleRadiusThreshold else {
                return
            }

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
                FlexaLog.motion.debug("🔁 [HandheldRep][Circular] Coordinate system initialized")
                return
            }

            guard var axisPrimary = circleAxisPrimary, var axisSecondary = circleAxisSecondary else { return }

            // Smooth coordinate system to handle 3D motion
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

            // Step 2: Calculate angle from center for each position
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
            if abs(angleDelta) > parameters.maxAngleStep {
                angleDelta = max(-parameters.maxAngleStep, min(parameters.maxAngleStep, angleDelta))
            }

            // Step 3: Accumulate angle changes
            angleAccumulator += angleDelta

            // Step 5: Enforce 0.4s cooldown
            let cooldownPeriod: TimeInterval = 0.4
            let cooldownMet = (timestamp - internalLastRepTimestamp) >= cooldownPeriod

            // Step 4: Detect completion when accumulated angle >= 2π
            let fullCircle: Float = 2 * .pi
            if cooldownMet && abs(angleAccumulator) >= fullCircle {
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
            // Enforce global minimum inter-rep interval to avoid chatter
            guard timestamp - self.internalLastRepTimestamp >= self.minimumInterRepInterval else {
                FlexaLog.motion.debug("⚠️ [RepDetector] Ignored rep due to minimum inter-rep interval (\(String(format: "%.3f", timestamp - self.internalLastRepTimestamp))s < \(self.minimumInterRepInterval)s)")
                // Reset rep state but do not increment
                self.resetRepState()
                return
            }
            internalLastRepTimestamp = timestamp

            // Enforce a minimum ROM threshold for small pendulum handheld games
            // to avoid false-positive rep counts from very small movements.
            // Require at least 8 degrees for Fruit Slicer and Fan the Flame.
            let minimumPendulumROM: Double = 8.0
            if (self.gameType == .fruitSlicer || self.gameType == .fanOutFlame) {
                if rom < minimumPendulumROM {
                    FlexaLog.motion.info("⚠️ [PendulumRep] Ignored rep due to low ROM (\(String(format: "%.1f", rom))° < \(minimumPendulumROM)°)")
                    // Reset hysteresis and return without awarding a rep
                    self.resetRepState()
                    return
                }
            }

            // Update ROM baseline position only when a rep is detected
            // This ensures ROM starts fresh for each new rep
            if let lastPosition = pendulumLastPosition {
                romBaselinePosition = lastPosition
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.currentReps += 1
                self.lastRepTimestamp = timestamp
                FlexaLog.motion.info("✅ [REP DETECTED] Rep #\(self.currentReps) | ROM: \(String(format: "%.1f", rom))°")
                self.onRepDetected?(self.currentReps, timestamp)
            }

            self.resetRepState()
        }

        private func resetRepState() {
            repState = .idle
            peakROM = 0
            repStartROM = 0
            repStartTimestamp = 0
            pendulumLastPosition = nil
            pendulumLastDirection = nil

            // Reset hysteresis state
            isPeakActive = false
            peakMagnitude = 0.0
            lastMovementMagnitude = 0.0
        }

        /// Simple fallback ROM estimator (deg) using angle between baseline and current position around origin
        private static func simpleROMEstimate(from baseline: SIMD3<Float>, to current: SIMD3<Float>) -> Double {
            let b = SIMD3<Double>(Double(baseline.x), Double(baseline.y), Double(baseline.z))
            let c = SIMD3<Double>(Double(current.x), Double(current.y), Double(current.z))
            let db = b / simd_length(b)
            let dc = c / simd_length(c)
            let dotp = max(-1.0, min(1.0, Double(simd_dot(SIMD3<Double>(db), SIMD3<Double>(dc)))));
            let angle = acos(dotp) * 180.0 / .pi
            return angle.isFinite ? angle : 0.0
        }

    // ...existing code...
}
