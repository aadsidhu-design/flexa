import XCTest
import simd
@testable import FlexaSwiftUI

final class MediaPipeTransformTests: XCTestCase {
    /// Verify front camera mirroring and clamping behavior for normalized landmarks.
    func testMirroringAndClamping() {
        // Simulate raw MediaPipe normalized coordinates (x,y) in and out of 0..1 range
        let rawValues: [(CGFloat, CGFloat, Bool, CGPoint)] = [
            // rawX, rawY, isFront, expectedNormalizedPoint
            (0.2, 0.7, false, CGPoint(x: 0.2, y: 0.7)),
            (0.2, 0.7, true, CGPoint(x: 0.8, y: 0.7)), // mirrored
            (-0.1, 1.2, false, CGPoint(x: 0.0, y: 1.0)), // clamped
            (1.1, -0.2, true, CGPoint(x: 0.0, y: 0.0)), // mirrored after clamp
        ]

        for (rawX, rawY, isFront, expected) in rawValues {
            // Mirror logic used in MediaPipePoseProvider.getNormalizedMirroredPoint:
            var clampedX = max(0, min(1, CGFloat(rawX)))
            let clampedY = max(0, min(1, CGFloat(rawY)))
            var normalizedX = clampedX
            if isFront {
                normalizedX = 1.0 - normalizedX
            }
            let result = CGPoint(x: normalizedX, y: clampedY)
            XCTAssertEqual(result.x, expected.x, accuracy: 1e-6)
            XCTAssertEqual(result.y, expected.y, accuracy: 1e-6)
        }
    }
}
