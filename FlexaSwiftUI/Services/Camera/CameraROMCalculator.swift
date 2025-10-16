import CoreGraphics

/// Calculates camera-based range of motion (ROM) metrics from pose keypoints.
final class CameraROMCalculator {
    func calculateROM(from keypoints: SimplifiedPoseKeypoints, jointPreference: CameraJointPreference) -> Double {
        let activeSide = keypoints.phoneArm
        let (shoulder, elbow, wrist) = activeSide == .left
            ? (keypoints.leftShoulder, keypoints.leftElbow, keypoints.leftWrist)
            : (keypoints.rightShoulder, keypoints.rightElbow, keypoints.rightWrist)

        if jointPreference == .elbow, let shoulder, let elbow, let wrist {
            return calculateElbowFlexionAngle(shoulder: shoulder, elbow: elbow, wrist: wrist)
        }

        if let shoulder, let elbow {
            return calculateArmAngle(shoulder: shoulder, elbow: elbow)
        }

        // Fallback to alternate side if active arm landmarks are unavailable
        if let leftShoulder = keypoints.leftShoulder, let leftElbow = keypoints.leftElbow {
            if jointPreference == .elbow, let leftWrist = keypoints.leftWrist {
                return calculateElbowFlexionAngle(shoulder: leftShoulder, elbow: leftElbow, wrist: leftWrist)
            }
            return calculateArmAngle(shoulder: leftShoulder, elbow: leftElbow)
        }

        if let rightShoulder = keypoints.rightShoulder, let rightElbow = keypoints.rightElbow {
            if jointPreference == .elbow, let rightWrist = keypoints.rightWrist {
                return calculateElbowFlexionAngle(shoulder: rightShoulder, elbow: rightElbow, wrist: rightWrist)
            }
            return calculateArmAngle(shoulder: rightShoulder, elbow: rightElbow)
        }

        return 0.0
    }

    private func calculateArmAngle(shoulder: CGPoint, elbow: CGPoint) -> Double {
        let deltaY = shoulder.y - elbow.y
        let deltaX = shoulder.x - elbow.x
        let angle = atan2(deltaY, deltaX) * 180.0 / .pi
        return abs(angle)
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
