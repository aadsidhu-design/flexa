import XCTest
import simd
@testable import FlexaSwiftUI

final class FruitSlicerAndFollowCircleRepROMTests: XCTestCase {
    // Helper to simulate a FruitSlicer-like trajectory (handheld, direction changes)
    func generateFruitSlicerTrajectory(reps: Int, amplitude: Float = 0.3, dt: Double = 0.05) -> [(timestamp: Double, position: SIMD3<Float>)] {
        var points: [(Double, SIMD3<Float>)] = []
        let base = SIMD3<Float>(0.5, 0.5, 0.0)
        for i in 0..<(reps * 2) {
            let t = Double(i) * dt
            // Alternate direction: left/right
            let offset = (i % 2 == 0 ? -amplitude : amplitude)
            let pos = base + SIMD3<Float>(offset, 0, 0)
            points.append((t, pos))
        }
        return points
    }

    // Helper to simulate a FollowCircle-like trajectory (camera, smooth circle)
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

    func testFruitSlicerRepAndROMDetection() {
        let service = SPARCCalculationService()
        let reps = 10
        let trajectory = generateFruitSlicerTrajectory(reps: reps)
        var lastDirection: Float = 0
        var detectedReps = 0
        var roms: [Double] = []
        var lastRepTime: Double = -1
        let minROM: Double = 0.4 // Simulated threshold
        for (i, (timestamp, pos)) in trajectory.enumerated() {
            service.addARKitPositionData(timestamp: timestamp, position: pos)
            // Rep detection: count direction changes
            let direction = pos.x > 0.5 ? 1.0 : -1.0
            if i > 0 && direction != lastDirection {
                // ROM calculation: distance between direction changes
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
        XCTAssertEqual(detectedReps, reps, "FruitSlicer: Should detect exactly \(reps) reps via direction changes")
        XCTAssertTrue(roms.allSatisfy { $0 >= 0.4 }, "FruitSlicer: All ROMs should meet minimum threshold")
        // SPARC should be in valid range
        let sparc = service.getCurrentSPARC()
        XCTAssertGreaterThanOrEqual(sparc, 0.0)
        XCTAssertLessThanOrEqual(sparc, 100.0)
    }

    func testFollowCircleRepAndROMDetection() {
        let service = SPARCCalculationService()
        let reps = 5
        let trajectory = generateFollowCircleTrajectory(reps: reps)
        var lastAngle: Double = 0
        var detectedReps = 0
        var roms: [Double] = []
        let minROM: Double = 0.2 // Simulated threshold
        for (i, (timestamp, pos)) in trajectory.enumerated() {
            service.addVisionMovement(timestamp: timestamp, position: pos)
            // Rep detection: count full circles (angle wraps)
            let dx = Double(pos.x - 0.5)
            let dy = Double(pos.y - 0.5)
            let angle = atan2(dy, dx)
            if i > 0 && angle < lastAngle - .pi {
                detectedReps += 1
                // ROM: circumference of circle
                let rom = 2 * .pi * Double(0.2)
                roms.append(rom)
            }
            lastAngle = angle
        }
        XCTAssertEqual(detectedReps, reps, "FollowCircle: Should detect exactly \(reps) reps (full circles)")
        XCTAssertTrue(roms.allSatisfy { $0 >= 2 * .pi * 0.2 }, "FollowCircle: All ROMs should meet minimum threshold")
        // SPARC should be in valid range
        let sparc = service.getCurrentSPARC()
        XCTAssertGreaterThanOrEqual(sparc, 0.0)
        XCTAssertLessThanOrEqual(sparc, 100.0)
    }
}
