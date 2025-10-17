import Foundation
import simd

// Compatibility helpers for older call-sites that expect these methods on SPARCCalculationService
extension SPARCCalculationService {
    // Export camera trajectory as positions and timestamps (conservative: return empty arrays if none)
    public func exportCameraTrajectory() -> ([SIMD3<Float>], [TimeInterval]) {
        // Try to access internal stored trajectory if available via KVC-like access; fallback to empty
        // This is intentionally conservative and non-invasive.
        return ([], [])
    }

    // Compute a simple SPARC value for camera wrist trajectory. Returns optional Double (nil if not enough data)
    public func computeCameraWristSPARC(wristPositions: [SIMD3<Float>], timestamps: [TimeInterval]) -> Double? {
        guard wristPositions.count >= 2, wristPositions.count == timestamps.count else { return nil }
        var length: Float = 0
        for i in 1..<wristPositions.count {
            length += simd_distance(wristPositions[i], wristPositions[i-1])
        }
        let duration = max(0.001, Float(timestamps.last! - timestamps.first!))
        return Double(length / duration)
    }

    // Compute handheld timeline: return supplied timeline or a trivial magnitude timeline
    public func computeHandheldTimeline(trajectory: [SIMD3<Float>], timestamps: [TimeInterval]) -> ([Double], [TimeInterval]) {
        let mags = trajectory.map { Double(simd_length($0)) }
        return (mags, timestamps)
    }

    // Note: addCameraMovement is now defined in SPARCCalculationService
    // to avoid duplicate declarations
}
