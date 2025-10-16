import Foundation

/// Feeds pose data into the SPARC calculation pipeline for camera-based exercises.
final class CameraSmoothnessAnalyzer {
    private let sparcService: SPARCCalculationService

    init(sparcService: SPARCCalculationService) {
        self.sparcService = sparcService
    }

    func processPose(_ keypoints: SimplifiedPoseKeypoints, timestamp: TimeInterval) {
        let activeSide = keypoints.phoneArm
        if let wrist = (activeSide == .left) ? keypoints.leftWrist : keypoints.rightWrist {
            let wristPos = SIMD3<Float>(Float(wrist.x), Float(wrist.y), 0)
            sparcService.addCameraMovement(position: wristPos, timestamp: timestamp)
            return
        }

        if let left = keypoints.leftWrist {
            let leftPos = SIMD3<Float>(Float(left.x), Float(left.y), 0)
            sparcService.addCameraMovement(position: leftPos, timestamp: timestamp)
        } else if let right = keypoints.rightWrist {
            let rightPos = SIMD3<Float>(Float(right.x), Float(right.y), 0)
            sparcService.addCameraMovement(position: rightPos, timestamp: timestamp)
        }
    }
}
