import Foundation
import Combine
import CoreGraphics

// MARK: - Body Measurement Learning System

// MARK: - Supporting Structures for Enhanced Analysis
struct BodyProportions {
    var armToShoulderRatio: Double?
    var upperToForearmRatio: Double?
    var armToTorsoRatio: Double?
}

struct PoseQualityScore {
    var shoulderAvailable = false
    var elbowAvailable = false
    var wristAvailable = false
    var neckAvailable = false
    var shoulderConfidence = 0.0
    var elbowConfidence = 0.0
    var overallConfidence = 0.0
    var isSuitableForROM = false
}
struct BodyMeasurement {
    var value: Double
    var confidence: Double
    var sampleCount: Int
    
    init(value: Double = 0.0, confidence: Double = 0.0, sampleCount: Int = 0) {
        self.value = value
        self.confidence = confidence
        self.sampleCount = sampleCount
    }
    
    mutating func updateWithSample(_ newValue: Double, confidence newConfidence: Double) {
        if sampleCount == 0 {
            // First sample - accept if above minimum threshold
            if newConfidence > 0.1 {
                value = newValue
                confidence = newConfidence
                sampleCount = 1
            }
        } else {
            // Only update if new data is significantly higher quality
            let confidenceImprovement = newConfidence - confidence
            let shouldUpdate: Bool
            
            if newConfidence > 0.8 {
                // Very high confidence - always update
                shouldUpdate = true
            } else if confidenceImprovement > 0.2 {
                // Significant confidence improvement
                shouldUpdate = true
            } else if newConfidence > confidence && abs(newValue - value) / value < 0.3 {
                // Higher confidence and measurement is reasonable (within 30% of current)
                shouldUpdate = true
            } else {
                shouldUpdate = false
            }
            
            if shouldUpdate {
                let weight = min(newConfidence, 0.8) // Cap learning rate
                let currentWeight = confidence * Double(sampleCount) / (Double(sampleCount) + 1.0)
                let totalWeight = currentWeight + weight
                
                value = (value * currentWeight + newValue * weight) / totalWeight
                confidence = min((confidence + newConfidence) / 2.0, 1.0)
                sampleCount += 1
                
                print("📊 [BODY] Updated measurement: value=\(String(format: "%.1f", value)), confidence=\(String(format: "%.2f", confidence)), samples=\(sampleCount)")
            }
        }
    }
    
    var isReliable: Bool {
        return confidence > 0.7 && sampleCount > 5
    }
}

class BodyMeasurements: ObservableObject {
    @Published var leftArmLength = BodyMeasurement()
    @Published var rightArmLength = BodyMeasurement()
    @Published var leftUpperArmLength = BodyMeasurement()
    @Published var rightUpperArmLength = BodyMeasurement()
    @Published var leftForearmLength = BodyMeasurement()
    @Published var rightForearmLength = BodyMeasurement()
    @Published var shoulderWidth = BodyMeasurement()
    @Published var torsoLength = BodyMeasurement()
    @Published var torsoHeight = BodyMeasurement()
    @Published var hipWidth = BodyMeasurement()
    @Published var headHeight = BodyMeasurement()
    @Published var eyeDistance = BodyMeasurement()
    @Published var shoulderMidpoint: CGPoint?
    @Published var headCenter: CGPoint?
    
    private let userDefaults = UserDefaults.standard
    private let keyPrefix = "BodyMeasurement_"
    
    init() {
        loadFromUserDefaults()
    }
    
    func updateMeasurements(with keypoints: SimplifiedPoseKeypoints, poseConfidence: Float = 0.5) {
        // Only update if pose confidence is good enough
        guard poseConfidence > 0.1 else { return }
        
        let confidenceMultiplier = min(Double(poseConfidence), 0.9)
        
        // Calculate RIGHT arm lengths (focus on right arm for TestROM)
        if let rightShoulder = keypoints.rightShoulder,
           let rightElbow = keypoints.rightElbow,
           let rightWrist = keypoints.rightWrist {
            
            let upperArmLength = distance(rightShoulder, rightElbow)
            let forearmLength = distance(rightElbow, rightWrist)
            let totalArmLength = upperArmLength + forearmLength
            
            // Update with confidence based on pose quality
            rightUpperArmLength.updateWithSample(upperArmLength, confidence: confidenceMultiplier)
            rightForearmLength.updateWithSample(forearmLength, confidence: confidenceMultiplier)
            rightArmLength.updateWithSample(totalArmLength, confidence: confidenceMultiplier)
            
            print("📏 [BODY] Right arm measurements updated - Upper: \(String(format: "%.1f", upperArmLength)), Forearm: \(String(format: "%.1f", forearmLength))")
        }
        
        // Calculate LEFT arm lengths for completeness
        if let leftShoulder = keypoints.leftShoulder,
           let leftElbow = keypoints.leftElbow,
           let leftWrist = keypoints.leftWrist {
            
            let upperArmLength = distance(leftShoulder, leftElbow)
            let forearmLength = distance(leftElbow, leftWrist)
            let totalArmLength = upperArmLength + forearmLength
            
            leftUpperArmLength.updateWithSample(upperArmLength, confidence: confidenceMultiplier * 0.8)
            leftForearmLength.updateWithSample(forearmLength, confidence: confidenceMultiplier * 0.8)
            leftArmLength.updateWithSample(totalArmLength, confidence: confidenceMultiplier * 0.8)
        }
        
        // Calculate shoulder width for better ROM estimation
        if let leftShoulder = keypoints.leftShoulder,
           let rightShoulder = keypoints.rightShoulder {
            let width = distance(leftShoulder, rightShoulder)
            shoulderWidth.updateWithSample(width, confidence: confidenceMultiplier)
            
            print("📏 [BODY] Shoulder width updated: \(String(format: "%.1f", width))")
        }
        
        // Calculate torso measurements for better body proportions
        if let neck = keypoints.neck,
           let leftHip = keypoints.leftHip,
           let rightHip = keypoints.rightHip {
            
            let shoulderCenter = CGPoint(
                x: ((keypoints.leftShoulder?.x ?? 0) + (keypoints.rightShoulder?.x ?? 0)) / 2,
                y: ((keypoints.leftShoulder?.y ?? 0) + (keypoints.rightShoulder?.y ?? 0)) / 2
            )
            
            let hipCenter = CGPoint(x: (leftHip.x + rightHip.x) / 2, y: (leftHip.y + rightHip.y) / 2)
            let torsoLen = distance(shoulderCenter, hipCenter)
            let hipW = distance(leftHip, rightHip)
            let neckToShoulder = distance(neck, shoulderCenter)
            
            torsoLength.updateWithSample(torsoLen, confidence: confidenceMultiplier * 0.7)
            hipWidth.updateWithSample(hipW, confidence: confidenceMultiplier * 0.8)
            torsoHeight.updateWithSample(neckToShoulder, confidence: confidenceMultiplier * 0.6)
        }
        
        // Save updated measurements periodically
        if leftArmLength.sampleCount % 10 == 0 || rightArmLength.sampleCount % 10 == 0 {
            saveToUserDefaults()
        }
    }
    
    // Enhanced ROM calculation using learned body measurements
    func calculateEnhancedROM(keypoints: SimplifiedPoseKeypoints, side: BodySide) -> Double? {
        let (shoulder, elbow, wrist, hip, oppositeShoulder) = side == .left ?
            (keypoints.leftShoulder, keypoints.leftElbow, keypoints.leftWrist, keypoints.leftHip, keypoints.rightShoulder) :
            (keypoints.rightShoulder, keypoints.rightElbow, keypoints.rightWrist, keypoints.rightHip, keypoints.leftShoulder)
        
        let upperArmLength = side == .left ? leftUpperArmLength : rightUpperArmLength
        let forearmLength = side == .left ? leftForearmLength : rightForearmLength
        
        // If we have shoulder and elbow, compute torso-referenced abduction
        if let s = shoulder, let e = elbow {
            // Reference vector: prefer hip (torso), then perpendicular to shoulder line, else screen vertical
            let upperArm = CGPoint(x: e.x - s.x, y: e.y - s.y)
            let reference: CGPoint = {
                if let h = hip { return CGPoint(x: h.x - s.x, y: h.y - s.y) }
                if let opp = oppositeShoulder {
                    let shoulderLine = CGPoint(x: opp.x - s.x, y: opp.y - s.y)
                    // Perpendicular to shoulder line approximates torso vertical
                    return CGPoint(x: -shoulderLine.y, y: shoulderLine.x)
                }
                return CGPoint(x: 0, y: 1)
            }()
            let angle = angleBetween(upperArm, reference)
            return max(0, min(180, angle))
        }
        
        // If elbow is missing but we have reliable measurements and wrist, infer elbow
        if let s = shoulder, let w = wrist, upperArmLength.isReliable && forearmLength.isReliable {
            let e = estimateElbowPosition(
                shoulder: s,
                wrist: w,
                upperArmLength: upperArmLength.value,
                forearmLength: forearmLength.value
            )
            let upperArm = CGPoint(x: e.x - s.x, y: e.y - s.y)
            let reference: CGPoint = {
                if let h = hip { return CGPoint(x: h.x - s.x, y: h.y - s.y) }
                if let opp = oppositeShoulder {
                    let shoulderLine = CGPoint(x: opp.x - s.x, y: opp.y - s.y)
                    return CGPoint(x: -shoulderLine.y, y: shoulderLine.x)
                }
                return CGPoint(x: 0, y: 1)
            }()
            let angle = angleBetween(upperArm, reference)
            return max(0, min(180, angle))
        }
        
        // Fallback to basic method (may return nil if insufficient)
        return keypoints.calculateShoulderAbduction(side: side)
    }
    
    // MARK: - Adaptive ROM Calculation with Learned Body Measurements
    func getAdaptiveArmpitROM(baseAngle: Double, side: BodySide) -> Double {
        let armLength = side == .left ? leftArmLength : rightArmLength
        let upperArmLength = side == .left ? leftUpperArmLength : rightUpperArmLength
        
        var adjustedAngle = baseAngle
        
        // Use learned body measurements to improve ROM accuracy
        if armLength.isReliable && shoulderWidth.isReliable {
            // Adjust ROM based on arm-to-shoulder ratio
            let armToShoulderRatio = armLength.value / shoulderWidth.value
            let lengthFactor = 0.8 + (armToShoulderRatio - 2.0) * 0.1 // Typical ratio ~2.0
            adjustedAngle *= lengthFactor
            
            print("🔧 [ADAPTIVE] ROM adjusted by length factor \(String(format: "%.2f", lengthFactor)) for \(side) arm")
        }
        
        // Further adjust based on upper arm length if available
        if upperArmLength.isReliable {
            let upperArmFactor = 0.9 + (upperArmLength.value / 50.0 - 1.0) * 0.1 // Normalize to ~50px
            adjustedAngle *= upperArmFactor
        }
        
        return max(0, min(adjustedAngle, 180)) // Clamp to reasonable range
    }
    
    private func angleBetween(_ vector1: CGPoint, _ vector2: CGPoint) -> Double {
        let dot = vector1.x * vector2.x + vector1.y * vector2.y
        let mag1Sq = vector1.x * vector1.x + vector1.y * vector1.y
        let mag2Sq = vector2.x * vector2.x + vector2.y * vector2.y
        
        // Use epsilon for numerical stability
        let epsilon: CGFloat = 1e-10
        guard mag1Sq > epsilon, mag2Sq > epsilon else { return 0 }
        
        let mag1 = sqrt(mag1Sq)
        let mag2 = sqrt(mag2Sq)
        
        // Clamp cosine to valid range with high precision
        let cosA = max(-1.0, min(1.0, dot / (mag1 * mag2)))
        return acos(cosA) * 180.0 / .pi
    }
    
    func getEstimatedBodyScale() -> Double {
        // Use shoulder width as primary scale reference
        if shoulderWidth.isReliable {
            let scale = shoulderWidth.value / 40.0 // Typical shoulder width in screen coordinates
            print("📐 [SCALE] Body scale from shoulder width: \(String(format: "%.2f", scale))")
            return scale
        }
        
        // Fallback to right arm length (more reliable for ROM)
        if rightArmLength.isReliable {
            let scale = rightArmLength.value / 80.0 // Typical arm length
            print("📐 [SCALE] Body scale from right arm length: \(String(format: "%.2f", scale))")
            return scale
        }
        
        print("📐 [SCALE] Using default body scale (no reliable measurements)")
        return 1.0 // Default scale
    }
    
    private func estimateElbowPosition(shoulder: CGPoint, wrist: CGPoint, upperArmLength: Double, forearmLength: Double) -> CGPoint {
        let dx = Double(wrist.x - shoulder.x)
        let dy = Double(wrist.y - shoulder.y)
        let shoulderToWristDistanceSq = dx * dx + dy * dy
        let shoulderToWristDistance = sqrt(shoulderToWristDistanceSq)
        
        // Validate triangle inequality before applying law of cosines
        let totalArmLength = upperArmLength + forearmLength
        guard shoulderToWristDistance > abs(upperArmLength - forearmLength) && 
              shoulderToWristDistance < totalArmLength else {
            // Invalid triangle - return midpoint as fallback
            return CGPoint(x: (shoulder.x + wrist.x) / 2.0, y: (shoulder.y + wrist.y) / 2.0)
        }
        
        // Use law of cosines to find elbow angle with high precision
        let numerator = upperArmLength * upperArmLength + shoulderToWristDistanceSq - forearmLength * forearmLength
        let denominator = 2.0 * upperArmLength * shoulderToWristDistance
        let cosAngle = max(-1.0, min(1.0, numerator / denominator))
        let angle = acos(cosAngle)
        
        // Calculate elbow position with double precision
        let shoulderToWristAngle = atan2(dy, dx)
        let elbowAngle = shoulderToWristAngle + angle
        
        let elbowX = Double(shoulder.x) + upperArmLength * cos(elbowAngle)
        let elbowY = Double(shoulder.y) + upperArmLength * sin(elbowAngle)
        
        return CGPoint(x: CGFloat(elbowX), y: CGFloat(elbowY))
    }
    
    // VNRecognizedPoint distance method removed - using CGPoint-based calculations
    
    private func distance(_ p1: CGPoint, _ p2: CGPoint) -> Double {
        let dx = p1.x - p2.x
        let dy = p1.y - p2.y
        return sqrt(dx * dx + dy * dy)
    }
    
    private func saveToUserDefaults() {
        let measurements = [
            "leftArmLength": ["value": leftArmLength.value, "confidence": leftArmLength.confidence, "samples": Double(leftArmLength.sampleCount)],
            "rightArmLength": ["value": rightArmLength.value, "confidence": rightArmLength.confidence, "samples": Double(rightArmLength.sampleCount)],
            "leftUpperArmLength": ["value": leftUpperArmLength.value, "confidence": leftUpperArmLength.confidence, "samples": Double(leftUpperArmLength.sampleCount)],
            "rightUpperArmLength": ["value": rightUpperArmLength.value, "confidence": rightUpperArmLength.confidence, "samples": Double(rightUpperArmLength.sampleCount)],
            "leftForearmLength": ["value": leftForearmLength.value, "confidence": leftForearmLength.confidence, "samples": Double(leftForearmLength.sampleCount)],
            "rightForearmLength": ["value": rightForearmLength.value, "confidence": rightForearmLength.confidence, "samples": Double(rightForearmLength.sampleCount)],
            "shoulderWidth": ["value": shoulderWidth.value, "confidence": shoulderWidth.confidence, "samples": Double(shoulderWidth.sampleCount)],
            "torsoLength": ["value": torsoLength.value, "confidence": torsoLength.confidence, "samples": Double(torsoLength.sampleCount)],
            "torsoHeight": ["value": torsoHeight.value, "confidence": torsoHeight.confidence, "samples": Double(torsoHeight.sampleCount)]
        ]
        
        if let data = try? JSONSerialization.data(withJSONObject: measurements) {
            userDefaults.set(data, forKey: keyPrefix + "AllMeasurements")
        }
    }
    
    private func loadFromUserDefaults() {
        guard let data = userDefaults.data(forKey: keyPrefix + "AllMeasurements"),
              let measurements = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Double]] else { return }
        
        if let leftArm = measurements["leftArmLength"] {
            leftArmLength = BodyMeasurement(value: leftArm["value"] ?? 0, confidence: leftArm["confidence"] ?? 0, sampleCount: Int(leftArm["samples"] ?? 0))
        }
        if let rightArm = measurements["rightArmLength"] {
            rightArmLength = BodyMeasurement(value: rightArm["value"] ?? 0, confidence: rightArm["confidence"] ?? 0, sampleCount: Int(rightArm["samples"] ?? 0))
        }
        if let leftUpper = measurements["leftUpperArmLength"] {
            leftUpperArmLength = BodyMeasurement(value: leftUpper["value"] ?? 0, confidence: leftUpper["confidence"] ?? 0, sampleCount: Int(leftUpper["samples"] ?? 0))
        }
        if let rightUpper = measurements["rightUpperArmLength"] {
            rightUpperArmLength = BodyMeasurement(value: rightUpper["value"] ?? 0, confidence: rightUpper["confidence"] ?? 0, sampleCount: Int(rightUpper["samples"] ?? 0))
        }
        if let leftForearm = measurements["leftForearmLength"] {
            leftForearmLength = BodyMeasurement(value: leftForearm["value"] ?? 0, confidence: leftForearm["confidence"] ?? 0, sampleCount: Int(leftForearm["samples"] ?? 0))
        }
        if let rightForearm = measurements["rightForearmLength"] {
            rightForearmLength = BodyMeasurement(value: rightForearm["value"] ?? 0, confidence: rightForearm["confidence"] ?? 0, sampleCount: Int(rightForearm["samples"] ?? 0))
        }
        if let shoulder = measurements["shoulderWidth"] {
            shoulderWidth = BodyMeasurement(value: shoulder["value"] ?? 0, confidence: shoulder["confidence"] ?? 0, sampleCount: Int(shoulder["samples"] ?? 0))
        }
        if let torso = measurements["torsoLength"] {
            torsoLength = BodyMeasurement(value: torso["value"] ?? 0, confidence: torso["confidence"] ?? 0, sampleCount: Int(torso["samples"] ?? 0))
        }
        if let torsoH = measurements["torsoHeight"] {
            torsoHeight = BodyMeasurement(value: torsoH["value"] ?? 0, confidence: torsoH["confidence"] ?? 0, sampleCount: Int(torsoH["samples"] ?? 0))
        }
    }

    // MARK: - Apple Vision Enhanced Arm Length Measurement
    func getMeasuredArmLength() -> Double? {
        // Use right arm as primary (most reliable for ROM measurements)
        if rightArmLength.isReliable {
            let lengthInPixels = rightArmLength.value
            // Convert from screen pixels to approximate meters using anthropometric data
            let estimatedLengthInMeters = convertPixelLengthToMeters(lengthInPixels)
            print("📏 [VISION-ARMLENGTH] Right arm length: \(String(format: "%.3f", estimatedLengthInMeters))m (\(String(format: "%.1f", lengthInPixels))px)")
            return estimatedLengthInMeters
        }

        // Fallback to left arm if right is not reliable
        if leftArmLength.isReliable {
            let lengthInPixels = leftArmLength.value
            let estimatedLengthInMeters = convertPixelLengthToMeters(lengthInPixels)
            print("📏 [VISION-ARMLENGTH] Left arm length (fallback): \(String(format: "%.3f", estimatedLengthInMeters))m (\(String(format: "%.1f", lengthInPixels))px)")
            return estimatedLengthInMeters
        }

        print("⚠️ [VISION-ARMLENGTH] No reliable arm length measurement available")
        return nil
    }

    private func convertPixelLengthToMeters(_ pixelLength: Double) -> Double {
        // Use shoulder width as reference for scale estimation
        if shoulderWidth.isReliable {
            // Average adult shoulder width is approximately 40-45cm
            let averageShoulderWidthMeters = 0.42 // meters
            let shoulderWidthPixels = shoulderWidth.value
            let pixelsPerMeter = shoulderWidthPixels / averageShoulderWidthMeters
            let estimatedArmLengthMeters = pixelLength / pixelsPerMeter

            print("📏 [VISION-ARMLENGTH] Scale factor: \(String(format: "%.1f", pixelsPerMeter))px/m")
            return estimatedArmLengthMeters
        }

        // Fallback estimation using typical screen-to-world conversion
        // This is a rough estimate and may not be accurate without proper calibration
        let fallbackPixelsPerMeter = 250.0 // Rough estimate for typical camera setup
        let estimatedArmLengthMeters = pixelLength / fallbackPixelsPerMeter

        print("📏 [VISION-ARMLENGTH] Using fallback scale: \(String(format: "%.1f", fallbackPixelsPerMeter))px/m")
        return estimatedArmLengthMeters
    }

    // MARK: - Enhanced Body Proportions Analysis
    func analyzeBodyProportions() -> BodyProportions {
        var proportions = BodyProportions()

        // Calculate arm-to-body ratios for better ROM calibration
        if rightArmLength.isReliable && shoulderWidth.isReliable {
            proportions.armToShoulderRatio = rightArmLength.value / shoulderWidth.value
        }

        if rightUpperArmLength.isReliable && rightForearmLength.isReliable {
            proportions.upperToForearmRatio = rightUpperArmLength.value / rightForearmLength.value
        }

        if torsoLength.isReliable && rightArmLength.isReliable {
            proportions.armToTorsoRatio = rightArmLength.value / torsoLength.value
        }

        print("📊 [BODY-PROPORTIONS] Arm/shoulder: \(String(format: "%.2f", proportions.armToShoulderRatio ?? 0))")
        print("📊 [BODY-PROPORTIONS] Upper/forearm: \(String(format: "%.2f", proportions.upperToForearmRatio ?? 0))")
        print("📊 [BODY-PROPORTIONS] Arm/torso: \(String(format: "%.2f", proportions.armToTorsoRatio ?? 0))")
        
        return proportions
    }
    
    // MARK: - Apple Vision Pose Quality Assessment
    func assessPoseQuality(keypoints: SimplifiedPoseKeypoints) -> PoseQualityScore {
        var score = PoseQualityScore()
        
        // Check landmark availability
        score.shoulderAvailable = keypoints.leftShoulder != nil && keypoints.rightShoulder != nil
        score.elbowAvailable = keypoints.leftElbow != nil || keypoints.rightElbow != nil
        score.wristAvailable = keypoints.leftWrist != nil || keypoints.rightWrist != nil
        score.neckAvailable = keypoints.neck != nil
        
        // Confidence from Vision likelihoods
        let shoulderConfs = [Double(keypoints.leftShoulderConfidence), Double(keypoints.rightShoulderConfidence)]
        let elbowConfs = [Double(keypoints.leftElbowConfidence), Double(keypoints.rightElbowConfidence)]
        
        // Use min for shoulders (we need both), and max for elbows (at least one)
        score.shoulderConfidence = min(max(shoulderConfs[0], 0.0), 1.0)
        score.shoulderConfidence = min(score.shoulderConfidence, min(max(shoulderConfs[1], 0.0), 1.0))
        score.elbowConfidence = min(max(max(elbowConfs[0], elbowConfs[1]), 0.0), 1.0)
        
        // Weighted overall confidence
        score.overallConfidence = score.shoulderConfidence * 0.7 + score.elbowConfidence * 0.3
        
        // Determine suitability: shoulders visible + (elbows or wrists or reliable inference) + confidence threshold
        let canInferElbow = (rightUpperArmLength.isReliable && rightForearmLength.isReliable) ||
                            (leftUpperArmLength.isReliable && leftForearmLength.isReliable)
        // Lowered confidence threshold from 0.55 -> 0.35 to tolerate moderate detections
        score.isSuitableForROM = score.shoulderAvailable && (score.elbowAvailable || score.wristAvailable || canInferElbow) && score.overallConfidence > 0.35
        
        print("🎯 [POSE-QUALITY] Suitable for ROM: \(score.isSuitableForROM) | Confidence: \(String(format: "%.2f", score.overallConfidence))")
        
        return score
    }
}
