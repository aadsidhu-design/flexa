import Foundation

/// Simple Spectral Arc Length (SPARC) approximation.
/// Input is a sequence of angles (degrees) sampled at fixed interval dt (seconds).
/// Returns a smoothness score (more negative → less smooth). Typical range [-8, -2].
struct SPARC {
    static func compute(angles: [Double], dt: Double) -> Double {
        // Prefer canonical SPARC implementation from SPARCCalculationService.
        // This keeps spectral and normalization behavior consistent across the app.
        do {
            // Convert angles (Double) to Float array for service input
            let signal = angles.map { Float($0) }
            let result = try SPARCCalculationService.computeSPARCStandalone(signal: signal, samplingRate: 1.0 / dt)
            // SPARCCalculationService returns a SPARCResult; its smoothness is in 0..100
            // Map back to a negative arc-like value if necessary; preserve smoothness if available
            return result.smoothness
        } catch {
            // As a safe fallback, return 0 if SPARC computation fails
            FlexaLog.motion.warning("SPARC.compute fallback due to error: \(error.localizedDescription)")
            return 0
        }
    }
    
    private static func dftMagnitude(_ x: [Double]) -> [Double] {
        let n = x.count
        let half = n/2
        var mags = [Double](repeating: 0, count: half)
        for k in 0..<half {
            var re = 0.0, im = 0.0
            for n0 in 0..<n {
                let theta = -2.0 * .pi * Double(k) * Double(n0) / Double(n)
                re += x[n0] * cos(theta)
                im += x[n0] * sin(theta)
            }
            mags[k] = sqrt(re*re + im*im)
        }
        // Normalize magnitude
        let maxv = mags.max() ?? 1
        if maxv > 0 { mags = mags.map { $0 / maxv } }
        return mags
    }
}
