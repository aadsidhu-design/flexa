import XCTest
@testable import FlexaSwiftUI
import simd

class HandheldROMCalculatorTests: XCTestCase {
    func testFullTrajectoryRepAndROM() {
        // Full trajectory from logs (example: copy-paste from RepTrajectory)
        let positions: [SIMD3<Float>] = [
            SIMD3<Float>(0.0030926913, -0.0013516396, 0.00932765),
            SIMD3<Float>(0.0030926913, -0.0013516396, 0.00932765),
            SIMD3<Float>(0.0059042573, -0.0024169236, 0.0178051),
            SIMD3<Float>(0.0059042573, -0.0024169236, 0.0178051),
            SIMD3<Float>(0.0033370405, 0.0059683174, -0.0071575046),
            SIMD3<Float>(0.0032572385, 0.0058618314, -0.005193977),
            SIMD3<Float>(0.0030628294, 0.0051845983, -0.0021014214),
            SIMD3<Float>(0.0029010624, 0.00477352, 0.0007504821),
            SIMD3<Float>(0.0029010624, 0.00477352, 0.0007504821),
            SIMD3<Float>(0.0029133942, 0.004756791, 0.0029619648),
            SIMD3<Float>(0.0029133942, 0.004756791, 0.0029619648),
            SIMD3<Float>(0.008225679, 0.0036155656, -0.02549398),
            SIMD3<Float>(0.009540603, 0.0033002868, -0.03621161),
            SIMD3<Float>(0.009751582, 0.0034164987, -0.041514367)
            // ... (add more positions from your log as needed)
        ]
        let calculator = HandheldROMCalculator()
        for pos in positions {
            calculator.processPosition(pos, timestamp: Date().timeIntervalSince1970)
        }
        print("Detected reps: \(calculator.repCount)")
        print("ROM per rep: \(calculator.romPerRep)")
        print("Max ROM: \(calculator.maxROM)")
    }
}
