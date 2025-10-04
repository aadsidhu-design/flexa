import SwiftUI
import AVFoundation
import CoreMotion
import Combine
import simd

// MARK: - Simplified PoseKeypoints Structure (No Complex Estimation)
struct SimplifiedPoseKeypoints {
    let timestamp: TimeInterval
    
    // Only store directly detected 2D landmarks - no estimation chains
    let leftWrist: CGPoint?
    let rightWrist: CGPoint?
    let leftElbow: CGPoint?
    let rightElbow: CGPoint?
    let leftShoulder: CGPoint?
    let rightShoulder: CGPoint?
    let nose: CGPoint?
    let neck: CGPoint?
    
    // Additional landmarks only if directly detected
    let leftHip: CGPoint?
    let rightHip: CGPoint?
    let leftEye: CGPoint?
    let rightEye: CGPoint?
    
    // 3D landmarks (if available from an optional Core ML 3D model)
    let leftShoulder3D: simd_float3?
    let rightShoulder3D: simd_float3?
    let leftElbow3D: simd_float3?
    let rightElbow3D: simd_float3?
    
    // Confidence scores for quality assessment
    let leftShoulderConfidence: Float
    let rightShoulderConfidence: Float
    let leftElbowConfidence: Float
    let rightElbowConfidence: Float
    let neckConfidence: Float
    
    // Phone arm detection based on pose asymmetry
    var phoneArm: BodySide {
        return detectPhoneArm()
    }
    
    func getBestElbowROM() -> Double? {
        let side = phoneArm
        return elbowFlexionAngle(side: side)
    }

    func getLeftElbowAngle() -> Double? {
        // Convert raw angle to degrees scaled 0-180
        if let angle = elbowFlexionAngle(side: .left) {
            // Normalize raw angle to 0-180 range
            let normalized = max(0, min(180, (180 - angle)))
            return normalized
        }
        return nil
    }
    
    func getRightElbowAngle() -> Double? {
        // Convert raw angle to degrees scaled 0-180
        if let angle = elbowFlexionAngle(side: .right) {
            // Normalize raw angle to 0-180 range 
            let normalized = max(0, min(180, (180 - angle)))
            return normalized
        }
        return nil
    }
    
    // MARK: - Simplified ROM Calculation (Shoulder Abduction)
    func getArmpitROM(side: BodySide) -> Double {
        // Calculate shoulder abduction (armpit ROM) using shoulder-elbow-hip angle
        return calculateShoulderAbduction(side: side) ?? 0.0
    }
    
    // MARK: - Elbow Flexion/Extension Angle (Upper arm vs forearm)
    func elbowFlexionAngle(side: BodySide) -> Double? {
        let shoulder = (side == .left) ? leftShoulder : rightShoulder
        let elbow    = (side == .left) ? leftElbow     : rightElbow
        let wrist    = (side == .left) ? leftWrist     : rightWrist
        guard let s = shoulder, let e = elbow, let w = wrist else { return nil }
        let upper = CGPoint(x: e.x - s.x, y: e.y - s.y)
        let fore  = CGPoint(x: w.x - e.x, y: w.y - e.y)
        return calculateAngleBetweenVectors(upper, fore)
    }
    
    func calculateShoulderAbduction(side: BodySide) -> Double? {
        let (shoulder, elbow, hip) = side == .left ? 
            (leftShoulder, leftElbow, leftHip) : 
            (rightShoulder, rightElbow, rightHip)
        
        guard let shoulder = shoulder, let elbow = elbow else {
            return nil
        }
        
        // Vector from shoulder to elbow (upper arm)
        let upperArm = CGPoint(x: elbow.x - shoulder.x, y: elbow.y - shoulder.y)
        
        // Primary method: Use hip if available (full body visible)
        if let hip = hip {
            let torso = CGPoint(x: hip.x - shoulder.x, y: hip.y - shoulder.y)
            return calculateAngleBetweenVectors(upperArm, torso)
        }
        
        // Fallback 1: Use opposite shoulder as torso reference (sitting/upper body only)
        let oppositeShoulder = side == .left ? rightShoulder : leftShoulder
        if let oppositeShoulder = oppositeShoulder {
            // Create vertical reference from shoulder line
            let shoulderLine = CGPoint(x: oppositeShoulder.x - shoulder.x, y: oppositeShoulder.y - shoulder.y)
            let verticalReference = CGPoint(x: -shoulderLine.y, y: shoulderLine.x) // Perpendicular = torso
            return calculateAngleBetweenVectors(upperArm, verticalReference)
        }
        
        // Fallback 2: Use screen vertical as reference (minimal landmarks)
        let screenVertical = CGPoint(x: 0, y: 1) // Straight down
        return calculateAngleBetweenVectors(upperArm, screenVertical)
    }
    
    private func calculateAngleBetweenVectors(_ vector1: CGPoint, _ vector2: CGPoint) -> Double {
        let dot = vector1.x * vector2.x + vector1.y * vector2.y
        let mag1Sq = vector1.x * vector1.x + vector1.y * vector1.y
        let mag2Sq = vector2.x * vector2.x + vector2.y * vector2.y
        
        // Use epsilon for numerical stability
        let epsilon: CGFloat = 1e-10
        guard mag1Sq > epsilon, mag2Sq > epsilon else { return 0 }
        
        let mag1 = sqrt(mag1Sq)
        let mag2 = sqrt(mag2Sq)
        
        // Clamp cosine to valid range with higher precision
        let cosAngle = max(-1.0, min(1.0, dot / (mag1 * mag2)))
        let angleRad = acos(cosAngle)
        return angleRad * 180.0 / .pi
    }
    
    func getBestArmpitROM() -> Double? {
        let leftROM = getArmpitROM(side: .left)
        let rightROM = getArmpitROM(side: .right)
        
        // Prioritize side with better confidence and valid range.
        // Down-weight sides missing critical landmarks.
        let leftPresencePenalty: Float = (leftShoulder != nil && leftElbow != nil) ? 1.0 : 0.5
        let rightPresencePenalty: Float = (rightShoulder != nil && rightElbow != nil) ? 1.0 : 0.5
        let leftConfidence = (leftShoulderConfidence * leftElbowConfidence) * leftPresencePenalty
        let rightConfidence = (rightShoulderConfidence * rightElbowConfidence) * rightPresencePenalty
        
        // Valid ROM should be between 0-180 degrees
        let leftValid = leftROM > 0 && leftROM <= 180
        let rightValid = rightROM > 0 && rightROM <= 180
        
        if leftValid && rightValid {
            // Both valid - choose higher confidence or larger angle (more raised arm)
            if abs(leftConfidence - rightConfidence) > 0.1 {
                return leftConfidence > rightConfidence ? leftROM : rightROM
            } else {
                return max(leftROM, rightROM) // Higher angle = more raised arm
            }
        } else if leftValid {
            return leftROM
        } else if rightValid {
            return rightROM
        }
        
        return nil
    }
    
    func getPhoneArmROM() -> Double? {
        return getArmpitROM(side: phoneArm)
    }
    
    // MARK: - Simplified Helper Methods
    private func getLandmarksForSide(_ side: BodySide) -> (shoulder: CGPoint?, elbow: CGPoint?, confidence: Float) {
        switch side {
        case .left:
            return (leftShoulder, leftElbow, leftElbowConfidence)
        case .right:
            return (rightShoulder, rightElbow, rightElbowConfidence)
        }
    }
    
    private func calculateTorsoVertical(leftShoulder: CGPoint, rightShoulder: CGPoint) -> CGPoint {
        // Calculate shoulder-to-shoulder vector
        let shoulderVector = CGPoint(
            x: rightShoulder.x - leftShoulder.x,
            y: rightShoulder.y - leftShoulder.y
        )
        
        // Calculate perpendicular vector (true vertical relative to torso)
        let shoulderLength = sqrt(shoulderVector.x * shoulderVector.x + shoulderVector.y * shoulderVector.y)
        
        if shoulderLength == 0 {
            // Fallback to screen vertical if shoulders are perfectly aligned
            return CGPoint(x: 0, y: 1)
        }
        
        // Perpendicular vector (rotated 90 degrees)
        return CGPoint(
            x: -shoulderVector.y / shoulderLength,  // Rotate 90° counterclockwise
            y: shoulderVector.x / shoulderLength
        )
    }
    
    
    private func calculateAngle(armVector: CGPoint, referenceVector: CGPoint) -> Double {
        let dot = armVector.x * referenceVector.x + armVector.y * referenceVector.y
        let armMag = sqrt(armVector.x * armVector.x + armVector.y * armVector.y)
        let refMag = sqrt(referenceVector.x * referenceVector.x + referenceVector.y * referenceVector.y)
        
        if armMag == 0 || refMag == 0 { return 0 }
        
        let cosAngle = dot / (armMag * refMag)
        let clampedCos = max(-1, min(1, cosAngle))
        let angleInRadians = acos(clampedCos)
        
        return angleInRadians * 180.0 / .pi
    }
    
    private func detectPhoneArm() -> BodySide {
        // Simple detection based on arm height and extension
        guard let leftShoulder = leftShoulder,
              let rightShoulder = rightShoulder,
              let leftElbow = leftElbow,
              let rightElbow = rightElbow else {
            return .right // Default assumption
        }
        
        // Calculate arm heights (negative Y means higher on screen)
        let leftHeight = leftShoulder.y - leftElbow.y
        let rightHeight = rightShoulder.y - rightElbow.y
        
        // Calculate arm extensions
        let leftExtension = distance2D(leftShoulder, leftElbow)
        let rightExtension = distance2D(rightShoulder, rightElbow)
        
        // Weighted scoring: height + extension
        let leftScore = leftHeight + (leftExtension * 0.5)
        let rightScore = rightHeight + (rightExtension * 0.5)
        
        return leftScore > rightScore ? .left : .right
    }
    
    private func distance2D(_ p1: CGPoint, _ p2: CGPoint) -> Double {
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        return sqrt(dx * dx + dy * dy)
    }
    
    
    // MARK: - Quality Assessment
    func getPoseQuality() -> Double {
        let criticalLandmarks = [leftShoulderConfidence, rightShoulderConfidence, leftElbowConfidence, rightElbowConfidence]
        let supportingLandmarks = [neckConfidence]
        
        let criticalAvg = criticalLandmarks.reduce(0, +) / Float(criticalLandmarks.count)
        let supportingAvg = supportingLandmarks.reduce(0, +) / Float(supportingLandmarks.count)
        
        // Weighted average: 70% critical landmarks, 30% supporting landmarks
        return Double((criticalAvg * 0.7) + (supportingAvg * 0.3))
    }
    
    func isValidForROMCalculation() -> Bool {
        // Check if we have minimum required landmarks with sufficient confidence
        let hasShoulders = leftShoulder != nil && rightShoulder != nil &&
                          leftShoulderConfidence >= 0.6 && rightShoulderConfidence >= 0.6
        let hasAtLeastOneElbow = (leftElbow != nil && leftElbowConfidence >= 0.6) ||
                               (rightElbow != nil && rightElbowConfidence >= 0.6)
        
        return hasShoulders && hasAtLeastOneElbow && getPoseQuality() >= 0.65
    }
}

// MARK: - Apple Vision Integration
// All baseline pose detection is handled by Apple Vision. Optional Core ML provider may populate 3D joints.
