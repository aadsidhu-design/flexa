import Foundation
import simd

/// Small compatibility shim used in several places; real implementation lives elsewhere.
struct SPARCDataCollectionFixes {
    let sessionStartTime: Date
    init(sessionStartTime: Date) {
        self.sessionStartTime = sessionStartTime
    }

    func applyFixes(to timeline: [Any]) -> [Any] { return timeline }

    // Create a validated SPARCDataPoint from raw inputs (conservative defaults)
    func createValidatedSPARCDataPoint(timestamp: Date, value: Double, confidence: Double, source: SPARCDataSource) -> SPARCDataPoint {
        return SPARCDataPoint(timestamp: timestamp, sparcValue: value.isNaN ? 0.0 : value, movementPhase: "unknown", jointAngles: [:], confidence: confidence.isNaN ? 0.0 : confidence, dataSource: source)
    }
}
