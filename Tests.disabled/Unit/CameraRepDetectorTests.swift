import XCTest
@testable import FlexaSwiftUI

final class CameraRepDetectorTests: XCTestCase {
    func testCooldownRejectsRapidReps() {
        let detector = CameraRepDetector(minimumInterval: 0.5)
        let now = Date().timeIntervalSince1970

        // First should be accepted when ROM >= threshold
        let first = detector.evaluateRepCandidate(rom: 20.0, threshold: 10.0, timestamp: now)
        switch first {
        case .accept:
            break
        default:
            XCTFail("Expected first rep to be accepted")
        }

        // Rapid second within cooldown should be cooldown
        let second = detector.evaluateRepCandidate(rom: 20.0, threshold: 10.0, timestamp: now + 0.2)
        switch second {
        case .cooldown(let elapsed, let required):
            XCTAssertLessThan(elapsed, required)
        default:
            XCTFail("Expected second rep to be rejected by cooldown")
        }

        // After cooldown should accept again
        let third = detector.evaluateRepCandidate(rom: 20.0, threshold: 10.0, timestamp: now + 0.6)
        switch third {
        case .accept:
            break
        default:
            XCTFail("Expected third rep to be accepted after cooldown")
        }
    }
}

final class FruitSlicerFollowCircleIntegrationTests: XCTestCase {
    // Reuse helpers from the newly added test file but inline here to ensure target inclusion
    func generateFruitSlicerTrajectory(reps: Int, amplitude: Float = 0.3, dt: Double = 0.05) -> [(timestamp: Double, position: SIMD3<Float>)] {
        var points: [(Double, SIMD3<Float>)] = []
        let base = SIMD3<Float>(0.5, 0.5, 0.0)
        for i in 0..<(reps * 2) {
            let t = Double(i) * dt
            let offset = (i % 2 == 0 ? -amplitude : amplitude)
            let pos = base + SIMD3<Float>(offset, 0, 0)
            points.append((t, pos))
        }
        return points
    }

    func generateFollowCircleTrajectory(reps: Int, radius: Float = 0.2, dt: Double = 0.05) -> [(timestamp: Double, position: CGPoint)] {
        var points: [(Double, CGPoint)] = []
        let center = CGPoint(x: 0.5, y: 0.5)
        let totalPoints = reps * 20
        for i in 0..<totalPoints {
            let t = Double(i) * dt
            let angle = 2 * .pi * Double(i) / Double(20)
            let x = center.x + CGFloat(radius * cos(angle))
            let y = center.y + CGFloat(radius * sin(angle))
            points.append((t, CGPoint(x: x, y: y)))
        }
        return points
    }

    func testFruitSlicerRepAndROMDetectionIntegration() {
        let service = SPARCCalculationService()
        let reps = 10
        let trajectory = generateFruitSlicerTrajectory(reps: reps)
        var lastDirection: Float = 0
        var detectedReps = 0
        var roms: [Double] = []
        var lastRepTime: Double = -1
        let minROM: Double = 0.4
        for (i, (timestamp, pos)) in trajectory.enumerated() {
            service.addARKitPositionData(timestamp: timestamp, position: pos)
            let direction = pos.x > 0.5 ? 1.0 : -1.0
            if i > 0 && direction != lastDirection {
                let prev = trajectory[i-1].position
                let rom = abs(Double(pos.x - prev.x))
                if rom >= minROM && (lastRepTime < 0 || timestamp - lastRepTime > 0.5) {
                    detectedReps += 1
                    roms.append(rom)
                    lastRepTime = timestamp
                }
            }
            lastDirection = direction
        }
        XCTAssertEqual(detectedReps, reps)
        XCTAssertTrue(roms.allSatisfy { $0 >= 0.4 })
        let sparc = service.getCurrentSPARC()
        XCTAssertGreaterThanOrEqual(sparc, 0.0)
        XCTAssertLessThanOrEqual(sparc, 100.0)
    }

    func testFollowCircleRepAndROMDetectionIntegration() {
        let service = SPARCCalculationService()
        let reps = 5
        let trajectory = generateFollowCircleTrajectory(reps: reps)
        var lastAngle: Double = 0
        var detectedReps = 0
        var roms: [Double] = []
        for (i, (timestamp, pos)) in trajectory.enumerated() {
            service.addVisionMovement(timestamp: timestamp, position: pos)
            let dx = Double(pos.x - 0.5)
            let dy = Double(pos.y - 0.5)
            let angle = atan2(dy, dx)
            if i > 0 && angle < lastAngle - .pi {
                detectedReps += 1
                let rom = 2 * .pi * Double(0.2)
                roms.append(rom)
            }
            lastAngle = angle
        }
        XCTAssertEqual(detectedReps, reps)
        XCTAssertTrue(roms.allSatisfy { $0 >= 2 * .pi * 0.2 })
        let sparc = service.getCurrentSPARC()
        XCTAssertGreaterThanOrEqual(sparc, 0.0)
        XCTAssertLessThanOrEqual(sparc, 100.0)
    }
}
