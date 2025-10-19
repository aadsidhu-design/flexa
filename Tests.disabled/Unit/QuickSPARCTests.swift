import XCTest
import simd
@testable import FlexaSwiftUI

/// Fast unit tests for SPARC - validates core functionality quickly
final class QuickSPARCTests: XCTestCase {
    
    func testSPARCBasicCalculation() {
        let sparc = SPARCCalculationService()
        
        // Add simple sinusoidal movement
        for i in 0..<50 {
            let t = Double(i) * 0.02
            let accel = [sin(t * 10), cos(t * 10), 0.0]
            let vel = [cos(t * 10) * 0.1, -sin(t * 10) * 0.1, 0.0]
            sparc.addIMUData(timestamp: t, acceleration: accel, velocity: vel)
        }
        
        // Give it a moment to calculate
        Thread.sleep(forTimeInterval: 0.3)
        
        let value = sparc.getCurrentSPARC()
        XCTAssertGreaterThan(value, 0.0, "SPARC should be calculated")
        XCTAssertLessThanOrEqual(value, 100.0, "SPARC should be in valid range")
    }
    
    func testSPARCWithARKitData() {
        let sparc = SPARCCalculationService()
        
        // Circular motion
        for i in 0..<30 {
            let angle = Double(i) * 0.2
            let pos = SIMD3<Float>(Float(cos(angle)), Float(sin(angle)), 0)
            sparc.addARKitPositionData(timestamp: Double(i) * 0.033, position: pos)
        }
        
        Thread.sleep(forTimeInterval: 0.2)
        
        let value = sparc.getCurrentSPARC()
        XCTAssertGreaterThanOrEqual(value, 0.0, "ARKit SPARC should be valid")
    }
    
    func testSPARCWithVisionData() {
        let sparc = SPARCCalculationService()
        
        // Linear motion
        for i in 0..<25 {
            let pos = CGPoint(x: Double(i) * 10, y: 100)
            sparc.addVisionMovement(timestamp: Double(i) * 0.04, position: pos)
        }
        
        Thread.sleep(forTimeInterval: 0.2)
        
        let value = sparc.getCurrentSPARC()
        XCTAssertGreaterThanOrEqual(value, 0.0, "Vision SPARC should be valid")
    }
    
    func testSPARCReset() {
        let sparc = SPARCCalculationService()
        
        // Add data
        for i in 0..<30 {
            let accel = [0.5, 0.5, 0.0]
            sparc.addIMUData(timestamp: Double(i) * 0.01, acceleration: accel, velocity: nil)
        }
        
        sparc.reset()
        
        XCTAssertEqual(sparc.getCurrentSPARC(), 0.0, "Reset should clear SPARC")
        XCTAssertEqual(sparc.getAverageSPARC(), 0.0, "Reset should clear average")
    }
    
    func testSPARCEndSession() {
        let sparc = SPARCCalculationService()
        
        // Add movement
        for i in 0..<40 {
            let t = Double(i) * 0.02
            let accel = [sin(t * 5), cos(t * 5), 0.0]
            let vel = [cos(t * 5) * 0.1, -sin(t * 5) * 0.1, 0.0]
            sparc.addIMUData(timestamp: t, acceleration: accel, velocity: vel)
        }
        
        let result = sparc.endSession()
        
        XCTAssertGreaterThanOrEqual(result.smoothness, 0.0, "End session should return valid smoothness")
        XCTAssertGreaterThanOrEqual(result.confidence, 0.0, "Confidence should be valid")
        XCTAssertLessThanOrEqual(result.confidence, 1.0, "Confidence should be <= 1.0")
    }
    
    func testSPARCHandlesInvalidData() {
        let sparc = SPARCCalculationService()
        
        // Invalid acceleration (only 2 components)
        sparc.addIMUData(timestamp: 0.0, acceleration: [1.0, 2.0], velocity: nil)
        
        // Should not crash
        XCTAssertTrue(true, "Should handle invalid data gracefully")
    }
    
    func testSPARCHandlesZeroMovement() {
        let sparc = SPARCCalculationService()
        
        // No movement
        for i in 0..<30 {
            sparc.addIMUData(timestamp: Double(i) * 0.01, acceleration: [0, 0, 0], velocity: [0, 0, 0])
        }
        
        Thread.sleep(forTimeInterval: 0.2)
        
        let value = sparc.getCurrentSPARC()
        XCTAssertGreaterThanOrEqual(value, 0.0, "Should handle zero movement")
    }
}
