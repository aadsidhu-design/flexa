import CoreMotion
import XCTest

@testable import FlexaSwiftUI

/// Fast unit tests for IMU rep detection - no async, no delays
final class QuickIMURepTests: XCTestCase {

  func testBasicRepDetection() {
    let detector = IMUDirectionRepDetector()
    var reps = 0
    var rom: Double = 20.0

    detector.onRepDetected = { count, _ in reps = count }
    detector.romProvider = { rom }
    detector.startSession()

    // Calibrate (30 samples at rest)
    for i in 0..<30 {
      let motion = MockMotion(gravity: (0, -1, 0), userAccel: (0, 0, 0), time: Double(i) * 0.01)
      detector.processDeviceMotion(motion, timestamp: Double(i) * 0.01)
    }

    // Up movement
    for i in 0..<10 {
      let motion = MockMotion(
        gravity: (0, -1, 0), userAccel: (0, 0.5, 0), time: 0.3 + Double(i) * 0.05)
      detector.processDeviceMotion(motion, timestamp: 0.3 + Double(i) * 0.05)
    }

    // Down movement
    for i in 0..<10 {
      let motion = MockMotion(
        gravity: (0, -1, 0), userAccel: (0, -0.5, 0), time: 0.8 + Double(i) * 0.05)
      detector.processDeviceMotion(motion, timestamp: 0.8 + Double(i) * 0.05)
    }

    XCTAssertGreaterThanOrEqual(reps, 1, "Should detect at least 1 rep")
  }

  func testMinimumROMRejection() {
    let detector = IMUDirectionRepDetector()
    var reps = 0
    var rom: Double = 3.0  // Below minimum

    detector.onRepDetected = { count, _ in reps = count }
    detector.romProvider = { rom }
    detector.startSession()

    // Calibrate
    for i in 0..<30 {
      let motion = MockMotion(gravity: (0, -1, 0), userAccel: (0, 0, 0), time: Double(i) * 0.01)
      detector.processDeviceMotion(motion, timestamp: Double(i) * 0.01)
    }

    // Movement with low ROM
    for i in 0..<20 {
      let accel = i < 10 ? 0.5 : -0.5
      let motion = MockMotion(
        gravity: (0, -1, 0), userAccel: (0, accel, 0), time: 0.3 + Double(i) * 0.05)
      detector.processDeviceMotion(motion, timestamp: 0.3 + Double(i) * 0.05)
    }

    XCTAssertEqual(reps, 0, "Should reject rep with ROM < 5°")
  }

  func testCooldownPreventsRapidReps() {
    let detector = IMUDirectionRepDetector()
    var reps = 0

    detector.onRepDetected = { count, _ in reps = count }
    detector.romProvider = { 20.0 }
    detector.startSession()

    // Calibrate
    for i in 0..<30 {
      let motion = MockMotion(gravity: (0, -1, 0), userAccel: (0, 0, 0), time: Double(i) * 0.01)
      detector.processDeviceMotion(motion, timestamp: Double(i) * 0.01)
    }

    // Rapid movements within cooldown
    var time = 0.3
    for _ in 0..<5 {
      for i in 0..<10 {
        let accel = i < 5 ? 0.5 : -0.5
        let motion = MockMotion(gravity: (0, -1, 0), userAccel: (0, accel, 0), time: time)
        detector.processDeviceMotion(motion, timestamp: time)
        time += 0.02
      }
    }

    XCTAssertLessThanOrEqual(reps, 2, "Cooldown should limit rapid reps")
  }
}

// Simple mock for CMDeviceMotion
class MockMotion: CMDeviceMotion {
  private let _gravity: CMAcceleration
  private let _userAccel: CMAcceleration
  private let _time: TimeInterval

  init(gravity: (Double, Double, Double), userAccel: (Double, Double, Double), time: TimeInterval) {
    _gravity = CMAcceleration(x: gravity.0, y: gravity.1, z: gravity.2)
    _userAccel = CMAcceleration(x: userAccel.0, y: userAccel.1, z: userAccel.2)
    _time = time
    super.init()
  }

  required init?(coder: NSCoder) { fatalError() }

  override var gravity: CMAcceleration { _gravity }
  override var userAcceleration: CMAcceleration { _userAccel }
  override var timestamp: TimeInterval { _time }
}
