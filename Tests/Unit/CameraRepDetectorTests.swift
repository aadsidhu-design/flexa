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
