import Foundation
import CoreMotion
import SwiftUI

// MARK: - Unified Rep Detection Service
class UnifiedRepDetectionService: ObservableObject {
    
    // MARK: - Game-Specific Rep Detectors
    enum GameType: String, CaseIterable {
        case fruitSlicer = "fruitSlicer"
        case hammerTime = "hammerTime"
        case followCircle = "followCircle"
        case balloonPop = "balloonPop"
        case constellationMaker = "constellationMaker"
        case wallClimbers = "wallClimbers"
        case fanOutFlame = "fanOutFlame"
        case makeYourOwn = "makeYourOwn"
    }
    
    deinit {
        // Reset all detectors to clean up their state
        resetForNewSession()
        print("🧹 [UnifiedRepDetectionService] Deinitializing and cleaning up resources")
    }
    
    // Basic ROM-threshold rep detection used for default games
    private var lastROM: Double = 0
    private var wasAbove: Bool = false
    private var lastRomTimestamp: TimeInterval = 0
    private let romThreshold: Double = 20
    private let minRepGap: TimeInterval = 0.5
    
    private func updateReps(rom: Double, timestamp: TimeInterval) {
        let above = rom >= romThreshold
        if above && !wasAbove {
            // Rising edge
            if timestamp - lastRomTimestamp >= minRepGap {
                registerRep()
                lastRomTimestamp = timestamp
            }
        }
        wasAbove = above
        lastROM = rom
    }
    
    @Published var currentReps: Int = 0
    @Published var repRate: Double = 0.0 // Reps per minute
    
    private var gameType: GameType = .fruitSlicer
    private var sessionStartTime: Date = Date()
    private var lastRepTime: Date = Date()
    
    // Game-specific detectors
    private var pendulumDetector = PendulumRepDetector()
    private var circularDetector = CircularMotionDetector()
    private var forearmDetector = ForearmSwingDetector()
    private var fanMotionDetector = FanMotionDetector()
    private var visionRepDetector = VisionBasedRepDetector()
    
    func startSession(gameType: GameType) {
        self.gameType = gameType
        currentReps = 0
        sessionStartTime = Date()
        lastRepTime = Date()
        
        // Reset all detectors
        pendulumDetector.reset()
        circularDetector.reset()
        forearmDetector.reset()
        fanMotionDetector.reset()
        visionRepDetector.reset()
        
        print("🔢 [RepDetection] Started session for \(gameType)")
    }
    
    func resetForNewSession() {
        currentReps = 0
        pendulumDetector.reset()
        circularDetector.reset()
        forearmDetector.reset()
        fanMotionDetector.reset()
        visionRepDetector.reset()
        print("🔢 [RepDetection] Reset for new session")
    }
    
    func updateFromGame(_ gameType: GameType, rom: Double, timestamp: TimeInterval) {
        self.gameType = gameType
        
        switch gameType {
        case .constellationMaker:
            // Reps are triggered externally by stroke completion in the game
            break
        case .wallClimbers:
            // Reps are triggered externally by checkpoint reaches in the game
            break
        case .makeYourOwn:
            // Reps are handled internally by smart motion detection in the game view
            break
        default:
            // Use ROM-based detection for other games
            updateReps(rom: rom, timestamp: timestamp)
        }
    }
    
    // MARK: - Game-Specific Rep Detection Methods
    
    func processPendulumSwing(rom: Double, timestamp: TimeInterval, threshold: Double, minGap: TimeInterval) -> Bool {
        return pendulumDetector.process(rom: rom, timestamp: timestamp, threshold: threshold, minGap: minGap)
    }
    
    func processCircularMotion(rom: Double, timestamp: TimeInterval, threshold: Double, minGap: TimeInterval) -> Bool {
        return circularDetector.process(rom: rom, timestamp: timestamp, threshold: threshold, minGap: minGap)
    }

    func processCircularMotion(_ motion: CMDeviceMotion, timestamp: Date) -> Bool {
        return circularDetector.processMotion(motion, timestamp: timestamp)
    }
    
    func processForearmSwing(rom: Double, timestamp: TimeInterval, threshold: Double, minGap: TimeInterval) -> Bool {
        return forearmDetector.process(rom: rom, timestamp: timestamp, threshold: threshold, minGap: minGap)
    }
    
    func processFanMotion(rom: Double, timestamp: TimeInterval, threshold: Double, minGap: TimeInterval) -> Bool {
        // Use specialized fan detector for left/right swing detection
        return fanMotionDetector.process(rom: rom, timestamp: timestamp, threshold: threshold, minGap: minGap)
    }
    
    func processVisionRep(rom: Double, timestamp: TimeInterval, threshold: Double, minGap: TimeInterval) -> Bool {
        return visionRepDetector.process(rom: rom, timestamp: timestamp, threshold: threshold, minGap: minGap)
    }

    // Direct motion-based processing for Fan Out the Flame (yaw crossings)
    func processFanMotion(_ motion: CMDeviceMotion, timestamp: Date) -> Bool {
        return fanMotionDetector.processMotion(motion, timestamp: timestamp)
    }
    
    func processDefaultRep(rom: Double, timestamp: TimeInterval) -> Bool {
        // Default detection with standard thresholds
        let above = rom >= romThreshold
        if above && !wasAbove {
            if timestamp - lastRomTimestamp >= minRepGap {
                wasAbove = above
                lastRomTimestamp = timestamp
                return true
            }
        }
        wasAbove = above
        return false
    }
    
    // Public wrapper to use motion-based pendulum detector for Fruit Slicer
    func processFruitSlicerMotion(_ motion: CMDeviceMotion, timestamp: Date) -> Bool {
        return pendulumDetector.processMotion(motion, timestamp: timestamp)
    }
    
    func processMotionData(gameType: SimpleMotionService.GameType, rom: Double, timestamp: TimeInterval, deviceMotion: CMDeviceMotion?) -> Int {
        let timestamp = Date()
        var repDetected = false
        
        switch gameType {
        case .fruitSlicer:
            if let motion = deviceMotion {
                repDetected = pendulumDetector.processMotion(motion, timestamp: timestamp)
            }
        case .followCircle:
            if let motion = deviceMotion {
                repDetected = circularDetector.processMotion(motion, timestamp: timestamp)
            }
        case .fanOutFlame:
            if let motion = deviceMotion {
                repDetected = fanMotionDetector.processMotion(motion, timestamp: timestamp)
            }
        case .constellation:
            // Strokes are detected by the game itself via star connections
            // This method is called by the game when a stroke is completed
            repDetected = true
        case .wallClimbers:
            // Climbing reps are detected by the game itself via checkpoint reaches
            // This method is called by the game when a checkpoint is reached
            repDetected = true
        default:
            break
        }
        
        if repDetected {
            currentReps += 1
            print("🔢 [RepDetection] Rep detected! Total: \(currentReps)")
        }
        
        return currentReps
    }
    
    func processVisionData(keypoints: SimplifiedPoseKeypoints) -> Bool {
        let timestamp = Date()
        var repDetected = false
        
        switch gameType {
        case .balloonPop:
            repDetected = visionRepDetector.processBalloonPopRep(keypoints: keypoints, timestamp: timestamp)
            
        default:
            // Handheld games should use processIMUData
            break
        }
        
        if repDetected {
            registerRep()
        }
        
        return repDetected
    }
    
    private func registerRep() {
        currentReps += 1
        lastRepTime = Date()
        
        // Calculate rep rate (reps per minute)
        let sessionDuration = Date().timeIntervalSince(sessionStartTime) / 60.0 // Convert to minutes
        repRate = sessionDuration > 0 ? Double(currentReps) / sessionDuration : 0
        
        print("🎯 [RepDetection] Rep #\(currentReps) detected for \(gameType)")
        
        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }
    
    func getSessionSummary() -> (reps: Int, repRate: Double, sessionDuration: TimeInterval) {
        let sessionDuration = Date().timeIntervalSince(sessionStartTime)
        return (currentReps, repRate, sessionDuration)
    }
}

// MARK: - Game-Specific Detectors

// Base Rep Detector
class BaseRepDetector {
    var lastROM: Double = 0
    var wasAbove: Bool = false
    var lastRepTime: TimeInterval = 0
    
    func reset() {
        lastROM = 0
        wasAbove = false
        lastRepTime = 0
    }
    
    func process(rom: Double, timestamp: TimeInterval, threshold: Double, minGap: TimeInterval) -> Bool {
        let above = rom >= threshold
        if above && !wasAbove {
            if timestamp - lastRepTime >= minGap {
                lastRepTime = timestamp
                wasAbove = above
                lastROM = rom
                return true
            }
        }
        wasAbove = above
        lastROM = rom
        return false
    }
}

// Pendulum Rep Detector for Fruit Slicer
class PendulumRepDetector: BaseRepDetector {
    private var angleHistory: [Double] = []
    private var timestamps: [Date] = []
    private let minRepInterval: TimeInterval = 0.4 // Minimum time between reps
    private let minSwingAmplitude: Double = 15.0 // Minimum degrees for a rep
    
    private var pendulumLastRepTime: TimeInterval = 0
    private var isSwingingForward = false
    private var lastAngle: Double = 0
    private var swingPeakForward: Double = 0
    private var swingPeakBackward: Double = 0
    
    func processMotion(_ motion: CMDeviceMotion, timestamp: Date) -> Bool {
        // Use Y-axis user acceleration for pendulum motion (up/down swings)
        // Phone held pointing down, swinging forward/backward
        let upDownAccel = motion.userAcceleration.y
        let forwardBackAccel = motion.userAcceleration.z
        
        // Combine both axes for comprehensive pendulum detection
        let totalAccel = sqrt(upDownAccel * upDownAccel + forwardBackAccel * forwardBackAccel)
        
        angleHistory.append(totalAccel)
        timestamps.append(timestamp)
        
        // Keep rolling window
        if angleHistory.count > 30 {
            angleHistory.removeFirst()
            timestamps.removeFirst()
        }
        
        guard angleHistory.count > 5 else { return false }
        
        // Detect significant acceleration changes (swing peaks)
        let accelDelta = totalAccel - lastAngle
        lastAngle = totalAccel
        
        // Detect swing direction change based on acceleration pattern
        if accelDelta > 0.3 && !isSwingingForward {
            // Significant positive acceleration - forward swing
            isSwingingForward = true
            swingPeakBackward = totalAccel
            
            // Check if previous swing amplitude was sufficient
            let swingAmplitude = abs(totalAccel - swingPeakForward)
            
            if swingAmplitude > minSwingAmplitude &&
               (Date().timeIntervalSince1970 - pendulumLastRepTime) > minRepInterval {
                pendulumLastRepTime = Date().timeIntervalSince1970
                return true
            }
        } else if accelDelta < 0 && isSwingingForward {
            // Changed from forward to backward - count as rep
            isSwingingForward = false
            swingPeakForward = totalAccel
            
            // Check if swing amplitude is sufficient
            let swingAmplitude = abs(swingPeakForward - swingPeakBackward)
            
            if swingAmplitude > minSwingAmplitude &&
               (Date().timeIntervalSince1970 - pendulumLastRepTime) > minRepInterval {
                pendulumLastRepTime = Date().timeIntervalSince1970
                return true
            }
        }
        
        return false
    }
    
    override func reset() {
        super.reset()
        angleHistory.removeAll()
        timestamps.removeAll()
        pendulumLastRepTime = 0
        isSwingingForward = false
        lastAngle = 0
        swingPeakForward = 0
        swingPeakBackward = 0
    }
}

// MARK: - Circular Motion Detector for Witch Brew
class CircularMotionDetector: BaseRepDetector {
    private var rotationHistory: [Double] = []
    private var timestamps: [Date] = []
    private let minCircleTime: TimeInterval = 0.8 // Minimum time window for one circle
    private let minRotationThreshold: Double = 330.0 // Require near-full rotation to count as a rep
    
    private var totalRotation: Double = 0
    private var lastYaw: Double = 0
    private var circleStartTime: Date = Date()
    private var circularLastRepTime: TimeInterval = 0
    
    func processMotion(_ motion: CMDeviceMotion, timestamp: Date) -> Bool {
        let yawAngle = motion.attitude.yaw * 180.0 / .pi
        
        // Calculate rotation delta (handle wrap-around)
        var deltaRotation = yawAngle - lastYaw
        if deltaRotation > 180 { deltaRotation -= 360 }
        if deltaRotation < -180 { deltaRotation += 360 }
        
        totalRotation += abs(deltaRotation)
        lastYaw = yawAngle
        
        rotationHistory.append(totalRotation)
        timestamps.append(timestamp)
        
        // Keep rolling window for circle detection
        if rotationHistory.count > 60 { // ~1 second at 60fps
            rotationHistory.removeFirst()
            timestamps.removeFirst()
        }
        
        // Check for complete circle
        if totalRotation >= minRotationThreshold {
            let circleTime = timestamp.timeIntervalSince(circleStartTime)
            
            if circleTime >= minCircleTime &&
               (Date().timeIntervalSince1970 - circularLastRepTime) > minCircleTime {
                // Complete circle detected
                totalRotation = 0
                circleStartTime = Date()
                circularLastRepTime = Date().timeIntervalSince1970
                return true
            }
        }
        
        return false
    }
    
    override func reset() {
        super.reset()
        rotationHistory.removeAll()
        timestamps.removeAll()
        totalRotation = 0
        lastYaw = 0
        circleStartTime = Date()
        circularLastRepTime = 0
    }
}

// MARK: - Forearm Swing Detector for Hammer Time
class ForearmSwingDetector: BaseRepDetector {
    private var rollHistory: [Double] = []
    private var timestamps: [Date] = []
    private let minSwingAmplitude: Double = 20.0 // Minimum degrees for forearm swing
    private let minRepInterval: TimeInterval = 0.6 // Minimum time between swings
    
    private var lastRollAngle: Double = 0
    private var swingPeakHigh: Double = 0
    private var swingPeakLow: Double = 0
    private var isSwingingUp = false
    private var forearmLastRepTime: TimeInterval = 0
    
    func processMotion(_ motion: CMDeviceMotion, timestamp: Date) -> Bool {
        // Use roll angle for side-lying forearm movement
        let rollAngle = motion.attitude.roll * 180.0 / .pi
        
        rollHistory.append(rollAngle)
        timestamps.append(timestamp)
        
        if rollHistory.count > 30 {
            rollHistory.removeFirst()
            timestamps.removeFirst()
        }
        
        guard rollHistory.count > 3 else { return false }
        
        // Detect swing direction change
        let rollDelta = rollAngle - lastRollAngle
        lastRollAngle = rollAngle
        
        // Track swing peaks
        if rollDelta > 0 && !isSwingingUp {
            // Changed from down to up swing
            isSwingingUp = true
            swingPeakLow = rollAngle
        } else if rollDelta < 0 && isSwingingUp {
            // Changed from up to down swing - rep detected
            isSwingingUp = false
            swingPeakHigh = rollAngle
            
            let swingAmplitude = abs(swingPeakHigh - swingPeakLow)
            
            if swingAmplitude > minSwingAmplitude &&
               (Date().timeIntervalSince1970 - forearmLastRepTime) > minRepInterval {
                forearmLastRepTime = Date().timeIntervalSince1970
                return true
            }
        }
        
        return false
    }
    
    override func reset() {
        super.reset()
        rollHistory.removeAll()
        timestamps.removeAll()
        lastRollAngle = 0
        swingPeakHigh = 0
        swingPeakLow = 0
        isSwingingUp = false
        forearmLastRepTime = 0
    }
}

// MARK: - Vision-Based Rep Detector for Camera Exercises
class VisionBasedRepDetector: BaseRepDetector {
    private var armPositionHistory: [CGPoint] = []
    private var elbowAngleHistory: [Double] = []
    private var timestamps: [Date] = []
    private let minRepInterval: TimeInterval = 0.8 // Minimum time between reps
    
    private var visionLastRepTime: TimeInterval = 0
    private var lastArmHeight: CGFloat = 0
    private var lastElbowAngle: Double = 0
    private var isRaisingArm = false
    private var isExtendingElbow = false
    
    // Wall Climbers: detect upward climb motion
    func processWallClimbersRep(keypoints: SimplifiedPoseKeypoints, timestamp: Date) -> Bool {
        guard let leftWrist = keypoints.leftWrist,
              let rightWrist = keypoints.rightWrist else { return false }
        
        // Use average wrist height as climb indicator
        let avgWristHeight = (leftWrist.y + rightWrist.y) / 2
        
        armPositionHistory.append(CGPoint(x: 0, y: avgWristHeight))
        timestamps.append(timestamp)
        
        if armPositionHistory.count > 20 {
            armPositionHistory.removeFirst()
            timestamps.removeFirst()
        }
        
        guard armPositionHistory.count > 5 else { return false }
        
        // Detect climbing motion (wrists moving up significantly)
        let heightDelta = avgWristHeight - lastArmHeight
        lastArmHeight = avgWristHeight
        
        if heightDelta < -30 && !isRaisingArm { // Moving up (y decreases)
            isRaisingArm = true
        } else if heightDelta > 10 && isRaisingArm { // Completed climb
            isRaisingArm = false
            
            if (Date().timeIntervalSince1970 - visionLastRepTime) > minRepInterval {
                visionLastRepTime = Date().timeIntervalSince1970
                return true
            }
        }
        
        return false
    }
    
    // Arm Raises: detect full arm raise motion
    func processArmRaisesRep(keypoints: SimplifiedPoseKeypoints, timestamp: Date) -> Bool {
        guard let leftShoulder = keypoints.leftShoulder,
              let rightShoulder = keypoints.rightShoulder,
              let leftWrist = keypoints.leftWrist,
              let rightWrist = keypoints.rightWrist else { return false }
        
        // Calculate arm elevation (wrist height relative to shoulder)
        let leftArmElevation = leftShoulder.y - (leftWrist.y)
        let rightArmElevation = rightShoulder.y - (rightWrist.y)
        let maxElevation = max(leftArmElevation, rightArmElevation)
        
        armPositionHistory.append(CGPoint(x: 0, y: maxElevation))
        timestamps.append(timestamp)
        
        if armPositionHistory.count > 20 {
            armPositionHistory.removeFirst()
            timestamps.removeFirst()
        }
        
        guard armPositionHistory.count > 5 else { return false }
        
        let elevationDelta = maxElevation - lastArmHeight
        lastArmHeight = maxElevation
        
        if elevationDelta > 20 && !isRaisingArm { // Arm going up
            isRaisingArm = true
        } else if elevationDelta < -15 && isRaisingArm { // Arm coming down
            isRaisingArm = false
            
            if (Date().timeIntervalSince1970 - visionLastRepTime) > minRepInterval {
                visionLastRepTime = Date().timeIntervalSince1970
                return true
            }
        }
        
        return false
    }
    
    // Balloon Pop: detect elbow extension (not armpit ROM)
    func processBalloonPopRep(keypoints: SimplifiedPoseKeypoints, timestamp: Date) -> Bool {
        // Calculate elbow angles for both arms
        let leftElbowAngle = calculateElbowAngle(
            shoulder: keypoints.leftShoulder,
            elbow: keypoints.leftElbow,
            wrist: keypoints.leftWrist
        )
        
        let rightElbowAngle = calculateElbowAngle(
            shoulder: keypoints.rightShoulder,
            elbow: keypoints.rightElbow,
            wrist: keypoints.rightWrist
        )
        
        let maxElbowAngle = max(leftElbowAngle, rightElbowAngle)
        
        elbowAngleHistory.append(maxElbowAngle)
        timestamps.append(timestamp)
        
        if elbowAngleHistory.count > 20 {
            elbowAngleHistory.removeFirst()
            timestamps.removeFirst()
        }
        
        guard elbowAngleHistory.count > 5 else { return false }
        
        let angleDelta = maxElbowAngle - lastElbowAngle
        lastElbowAngle = maxElbowAngle
        
        // Detect elbow extension (angle increasing) followed by flexion
        if angleDelta > 5 && !isExtendingElbow { // Extending elbow
            isExtendingElbow = true
        } else if angleDelta < -5 && isExtendingElbow { // Flexing elbow
            isExtendingElbow = false
            
            if (Date().timeIntervalSince1970 - visionLastRepTime) > minRepInterval {
                visionLastRepTime = Date().timeIntervalSince1970
                return true
            }
        }
        
        return false
    }
    
    private func calculateElbowAngle(shoulder: CGPoint?, elbow: CGPoint?, wrist: CGPoint?) -> Double {
        guard let shoulder = shoulder,
              let elbow = elbow,
              let wrist = wrist else { return 0 }
        
        // Calculate vectors
        let upperArm = CGPoint(x: elbow.x - shoulder.x, y: elbow.y - shoulder.y)
        let forearm = CGPoint(x: wrist.x - elbow.x, y: wrist.y - elbow.y)
        
        // Calculate angle between vectors
        let dot = upperArm.x * forearm.x + upperArm.y * forearm.y
        let upperArmMag = sqrt(upperArm.x * upperArm.x + upperArm.y * upperArm.y)
        let forearmMag = sqrt(forearm.x * forearm.x + forearm.y * forearm.y)
        
        if upperArmMag > 0 && forearmMag > 0 {
            let cosAngle = dot / (upperArmMag * forearmMag)
            let clampedCos = max(-1.0, min(1.0, cosAngle))
            let angleRad = acos(clampedCos)
            return angleRad * 180.0 / .pi
        }
        
        return 0
    }
    
    override func reset() {
        super.reset()
        armPositionHistory.removeAll()
        elbowAngleHistory.removeAll()
        timestamps.removeAll()
        visionLastRepTime = 0
        lastArmHeight = 0
        lastElbowAngle = 0
        isRaisingArm = false
        isExtendingElbow = false
    }
}

// MARK: - Fan Motion Detector for Fan Out the Flame
class FanMotionDetector: BaseRepDetector {
    private var yawHistory: [Double] = []
    private var timestamps: [Date] = []
    // CRITICAL FIX: A FULL SWING (left→right OR right→left) = ONE REP
    // Not two separate reps for each direction!
    private let minSwingAmplitude: Double = 15.0 // Lower threshold for users in rehab
    private let minRepInterval: TimeInterval = 0.4 // Faster swings allowed
    private let centerDeadband: Double = 7.0 // degrees around center that counts as neutral
    private let smoothingFactor: Double = 0.22
    private let minCenterHoldDuration: TimeInterval = 0.15 // Shorter hold for responsive detection
    private let accelSmoothingFactor: Double = 0.25
    private let accelThreshold: Double = 0.30 // Slightly lower threshold for easier detection
    private let accelCenterDeadband: Double = 0.10
    private let yawVelocityThreshold: Double = 35.0 // Lower velocity threshold for easier swings
    private let yawVelocitySmoothingFactor: Double = 0.25
    private let centerDriftFactor: Double = 0.015
    
    private var fanLastRepTime: TimeInterval = 0
    private var centerPosition: Double = 0
    private var hasEstablishedCenter = false
    private var swingPeakLeft: Double = 0
    private var swingPeakRight: Double = 0
    private enum SwingPhase { case center, left, right }
    private var swingPhase: SwingPhase = .center
    private var lastCompletedSwing: SwingPhase = .center // Track last swing direction
    private var filteredYawVelocity: Double?
    private var filteredLateralAccel: Double?
    private var lastYawCenterTime: TimeInterval = 0
    private var lastAccelNeutralTime: TimeInterval = 0
    private var lastYawSample: Double = 0
    private var lastYawSampleTime: TimeInterval = 0
    
    func processMotion(_ motion: CMDeviceMotion, timestamp: Date) -> Bool {
        // Use pure gravity-compensated lateral acceleration for left/right fan motion
        let lateralAccelRaw = computeLateralAcceleration(from: motion)
        let smoothedLateralAccel: Double
        if let previous = filteredLateralAccel {
            smoothedLateralAccel = previous + accelSmoothingFactor * (lateralAccelRaw - previous)
        } else {
            smoothedLateralAccel = lateralAccelRaw
        }
        filteredLateralAccel = smoothedLateralAccel
        let timestampValue = timestamp.timeIntervalSince1970
        
        yawHistory.append(smoothedLateralAccel)
        timestamps.append(timestamp)
        if yawHistory.count > 30 { yawHistory.removeFirst(); timestamps.removeFirst() }

        // Establish center as zero (lateral acceleration center)
        if !hasEstablishedCenter && yawHistory.count >= 10 {
            centerPosition = 0 // Lateral acceleration center is zero
            hasEstablishedCenter = true
            swingPeakLeft = centerPosition
            swingPeakRight = centerPosition
            swingPhase = .center
            lastCompletedSwing = .center
            filteredYawVelocity = 0
            lastYawSample = 0
            lastYawSampleTime = timestampValue
            lastYawCenterTime = timestampValue
            lastAccelNeutralTime = timestampValue
        }
        guard hasEstablishedCenter else { return false }

        // Calculate velocity from acceleration
        let deltaTime = max(0.001, timestampValue - lastYawSampleTime)
        let accelChange = smoothedLateralAccel - lastYawSample
        let velocityEstimate = accelChange / deltaTime
        var lateralVelocity: Double
        if let previous = filteredYawVelocity {
            lateralVelocity = previous + yawVelocitySmoothingFactor * (velocityEstimate - previous)
            // Apply decay to prevent drift
            lateralVelocity *= 0.98
        } else {
            lateralVelocity = velocityEstimate
        }
        filteredYawVelocity = lateralVelocity
        lastYawSample = smoothedLateralAccel
        lastYawSampleTime = timestampValue

        // Calculate relative acceleration from center
        let relativeAccel = smoothedLateralAccel - centerPosition

        // Track peak positions for amplitude logging
        if relativeAccel < 0 {
            swingPeakLeft = min(swingPeakLeft, smoothedLateralAccel)
        } else if relativeAccel > 0 {
            swingPeakRight = max(swingPeakRight, smoothedLateralAccel)
        }

        let now = timestampValue
        let amplitude = abs(relativeAccel)
        if abs(relativeAccel) <= accelCenterDeadband && abs(lateralVelocity) <= yawVelocityThreshold * 0.01 {
            swingPhase = .center
            swingPeakLeft = centerPosition
            swingPeakRight = centerPosition
            centerPosition += centerDriftFactor * (smoothedLateralAccel - centerPosition)
            lastYawCenterTime = now
        }
        if abs(smoothedLateralAccel) <= accelCenterDeadband {
            lastAccelNeutralTime = now
        }

        let lastNeutralTime = max(lastYawCenterTime, lastAccelNeutralTime)
        let timeSinceNeutral = now - lastNeutralTime
        let accelValue = smoothedLateralAccel
        let velocityValue = lateralVelocity

        // CRITICAL FIX: Only count as rep if swinging in OPPOSITE direction from last completed swing
        // This makes a FULL CYCLE (left→right OR right→left) count as ONE rep
        if relativeAccel <= -accelThreshold {
            if swingPhase != .left {
                if (swingPhase == .right || swingPhase == .center),
                   amplitude >= accelThreshold,
                   timeSinceNeutral >= minCenterHoldDuration,
                   (now - fanLastRepTime) >= minRepInterval,
                   abs(velocityValue) >= yawVelocityThreshold * 0.01,
                   lastCompletedSwing != .left { // NEW: Only count if last swing was RIGHT or CENTER
                    fanLastRepTime = now
                    swingPhase = .left
                    lastCompletedSwing = .left // Mark this swing as completed
                    let swingRange = abs(swingPeakRight - swingPeakLeft)
                    let displayAmplitude = swingRange > 0 ? swingRange : amplitude * 2
                    swingPeakLeft = smoothedLateralAccel
                    swingPeakRight = centerPosition
                    print("🍃 [Fan] LEFT swing detected - Rep! Amplitude: \(String(format: "%.2f", displayAmplitude))g, accel: \(String(format: "%.2f", accelValue))g, vel: \(String(format: "%.2f", velocityValue))g/s")
                    return true
                }
                swingPhase = .left
            }
        } else if relativeAccel >= accelThreshold {
            if swingPhase != .right {
                if (swingPhase == .left || swingPhase == .center),
                   amplitude >= accelThreshold,
                   timeSinceNeutral >= minCenterHoldDuration,
                   (now - fanLastRepTime) >= minRepInterval,
                   abs(velocityValue) >= yawVelocityThreshold * 0.01,
                   lastCompletedSwing != .right { // NEW: Only count if last swing was LEFT or CENTER
                    fanLastRepTime = now
                    swingPhase = .right
                    lastCompletedSwing = .right // Mark this swing as completed
                    let swingRange = abs(swingPeakRight - swingPeakLeft)
                    let displayAmplitude = swingRange > 0 ? swingRange : amplitude * 2
                    swingPeakRight = smoothedLateralAccel
                    swingPeakLeft = centerPosition
                    print("🍃 [Fan] RIGHT swing detected - Rep! Amplitude: \(String(format: "%.2f", displayAmplitude))g, accel: \(String(format: "%.2f", accelValue))g, vel: \(String(format: "%.2f", velocityValue))g/s")
                    return true
                }
                swingPhase = .right
            }
        }

        return false
    }
    
    override func reset() {
        super.reset()
        yawHistory.removeAll()
        timestamps.removeAll()
        fanLastRepTime = 0
        centerPosition = 0
        hasEstablishedCenter = false
        swingPeakLeft = 0
        swingPeakRight = 0
        swingPhase = .center
        lastCompletedSwing = .center
        filteredYawVelocity = nil
        filteredLateralAccel = nil
        lastYawCenterTime = 0
        lastAccelNeutralTime = 0
        lastYawSample = 0
        lastYawSampleTime = 0
    }

    private func computeLateralAcceleration(from motion: CMDeviceMotion) -> Double {
        let linear = motion.userAcceleration
        let rotation = motion.attitude.rotationMatrix

        // Transform linear acceleration into reference frame
        let worldAx = rotation.m11 * linear.x + rotation.m12 * linear.y + rotation.m13 * linear.z
        let worldAy = rotation.m21 * linear.x + rotation.m22 * linear.y + rotation.m23 * linear.z
        let worldAz = rotation.m31 * linear.x + rotation.m32 * linear.y + rotation.m33 * linear.z

        // Normalize gravity vector for plane projection
        let gravity = motion.gravity
        let gravityMagnitude = sqrt(gravity.x * gravity.x + gravity.y * gravity.y + gravity.z * gravity.z)
        guard gravityMagnitude > 0.0001 else { return 0 }
        let gravityNormX = gravity.x / gravityMagnitude
        let gravityNormY = gravity.y / gravityMagnitude
        let gravityNormZ = gravity.z / gravityMagnitude

        // Device forward axis (screen normal) in reference frame
        let deviceZX = rotation.m13
        let deviceZY = rotation.m23
        let deviceZZ = rotation.m33

        // Lateral axis is perpendicular to both gravity and forward axis
        var lateralX = gravityNormY * deviceZZ - gravityNormZ * deviceZY
        var lateralY = gravityNormZ * deviceZX - gravityNormX * deviceZZ
        var lateralZ = gravityNormX * deviceZY - gravityNormY * deviceZX
        let lateralMagnitude = sqrt(lateralX * lateralX + lateralY * lateralY + lateralZ * lateralZ)

        if lateralMagnitude < 0.0001 {
            // Fallback: rotate gravity 90 degrees in horizontal plane
            lateralX = -gravityNormY
            lateralY = gravityNormX
            lateralZ = 0
            let fallbackMagnitude = sqrt(lateralX * lateralX + lateralY * lateralY + lateralZ * lateralZ)
            if fallbackMagnitude > 0.0001 {
                lateralX /= fallbackMagnitude
                lateralY /= fallbackMagnitude
                lateralZ /= fallbackMagnitude
            }
        } else {
            lateralX /= lateralMagnitude
            lateralY /= lateralMagnitude
            lateralZ /= lateralMagnitude
        }

        // Project world acceleration onto lateral axis
        let lateralAccel = worldAx * lateralX + worldAy * lateralY + worldAz * lateralZ
        return lateralAccel
    }
}

