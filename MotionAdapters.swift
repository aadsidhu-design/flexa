import Foundation

// Bridge argument label difference used by some call sites
extension SPARCCalculationService {
    func computeTrajectorySPARC(trajectory positions: [SIMD3<Float>], timestamps: [TimeInterval]) throws -> TrajectorySPARCResult? {
        try computeTrajectorySPARC(positions: positions, timestamps: timestamps)
    }
}

// Provide the DiagnosticsSample.stateLabel used by SimpleMotionService
extension InstantARKitTracker.DiagnosticsSample {
    var stateLabel: String { trackingStateDescription }
}
