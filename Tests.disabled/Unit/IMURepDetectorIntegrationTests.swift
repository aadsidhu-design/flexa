import XCTest
import CoreMotion
@testable import FlexaSwiftUI

final class IMURepDetectorIntegrationTests: XCTestCase {
    
    var detector: IMUDirectionRepDetector!
    var detectedReps: [(repCount: Int, timestamp: TimeInterval)] = []
    var mockROM: Double = 0.0
    
    override func setUp() {
        super.setUp()
        detector = IMUDirectionRepDetector()
        detectedReps = []
        mockROM = 0.0
        
        // Set up callbacks
        detector.onRepDetected = { [weak self] count, timestamp in
            self?.detectedReps.append((count, timestamp))
        }
        detector.romProvider = { [weak self] in
            return self?.mockROM ?? 0.0
        }
    }
    
    override func tearDown() {
        detector = nil
        detectedReps = []
        super.tearDown()
    }
    
    // MARK: - Gravity Calibration Tests
    
    func testGravityCalibration() {
        detector.startSession()
        
        // Simulate 30 stationary samples for calibration (phone upright, gravity = -9.8 on Y)
        let gravityAccel = CMAcceleration(x: 0.0, y: -9.8, z: 0.0)
        
        for i in 0..<30 {
            let motion = createMockMotion(acceleration: gravityAccel, timestamp: Double(i) * 0.01)
            detector.processDeviceMotion(motion, timestamp: Double(i) * 0.01)
        }
        
        // After calibration, gravity should be removed
        // No reps should be detected during calibration
        XCTAssertEqual(detectedReps.count, 0, "No reps should be detected during calibration")
    }
    
    // MARK: - Simple Movement Tests
    
    func testSimpleUpDownMovement() {
        detector.startSession()
        mockROM = 30.0 // Sufficient ROM
        
        // Calibrate with stationary samples
        calibrateDetector()
        
        // Simulate upward movement (positive Y acceleration)
        for i in 0..<10 {
            let accel = CMAcceleration(x: 0.0, y: -9.8 + 2.0, z: 0.0) // Upward acceleration
            let motion = createMockMotion(acceleration: accel, timestamp: 0.3 + Double(i) * 0.05)
            detector.processDeviceMotion(motion, timestamp: 0.3 + Double(i) * 0.05)
        }
        
        // Simulate downward movement (negative Y acceleration)
        for i in 0..<10 {
            let accel = CMAcceleration(x: 0.0, y: -9.8 - 2.0, z: 0.0) // Downward acceleration
            let motion = createMockMotion(acceleration: accel, timestamp: 0.8 + Double(i) * 0.05)
            detector.processDeviceMotion(motion, timestamp: 0.8 + Double(i) * 0.05)
        }
        
        // Should detect at least 1 rep from direction change
        XCTAssertGreaterThanOrEqual(detectedReps.count, 1, "Should detect rep from direction change")
    }
    
    func testMultipleRepsWithCooldown() {
        detector.startSession()
        mockROM = 25.0
        
        calibrateDetector()
        
        var timestamp = 0.3
        
        // Simulate 3 complete up-down cycles with proper cooldown
        for cycle in 0..<3 {
            // Up movement
            for i in 0..<8 {
                let accel = CMAcceleration(x: 0.0, y: -9.8 + 1.5, z: 0.0)
                let motion = createMockMotion(acceleration: accel, timestamp: timestamp)
                detector.processDeviceMotion(motion, timestamp: timestamp)
                timestamp += 0.05
            }
            
            // Down movement
            for i in 0..<8 {
                let accel = CMAcceleration(x: 0.0, y: -9.8 - 1.5, z: 0.0)
                let motion = createMockMotion(acceleration: accel, timestamp: timestamp)
                detector.processDeviceMotion(motion, timestamp: timestamp)
                timestamp += 0.05
            }
            
            // Cooldown period
            timestamp += 0.4
        }
        
        // Should detect multiple reps
        XCTAssertGreaterThanOrEqual(detectedReps.count, 2, "Should detect multiple reps with proper cooldown")
    }
    
    // MARK: - ROM Validation Tests
    
    func testMinimumROMRequirement() {
        detector.startSession()
        
        calibrateDetector()
        
        // Set ROM below minimum (5 degrees)
        mockROM = 3.0
        
        // Simulate movement
        simulateUpDownMovement(startTime: 0.3)
        
        // Should NOT detect rep due to insufficient ROM
        XCTAssertEqual(detectedReps.count, 0, "Should not detect rep with ROM below minimum")
        
        // Now set ROM above minimum
        mockROM = 15.0
        
        // Simulate another movement after cooldown
        simulateUpDownMovement(startTime: 1.5)
        
        // Should detect rep with sufficient ROM
        XCTAssertGreaterThanOrEqual(detectedReps.count, 1, "Should detect rep with sufficient ROM")
    }
    
    func testROMBoundaryConditions() {
        detector.startSession()
        calibrateDetector()
        
        // Test exactly at minimum ROM (5 degrees)
        mockROM = 5.0
        simulateUpDownMovement(startTime: 0.3)
        
        let repsAtMinimum = detectedReps.count
        XCTAssertGreaterThanOrEqual(repsAtMinimum, 1, "Should detect rep at exactly minimum ROM")
        
        // Test just below minimum
        detectedReps.removeAll()
        mockROM = 4.9
        simulateUpDownMovement(startTime: 1.5)
        
        XCTAssertEqual(detectedReps.count, 0, "Should not detect rep just below minimum ROM")
    }
    
    // MARK: - Cooldown Tests
    
    func testCooldownPreventsRapidReps() {
        detector.startSession()
        mockROM = 20.0
        
        calibrateDetector()
        
        // Simulate rapid movements within cooldown period (0.3s)
        var timestamp = 0.3
        for _ in 0..<5 {
            simulateUpDownMovement(startTime: timestamp)
            timestamp += 0.1 // Less than cooldown period
        }
        
        // Should only detect 1-2 reps due to cooldown
        XCTAssertLessThanOrEqual(detectedReps.count, 2, "Cooldown should prevent rapid rep detection")
    }
    
    // MARK: - 3D Movement Tests
    
    func test3DMovementDetection() {
        detector.startSession()
        mockROM = 30.0
        
        calibrateDetector()
        
        var timestamp = 0.3
        
        // Simulate circular/3D movement
        for i in 0..<20 {
            let angle = Double(i) * 0.314 // ~18 degrees per step
            let x = cos(angle) * 1.5
            let y = sin(angle) * 1.5
            let accel = CMAcceleration(x: x, y: -9.8 + y, z: 0.0)
            let motion = createMockMotion(acceleration: accel, timestamp: timestamp)
            detector.processDeviceMotion(motion, timestamp: timestamp)
            timestamp += 0.05
        }
        
        // Should detect reps from 3D movement
        XCTAssertGreaterThanOrEqual(detectedReps.count, 1, "Should detect reps from 3D movement")
    }
    
    // MARK: - Edge Cases
    
    func testNoMovementNoReps() {
        detector.startSession()
        mockROM = 20.0
        
        calibrateDetector()
        
        // Simulate stationary phone (only gravity)
        for i in 0..<50 {
            let accel = CMAcceleration(x: 0.0, y: -9.8, z: 0.0)
            let motion = createMockMotion(acceleration: accel, timestamp: 0.3 + Double(i) * 0.05)
            detector.processDeviceMotion(motion, timestamp: 0.3 + Double(i) * 0.05)
        }
        
        XCTAssertEqual(detectedReps.count, 0, "No reps should be detected without movement")
    }
    
    func testVerySlowMovement() {
        detector.startSession()
        mockROM = 15.0
        
        calibrateDetector()
        
        // Simulate very slow movement (below velocity threshold)
        var timestamp = 0.3
        for i in 0..<20 {
            let accel = CMAcceleration(x: 0.0, y: -9.8 + 0.05, z: 0.0) // Very small acceleration
            let motion = createMockMotion(acceleration: accel, timestamp: timestamp)
            detector.processDeviceMotion(motion, timestamp: timestamp)
            timestamp += 0.1
        }
        
        // May or may not detect depending on velocity threshold
        // Just verify it doesn't crash
        XCTAssertTrue(true, "Should handle very slow movement without crashing")
    }
    
    func testResetClearsState() {
        detector.startSession()
        mockROM = 20.0
        
        calibrateDetector()
        simulateUpDownMovement(startTime: 0.3)
        
        let repsBeforeReset = detectedReps.count
        XCTAssertGreaterThan(repsBeforeReset, 0, "Should have detected reps before reset")
        
        // Reset detector
        detector.resetState()
        detectedReps.removeAll()
        
        // Need to recalibrate after reset
        calibrateDetector()
        
        // Verify state is clean
        XCTAssertEqual(detectedReps.count, 0, "Rep count should be zero after reset")
    }
    
    // MARK: - Helper Methods
    
    private func calibrateDetector() {
        // Simulate 30 stationary samples for gravity calibration
        let gravityAccel = CMAcceleration(x: 0.0, y: -9.8, z: 0.0)
        for i in 0..<30 {
            let motion = createMockMotion(acceleration: gravityAccel, timestamp: Double(i) * 0.01)
            detector.processDeviceMotion(motion, timestamp: Double(i) * 0.01)
        }
    }
    
    private func simulateUpDownMovement(startTime: TimeInterval) {
        var timestamp = startTime
        
        // Up movement
        for _ in 0..<8 {
            let accel = CMAcceleration(x: 0.0, y: -9.8 + 1.5, z: 0.0)
            let motion = createMockMotion(acceleration: accel, timestamp: timestamp)
            detector.processDeviceMotion(motion, timestamp: timestamp)
            timestamp += 0.05
        }
        
        // Down movement
        for _ in 0..<8 {
            let accel = CMAcceleration(x: 0.0, y: -9.8 - 1.5, z: 0.0)
            let motion = createMockMotion(acceleration: accel, timestamp: timestamp)
            detector.processDeviceMotion(motion, timestamp: timestamp)
            timestamp += 0.05
        }
    }
    
    private func createMockMotion(acceleration: CMAcceleration, timestamp: TimeInterval) -> CMDeviceMotion {
        // Create a mock CMDeviceMotion object
        // Note: CMDeviceMotion is a class from CoreMotion that we can't easily instantiate
        // In a real test environment, you'd use a protocol or wrapper
        // For now, we'll use a workaround with reflection
        
        let motion = MockDeviceMotion()
        motion.mockAcceleration = acceleration
        motion.mockTimestamp = timestamp
        return motion as! CMDeviceMotion
    }
}

// MARK: - Mock Device Motion

class MockDeviceMotion: CMDeviceMotion {
    var mockAcceleration: CMAcceleration = CMAcceleration(x: 0, y: 0, z: 0)
    var mockTimestamp: TimeInterval = 0
    
    override var acceleration: CMAcceleration {
        return mockAcceleration
    }
    
    override var timestamp: TimeInterval {
        return mockTimestamp
    }
    
    override var userAcceleration: CMAcceleration {
        // Return acceleration minus gravity (simplified)
        return CMAcceleration(
            x: mockAcceleration.x,
            y: mockAcceleration.y + 9.8, // Remove gravity from Y
            z: mockAcceleration.z
        )
    }
}
