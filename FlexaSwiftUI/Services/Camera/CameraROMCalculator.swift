import CoreGraphics

/// Calculates camera-based range of motion (ROM) metrics from pose keypoints.
final class CameraROMCalculator {
    func calculateROM(from keypoints: SimplifiedPoseKeypoints, jointPreference: CameraJointPreference, flipY: Bool = false) -> Double {
    let kpts = flippedY(keypoints) // Always flip Y for correct mapping
    let activeSide = kpts.phoneArm
        FlexaLog.vision.debug("📐 [ROM-CALC] Active arm: \(activeSide == .left ? "LEFT" : "RIGHT"), Joint: \(jointPreference == .elbow ? "ELBOW" : "ARMPIT")")
        
        let (shoulder, elbow, wrist, hip) = activeSide == .left
            ? (kpts.leftShoulder, kpts.leftElbow, kpts.leftWrist, kpts.leftHip)
            : (kpts.rightShoulder, kpts.rightElbow, kpts.rightWrist, kpts.rightHip)

        if let s = shoulder, let e = elbow {
            FlexaLog.vision.debug("📐 [ROM-CALC] Shoulder: (\(String(format: "%.1f", s.x)), \(String(format: "%.1f", s.y))), Elbow: (\(String(format: "%.1f", e.x)), \(String(format: "%.1f", e.y)))")
        }

        // Elbow preference: 3-point flexion at elbow
        if jointPreference == .elbow, let shoulder, let elbow, let wrist {
            let angle = calculateElbowFlexionAngle(shoulder: shoulder, elbow: elbow, wrist: wrist)
            FlexaLog.vision.debug("📐 [ROM-CALC] Elbow flexion angle: \(String(format: "%.1f", angle))°")
            return angle
        }

        // Armpit/shoulder preference: 3-point armpit angle (shoulder-hip vs shoulder-elbow)
        if let shoulder, let elbow, let hip {
            let angle = calculateArmpitAngle(shoulder: shoulder, hip: hip, elbow: elbow)
            FlexaLog.vision.debug("📐 [ROM-CALC] Armpit angle (shoulder–hip vs shoulder–elbow): \(String(format: "%.1f", angle))°")
            return angle
        }

        // Fallbacks if hip missing
        if let shoulder, let elbow {
            let angle = calculateArmAngle(shoulder: shoulder, elbow: elbow)
            FlexaLog.vision.debug("📐 [ROM-CALC] Arm angle from vertical (fallback): \(String(format: "%.1f", angle))°")
            return angle
        }

        // Fallback to alternate side if active landmarks unavailable
    if let leftShoulder = kpts.leftShoulder, let leftElbow = kpts.leftElbow {
            if jointPreference == .elbow, let leftWrist = keypoints.leftWrist {
                return calculateElbowFlexionAngle(shoulder: leftShoulder, elbow: leftElbow, wrist: leftWrist)
            }
            if let leftHip = keypoints.leftHip {
                return calculateArmpitAngle(shoulder: leftShoulder, hip: leftHip, elbow: leftElbow)
            }
            return calculateArmAngle(shoulder: leftShoulder, elbow: leftElbow)
        }

    if let rightShoulder = kpts.rightShoulder, let rightElbow = kpts.rightElbow {
            if jointPreference == .elbow, let rightWrist = keypoints.rightWrist {
                return calculateElbowFlexionAngle(shoulder: rightShoulder, elbow: rightElbow, wrist: rightWrist)
            }
            if let rightHip = keypoints.rightHip {
                return calculateArmpitAngle(shoulder: rightShoulder, hip: rightHip, elbow: rightElbow)
            }
            return calculateArmAngle(shoulder: rightShoulder, elbow: rightElbow)
        }

        return 0.0
    }

    private func flippedY(_ kp: SimplifiedPoseKeypoints) -> SimplifiedPoseKeypoints {
        func flip(_ p: CGPoint?) -> CGPoint? { p.map { CGPoint(x: $0.x, y: 1.0 - $0.y) } }

        return SimplifiedPoseKeypoints(
            timestamp: kp.timestamp,
            leftWrist: flip(kp.leftWrist),
            rightWrist: flip(kp.rightWrist),
            leftElbow: flip(kp.leftElbow),
            rightElbow: flip(kp.rightElbow),
            leftShoulder: flip(kp.leftShoulder),
            rightShoulder: flip(kp.rightShoulder),
            nose: flip(kp.nose),
            neck: flip(kp.neck),
            leftHip: flip(kp.leftHip),
            rightHip: flip(kp.rightHip),
            leftEye: flip(kp.leftEye),
            rightEye: flip(kp.rightEye),
            leftShoulder3D: kp.leftShoulder3D,
            rightShoulder3D: kp.rightShoulder3D,
            leftElbow3D: kp.leftElbow3D,
            rightElbow3D: kp.rightElbow3D,
            leftShoulderConfidence: kp.leftShoulderConfidence,
            rightShoulderConfidence: kp.rightShoulderConfidence,
            leftElbowConfidence: kp.leftElbowConfidence,
            rightElbowConfidence: kp.rightElbowConfidence,
            leftWristConfidence: kp.leftWristConfidence,
            rightWristConfidence: kp.rightWristConfidence,
            noseConfidence: kp.noseConfidence,
            neckConfidence: kp.neckConfidence
        )
    }

    private func calculateArmAngle(shoulder: CGPoint, elbow: CGPoint) -> Double {
        // Calculate vector from shoulder to elbow (upper arm)
        let armVector = CGVector(dx: elbow.x - shoulder.x, dy: elbow.y - shoulder.y)
        
        // Screen Y-axis points downward (vertical reference)
        let verticalReference = CGVector(dx: 0, dy: 1)
        
        // Calculate arm vector length
        let armLength = max(1e-6, hypot(armVector.dx, armVector.dy))
        
        // Calculate dot product and angle from vertical
        let dot = armVector.dx * verticalReference.dx + armVector.dy * verticalReference.dy
        let cosAngle = dot / armLength
        let clamped = max(-1.0, min(1.0, cosAngle))
        let radians = acos(clamped)
        let degrees = radians * 180.0 / .pi
        
        // Return absolute angle in degrees
        return abs(degrees)
    }

    private func calculateArmpitAngle(shoulder: CGPoint, hip: CGPoint, elbow: CGPoint) -> Double {
        // Vector along torso (shoulder -> hip)
        let torso = CGVector(dx: hip.x - shoulder.x, dy: hip.y - shoulder.y)
        // Vector along upper arm (shoulder -> elbow)
        let arm = CGVector(dx: elbow.x - shoulder.x, dy: elbow.y - shoulder.y)
        let torsoLen = max(1e-6, hypot(torso.dx, torso.dy))
        let armLen = max(1e-6, hypot(arm.dx, arm.dy))
        let dot = (torso.dx * arm.dx + torso.dy * arm.dy) / (torsoLen * armLen)
        let clamped = max(-1.0, min(1.0, dot))
        let radians = acos(clamped)
        let degrees = radians * 180.0 / .pi
        return max(0.0, min(180.0, degrees))
    }

    private func calculateElbowFlexionAngle(shoulder: CGPoint, elbow: CGPoint, wrist: CGPoint) -> Double {
        let upper = CGVector(dx: shoulder.x - elbow.x, dy: shoulder.y - elbow.y)
        let forearm = CGVector(dx: wrist.x - elbow.x, dy: wrist.y - elbow.y)
        let upperLength = max(1e-6, hypot(upper.dx, upper.dy))
        let forearmLength = max(1e-6, hypot(forearm.dx, forearm.dy))
        let dot = (upper.dx * forearm.dx + upper.dy * forearm.dy) / (upperLength * forearmLength)
        let clamped = max(-1.0, min(1.0, dot))
        let radians = acos(clamped)
        let degrees = radians * 180.0 / .pi
        return max(0.0, min(180.0, degrees))
    }
}
