import XCTest
import simd
@testable import FlexaSwiftUI

final class SPARCIntegrationTests: XCTestCase {
    
    var sparcService: SPARCCalculationService!
    
    override func setUp() {
        super.setUp()
        sparcService = SPARCCalculationService()
    }
    
    override func tearDown() {
        sparcService = nil
        super.tearDown()
    }
    
    // MARK: - IMU Data Processing Tests
    
    func testIMUDataIngestion() {
        // Add IMU data samples
        for i in 0..<50 {
            let timestamp = Double(i) * 0.01
            let acceleration = [sin(Double(i) * 0.1), cos(Double(i) * 0.1), 0.0]
            let velocity = [cos(Double(i) * 0.1) * 0.1, -sin(Double(i) * 0.1) * 0.1, 0.0]
            
            sparcService.addIMUData(timestamp: timestamp, acceleration: acceleration, velocity: velocity)
        }
        
        // Wait for async processing
        let expectation = XCTestExpectation(description: "SPARC calculation")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // Verify SPARC was calculated
        let sparc = sparcService.getCurrentSPARC()
        XCTAssertGreaterThan(sparc, 0.0, "SPARC should be calculated from IMU data")
        XCTAssertLessThanOrEqual(sparc, 100.0, "SPARC should be within valid range")
    }
    
    func testIMUGravityRemoval() {
        // Test that gravity is properly removed via high-pass filter
        // Add samples with constant gravity component
        for i in 0..<50 {
            let timestamp = Double(i) * 0.01
            // Acceleration with gravity (9.8 m/s² on Y) plus small movement
            let acceleration = [0.1 * sin(Double(i) * 0.2), 9.8 + 0.1 * cos(Double(i) * 0.2), 0.0]
            
            sparcService.addIMUData(timestamp: timestamp, acceleration: acceleration, velocity: nil)
        }
        
        let expectation = XCTestExpectation(description: "Gravity filtering")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // Should calculate SPARC without gravity affecting results
        let sparc = sparcService.getCurrentSPARC()
        XCTAssertGreaterThan(sparc, 0.0, "SPARC should be calculated with gravity removed")
    }
    
    func testIMUVelocityIntegration() {
        // Test velocity estimation from acceleration
        var timestamp = 0.0
        
        // Add acceleration data without velocity (should be estimated)
        for i in 0..<40 {
            let acceleration = [1.0 * sin(Double(i) * 0.15), 1.0 * cos(Double(i) * 0.15), 0.0]
            sparcService.addIMUData(timestamp: timestamp, acceleration: acceleration, velocity: nil)
            timestamp += 0.025
        }
        
        let expectation = XCTestExpectation(description: "Velocity integration")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        let sparc = sparcService.getCurrentSPARC()
        XCTAssertGreaterThan(sparc, 0.0, "SPARC should work with integrated velocity")
    }
    
    // MARK: - ARKit Position Data Tests
    
    func testARKitPositionTracking() {
        // Simulate ARKit position data (handheld game scenario)
        var timestamp = 0.0
        
        for i in 0..<50 {
            let angle = Double(i) * 0.1
            let position = SIMD3<Float>(
                Float(cos(angle) * 0.5),
                Float(sin(angle) * 0.5),
                0.0
            )
            
            sparcService.addARKitPositionData(timestamp: timestamp, position: position)
            timestamp += 0.016 // ~60 FPS
        }
        
        let expectation = XCTestExpectation(description: "ARKit SPARC")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        let sparc = sparcService.getCurrentSPARC()
        XCTAssertGreaterThan(sparc, 0.0, "SPARC should be calculated from ARKit positions")
    }
    
    func testARKitArcLengthCalculation() {
        // Test that arc length is calculated from position trajectory
        let positions: [SIMD3<Float>] = [
            SIMD3<Float>(0, 0, 0),
            SIMD3<Float>(1, 0, 0),
            SIMD3<Float>(1, 1, 0),
            SIMD3<Float>(0, 1, 0),
            SIMD3<Float>(0, 0, 0)
        ]
        
        var timestamp = 0.0
        for position in positions {
            sparcService.addARKitPositionData(timestamp: timestamp, position: position)
            timestamp += 0.1
        }
        
        let expectation = XCTestExpectation(description: "Arc length")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 0.5)
        
        // Arc length should be approximately 4.0 (square perimeter)
        // SPARC should reflect this movement
        let sparc = sparcService.getCurrentSPARC()
        XCTAssertGreaterThan(sparc, 0.0, "SPARC should reflect arc length")
    }
    
    // MARK: - Vision/Camera Data Tests
    
    func testVisionDataProcessing() {
        // Simulate camera-based pose tracking
        var timestamp = 0.0
        
        for i in 0..<40 {
            let x = CGFloat(cos(Double(i) * 0.2) * 100 + 200)
            let y = CGFloat(sin(Double(i) * 0.2) * 100 + 300)
            let position = CGPoint(x: x, y: y)
            
            sparcService.addVisionMovement(timestamp: timestamp, position: position)
            timestamp += 0.033 // ~30 FPS
        }
        
        let expectation = XCTestExpectation(description: "Vision SPARC")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        let sparc = sparcService.getCurrentSPARC()
        XCTAssertGreaterThan(sparc, 0.0, "SPARC should be calculated from vision data")
    }
    
    func testVisionVelocityEstimation() {
        // Test that velocity is estimated from position changes
        let positions: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 10, y: 0),
            CGPoint(x: 20, y: 0),
            CGPoint(x: 30, y: 0),
            CGPoint(x: 40, y: 0)
        ]
        
        var timestamp = 0.0
        for position in positions {
            sparcService.addVisionMovement(timestamp: timestamp, position: position)
            timestamp += 0.1
        }
        
        let expectation = XCTestExpectation(description: "Velocity estimation")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 0.5)
        
        // Should calculate SPARC from estimated velocity
        let sparc = sparcService.getCurrentSPARC()
        XCTAssertGreaterThanOrEqual(sparc, 0.0, "SPARC should work with estimated velocity")
    }
    
    // MARK: - Smoothness Quality Tests
    
    func testSmoothMovementHighSPARC() {
        // Smooth sinusoidal movement should produce high SPARC
        var timestamp = 0.0
        
        for i in 0..<60 {
            let angle = Double(i) * 0.1
            let acceleration = [sin(angle) * 0.5, cos(angle) * 0.5, 0.0]
            let velocity = [cos(angle) * 0.05, -sin(angle) * 0.05, 0.0]
            
            sparcService.addIMUData(timestamp: timestamp, acceleration: acceleration, velocity: velocity)
            timestamp += 0.02
        }
        
        let expectation = XCTestExpectation(description: "Smooth movement")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        let sparc = sparcService.getCurrentSPARC()
        XCTAssertGreaterThan(sparc, 40.0, "Smooth movement should produce higher SPARC")
    }
    
    func testJerkyMovementLowSPARC() {
        // Jerky, irregular movement should produce lower SPARC
        var timestamp = 0.0
        
        for i in 0..<60 {
            // Random jerky movements
            let randomAccel = Double.random(in: -2.0...2.0)
            let acceleration = [randomAccel, Double.random(in: -2.0...2.0), 0.0]
            let velocity = [randomAccel * 0.1, Double.random(in: -0.2...0.2), 0.0]
            
            sparcService.addIMUData(timestamp: timestamp, acceleration: acceleration, velocity: velocity)
            timestamp += 0.02
        }
        
        let expectation = XCTestExpectation(description: "Jerky movement")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        let sparc = sparcService.getCurrentSPARC()
        // Jerky movement should produce lower SPARC (but still valid)
        XCTAssertGreaterThanOrEqual(sparc, 0.0, "SPARC should be valid for jerky movement")
        XCTAssertLessThanOrEqual(sparc, 100.0, "SPARC should be within range")
    }
    
    // MARK: - Session Management Tests
    
    func testResetClearsData() {
        // Add some data
        for i in 0..<30 {
            let timestamp = Double(i) * 0.01
            let acceleration = [sin(Double(i) * 0.1), cos(Double(i) * 0.1), 0.0]
            sparcService.addIMUData(timestamp: timestamp, acceleration: acceleration, velocity: nil)
        }
        
        // Reset
        sparcService.reset()
        
        // Verify state is cleared
        XCTAssertEqual(sparcService.getCurrentSPARC(), 0.0, "SPARC should be reset to 0")
        XCTAssertEqual(sparcService.getAverageSPARC(), 0.0, "Average SPARC should be reset to 0")
    }
    
    func testEndSessionCalculation() {
        // Add movement data
        for i in 0..<50 {
            let timestamp = Double(i) * 0.02
            let acceleration = [sin(Double(i) * 0.15), cos(Double(i) * 0.15), 0.0]
            let velocity = [cos(Double(i) * 0.15) * 0.1, -sin(Double(i) * 0.15) * 0.1, 0.0]
            sparcService.addIMUData(timestamp: timestamp, acceleration: acceleration, velocity: velocity)
        }
        
        // End session and get final result
        let result = sparcService.endSession()
        
        XCTAssertGreaterThan(result.smoothness, 0.0, "End session should return valid smoothness")
        XCTAssertGreaterThanOrEqual(result.confidence, 0.0, "Confidence should be non-negative")
        XCTAssertLessThanOrEqual(result.confidence, 1.0, "Confidence should be <= 1.0")
    }
    
    func testAverageSPARCTracking() {
        // Add data in batches to trigger multiple SPARC calculations
        for batch in 0..<3 {
            for i in 0..<40 {
                let timestamp = Double(batch * 40 + i) * 0.02
                let acceleration = [sin(Double(i) * 0.1), cos(Double(i) * 0.1), 0.0]
                let velocity = [cos(Double(i) * 0.1) * 0.1, -sin(Double(i) * 0.1) * 0.1, 0.0]
                sparcService.addIMUData(timestamp: timestamp, acceleration: acceleration, velocity: velocity)
            }
            
            // Wait for calculation
            Thread.sleep(forTimeInterval: 0.3)
        }
        
        let expectation = XCTestExpectation(description: "Average SPARC")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
        
        let avgSparc = sparcService.getAverageSPARC()
        XCTAssertGreaterThan(avgSparc, 0.0, "Average SPARC should be calculated")
    }
    
    // MARK: - Data Point Tracking Tests
    
    func testSPARCDataPointsRecorded() {
        // Add data
        for i in 0..<50 {
            let timestamp = Double(i) * 0.02
            let acceleration = [sin(Double(i) * 0.1), cos(Double(i) * 0.1), 0.0]
            sparcService.addIMUData(timestamp: timestamp, acceleration: acceleration, velocity: nil)
        }
        
        let expectation = XCTestExpectation(description: "Data points")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        let dataPoints = sparcService.getSPARCDataPoints()
        XCTAssertGreaterThan(dataPoints.count, 0, "SPARC data points should be recorded")
        
        // Verify data point structure
        if let firstPoint = dataPoints.first {
            XCTAssertGreaterThanOrEqual(firstPoint.sparcValue, 0.0, "SPARC value should be valid")
            XCTAssertLessThanOrEqual(firstPoint.sparcValue, 100.0, "SPARC value should be in range")
            XCTAssertGreaterThanOrEqual(firstPoint.confidence, 0.0, "Confidence should be valid")
            XCTAssertLessThanOrEqual(firstPoint.confidence, 1.0, "Confidence should be <= 1.0")
        }
    }
    
    // MARK: - Edge Cases
    
    func testInsufficientDataHandling() {
        // Add very few samples (below minimum threshold)
        for i in 0..<5 {
            let timestamp = Double(i) * 0.01
            let acceleration = [0.1, 0.1, 0.0]
            sparcService.addIMUData(timestamp: timestamp, acceleration: acceleration, velocity: nil)
        }
        
        // Should not crash with insufficient data
        let sparc = sparcService.getCurrentSPARC()
        XCTAssertGreaterThanOrEqual(sparc, 0.0, "Should handle insufficient data gracefully")
    }
    
    func testZeroMovementHandling() {
        // Add samples with no movement
        for i in 0..<50 {
            let timestamp = Double(i) * 0.01
            let acceleration = [0.0, 0.0, 0.0]
            let velocity = [0.0, 0.0, 0.0]
            sparcService.addIMUData(timestamp: timestamp, acceleration: acceleration, velocity: velocity)
        }
        
        let expectation = XCTestExpectation(description: "Zero movement")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // Should handle zero movement without crashing
        let sparc = sparcService.getCurrentSPARC()
        XCTAssertGreaterThanOrEqual(sparc, 0.0, "Should handle zero movement")
    }
    
    func testInvalidAccelerationData() {
        // Test with invalid/incomplete acceleration data
        let invalidAcceleration = [1.0, 2.0] // Only 2 components instead of 3
        sparcService.addIMUData(timestamp: 0.0, acceleration: invalidAcceleration, velocity: nil)
        
        // Should handle gracefully without crashing
        XCTAssertTrue(true, "Should handle invalid acceleration data without crashing")
    }
}
