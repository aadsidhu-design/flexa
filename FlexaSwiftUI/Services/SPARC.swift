import Foundation

/// Simple Spectral Arc Length (SPARC) approximation.
/// Input is a sequence of angles (degrees) sampled at fixed interval dt (seconds).
/// Returns a smoothness score (more negative → less smooth). Typical range [-8, -2].
struct SPARC {
    static func compute(angles: [Double], dt: Double) -> Double {
        let n = angles.count
        guard n >= 16, dt > 0 else { return 0 }
        // Detrend and normalize
        let mean = angles.reduce(0, +) / Double(n)
        let x = angles.map { $0 - mean }
        // Compute velocity profile (finite diff)
        var v = [Double](repeating: 0, count: n)
        for i in 1..<n { v[i] = (x[i] - x[i-1]) / dt }
        // Hanning window to reduce spectral leakage
        var w = [Double](repeating: 0, count: n)
        for i in 0..<n { w[i] = 0.5 - 0.5 * cos(2.0 * .pi * Double(i) / Double(n-1)) }
        let vw = zip(v, w).map(* )
        // DFT magnitude (first half)
        let mags = dftMagnitude(vw)
        // Normalize frequency axis to [0,1]
        let m = mags.count
        guard m > 2 else { return 0 }
        var arc: Double = 0
        for k in 1..<m {
            let dy = mags[k] - mags[k-1]
            let dx = 1.0 / Double(m-1)
            arc += sqrt(dx*dx + dy*dy)
        }
        return -arc // negative arc length (higher magnitude changes => more negative)
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
