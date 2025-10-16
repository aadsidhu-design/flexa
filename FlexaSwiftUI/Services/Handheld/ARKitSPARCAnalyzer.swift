import Foundation
import simd
import Accelerate

/// Analyzes movement smoothness from ARKit position data using spectral analysis.
final class ARKitSPARCAnalyzer {
    
    // MARK: - Data Structures
    
    struct PositionSample {
        let position: SIMD3<Float>
        let timestamp: TimeInterval
    }
    
    struct PositionSample2D {
        let position: SIMD2<Float>
        let timestamp: TimeInterval
    }
    
    struct SPARCResult {
        let overallScore: Double      // 0-100 smoothness score
        let smoothnessScore: Double   // 0-100 normalized score
        let perRepScores: [Double]    // Individual rep smoothness
        let timeline: [SPARCPoint]    // For visualization
        let peakVelocity: Double      // m/s
        let avgAcceleration: Double   // m/s²
        let jerkiness: Double         // Jerk metric (for reference)
    }
    
    enum GameType {
        case pendulum
        case circular
        case freeForm
    }
    
    // MARK: - Public API
    
    static func analyze(
        positions: [SIMD3<Float>],
        timestamps: [Date],
        gameType: GameType,
        repCount: Int
    ) -> SPARCResult {
        
        guard positions.count >= 32, positions.count == timestamps.count else {
            FlexaLog.motion.warning("📊 [ARKitSPARC] Insufficient data: \(positions.count) samples")
            return SPARCResult(overallScore: 0, smoothnessScore: 0, perRepScores: [], timeline: [], peakVelocity: 0, avgAcceleration: 0, jerkiness: 1.0)
        }
        
        // Auto-detect best 2D plane from positions to minimize bias
        let bestPlane = findBestProjectionPlane(positions)
        let positions2D = positions.map { projectTo2D($0, plane: bestPlane) }
        
        let samples = zip(positions2D, timestamps).map { position2D, date in
            PositionSample2D(position: position2D, timestamp: date.timeIntervalSince1970)
        }
        
        let velocities = calculateVelocities2D(from: samples)
        let accelerations = calculateAccelerations2D(from: velocities)
        let jerks = calculateJerks2D(from: accelerations)
        
        let (sparcScore, timeline) = calculateSPARCFromSpectrum(velocities: velocities)
        
        let perRepScores = calculatePerRepScores(velocities: velocities, repCount: repCount)
        
        let peakVel = velocities.map { $0.magnitude }.max() ?? 0
        let avgAccel = accelerations.isEmpty ? 0 : accelerations.map { $0.magnitude }.reduce(0, +) / Double(accelerations.count)
        let avgJerk = jerks.isEmpty ? 1.0 : jerks.map { $0.magnitude }.reduce(0, +) / Double(jerks.count)
        
        guard !avgAccel.isNaN, !avgAccel.isInfinite else { return SPARCResult(overallScore: 50, smoothnessScore: 50, perRepScores: [], timeline: [], peakVelocity: peakVel, avgAcceleration: 0, jerkiness: avgJerk) }
        guard !avgJerk.isNaN, !avgJerk.isInfinite else { return SPARCResult(overallScore: 50, smoothnessScore: 50, perRepScores: [], timeline: [], peakVelocity: peakVel, avgAcceleration: avgAccel, jerkiness: 1.0) }
        
        let scoreInt = sparcScore.isNaN || sparcScore.isInfinite ? 50 : Int(sparcScore)
        FlexaLog.motion.info("📊 [ARKitSPARC] Analysis complete on plane \(bestPlane): score=\(String(format: "%.2f", sparcScore)) smooth=\(scoreInt)% vel=\(String(format: "%.2f", peakVel))m/s jerk=\(String(format: "%.3f", avgJerk))")
        
        return SPARCResult(
            overallScore: sparcScore,
            smoothnessScore: sparcScore,
            perRepScores: perRepScores,
            timeline: timeline,
            peakVelocity: peakVel,
            avgAcceleration: avgAccel,
            jerkiness: avgJerk
        )
    }
    
    // MARK: - 2D Velocity, Acceleration, Jerk Calculation
    
    private struct VelocitySample2D {
        let velocity: SIMD2<Float>
        let magnitude: Double
        let timestamp: TimeInterval
    }
    
    private static func calculateVelocities2D(from samples: [PositionSample2D]) -> [VelocitySample2D] {
        guard samples.count >= 2 else { return [] }
        var velocities: [VelocitySample2D] = []
        for i in 1..<samples.count {
            let dt = samples[i].timestamp - samples[i-1].timestamp
            guard dt > 0 else { continue }
            let dp = samples[i].position - samples[i-1].position
            let vel = dp / Float(dt)
            velocities.append(VelocitySample2D(velocity: vel, magnitude: Double(simd_length(vel)), timestamp: samples[i].timestamp))
        }
        return velocities
    }
    
    private struct AccelerationSample2D {
        let acceleration: SIMD2<Float>
        let magnitude: Double
        let timestamp: TimeInterval
    }
    
    private static func calculateAccelerations2D(from velocities: [VelocitySample2D]) -> [AccelerationSample2D] {
        guard velocities.count >= 2 else { return [] }
        var accelerations: [AccelerationSample2D] = []
        for i in 1..<velocities.count {
            let dt = velocities[i].timestamp - velocities[i-1].timestamp
            guard dt > 0 else { continue }
            let dv = velocities[i].velocity - velocities[i-1].velocity
            let accel = dv / Float(dt)
            accelerations.append(AccelerationSample2D(acceleration: accel, magnitude: Double(simd_length(accel)), timestamp: velocities[i].timestamp))
        }
        return accelerations
    }
    
    private struct JerkSample2D {
        let jerk: SIMD2<Float>
        let magnitude: Double
        let timestamp: TimeInterval
    }
    
    private static func calculateJerks2D(from accelerations: [AccelerationSample2D]) -> [JerkSample2D] {
        guard accelerations.count >= 2 else { return [] }
        var jerks: [JerkSample2D] = []
        for i in 1..<accelerations.count {
            let dt = accelerations[i].timestamp - accelerations[i-1].timestamp
            guard dt > 0 else { continue }
            let da = accelerations[i].acceleration - accelerations[i-1].acceleration
            let jerk = da / Float(dt)
            jerks.append(JerkSample2D(jerk: jerk, magnitude: Double(simd_length(jerk)), timestamp: accelerations[i].timestamp))
        }
        return jerks
    }
    
    // MARK: - Velocity, Acceleration, Jerk Calculation (for reference)
    
    private struct VelocitySample {
        let velocity: SIMD3<Float>
        let magnitude: Double
        let timestamp: TimeInterval
    }
    
    private static func calculateVelocities(from samples: [PositionSample]) -> [VelocitySample] {
        guard samples.count >= 2 else { return [] }
        var velocities: [VelocitySample] = []
        for i in 1..<samples.count {
            let dt = samples[i].timestamp - samples[i-1].timestamp
            guard dt > 0 else { continue }
            let dp = samples[i].position - samples[i-1].position
            let vel = dp / Float(dt)
            velocities.append(VelocitySample(velocity: vel, magnitude: Double(simd_length(vel)), timestamp: samples[i].timestamp))
        }
        return velocities
    }
    
    private struct AccelerationSample {
        let acceleration: SIMD3<Float>
        let magnitude: Double
        let timestamp: TimeInterval
    }
    
    private static func calculateAccelerations(from velocities: [VelocitySample]) -> [AccelerationSample] {
        guard velocities.count >= 2 else { return [] }
        var accelerations: [AccelerationSample] = []
        for i in 1..<velocities.count {
            let dt = velocities[i].timestamp - velocities[i-1].timestamp
            guard dt > 0 else { continue }
            let dv = velocities[i].velocity - velocities[i-1].velocity
            let accel = dv / Float(dt)
            accelerations.append(AccelerationSample(acceleration: accel, magnitude: Double(simd_length(accel)), timestamp: velocities[i].timestamp))
        }
        return accelerations
    }
    
    private struct JerkSample {
        let jerk: SIMD3<Float>
        let magnitude: Double
        let timestamp: TimeInterval
    }
    
    private static func calculateJerks(from accelerations: [AccelerationSample]) -> [JerkSample] {
        guard accelerations.count >= 2 else { return [] }
        var jerks: [JerkSample] = []
        for i in 1..<accelerations.count {
            let dt = accelerations[i].timestamp - accelerations[i-1].timestamp
            guard dt > 0 else { continue }
            let da = accelerations[i].acceleration - accelerations[i-1].acceleration
            let jerk = da / Float(dt)
            jerks.append(JerkSample(jerk: jerk, magnitude: Double(simd_length(jerk)), timestamp: accelerations[i].timestamp))
        }
        return jerks
    }
    
    // MARK: - New SPARC Calculation from Spectrum
    
    private static func calculateSPARCScore(velocities: [VelocitySample]) -> Double {
        guard velocities.count >= 32 else { return 50.0 }
        
        let velocityMagnitudes = velocities.map { Float($0.magnitude) }
        guard !velocityMagnitudes.isEmpty else { return 50.0 }
        
        let n = vDSP_Length(nextPowerOfTwo(for: velocityMagnitudes.count))
        var realp = [Float](velocityMagnitudes)
        if realp.count < Int(n) {
            realp.append(contentsOf: Array(repeating: Float(0), count: Int(n) - realp.count))
        }
        var imagp = [Float](repeating: 0, count: Int(n))
        
        let score: Double = realp.withUnsafeMutableBufferPointer { realp_ptr in
            imagp.withUnsafeMutableBufferPointer { imagp_ptr in
                var splitComplex = DSPSplitComplex(realp: realp_ptr.baseAddress!, imagp: imagp_ptr.baseAddress!)
                
                let log2n = vDSP_Length(log2(Float(n)))
                guard let fftSetUp = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return 50.0 }
                defer { vDSP_destroy_fftsetup(fftSetUp) }
                
                vDSP_fft_zip(fftSetUp, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
                
                var magnitudes = [Float](repeating: 0.0, count: Int(n/2))
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(n/2))
                
                let totalPower = vDSP.sum(magnitudes)
                guard totalPower > 1e-6, !totalPower.isNaN, !totalPower.isInfinite else { return 50.0 }
                
                guard let maxMagnitude = magnitudes.max() else { return 50.0 }
                guard maxMagnitude > 0, !maxMagnitude.isNaN, !maxMagnitude.isInfinite else { return 50.0 }
                
                guard let dominantFrequencyIndex = magnitudes.firstIndex(of: maxMagnitude) else {
                    return 50.0
                }
                
                guard dominantFrequencyIndex >= 0, dominantFrequencyIndex < magnitudes.count else {
                    return 50.0
                }
                
                let dominantFrequencyPower = magnitudes[dominantFrequencyIndex]
                guard !dominantFrequencyPower.isNaN, !dominantFrequencyPower.isInfinite else { return 50.0 }
                
                let spectralPurity = dominantFrequencyPower / totalPower
                guard !spectralPurity.isNaN, !spectralPurity.isInfinite else { return 50.0 }
                
                let score = Double(spectralPurity * 100)
                guard !score.isNaN, !score.isInfinite else { return 50.0 }
                
                return min(100.0, max(0.0, score))
            }
        }
        
        return score.isNaN || score.isInfinite ? 50.0 : score
    }

    private static func calculateSPARCFromSpectrum(velocities: [VelocitySample2D]) -> (score: Double, timeline: [SPARCPoint]) {
        let overallScore = calculateSPARCScore2D(velocities: velocities)
        guard !overallScore.isNaN, !overallScore.isInfinite else { return (50.0, []) }
        
        var timeline: [SPARCPoint] = []
        let windowSize = 32
        
        guard velocities.count >= windowSize else { return (overallScore, timeline) }
        
        for i in (windowSize - 1)..<velocities.count {
            guard i - windowSize + 1 >= 0, i < velocities.count else { continue }
            let window = Array(velocities[(i - windowSize + 1)...i])
            let score = calculateSPARCScore2D(velocities: window)
            guard !score.isNaN, !score.isInfinite else { continue }
            if let lastSample = window.last {
                timeline.append(SPARCPoint(sparc: score, timestamp: Date(timeIntervalSince1970: lastSample.timestamp)))
            }
        }
        
        return (overallScore, timeline)
    }
    
    private static func calculateSPARCScore2D(velocities: [VelocitySample2D]) -> Double {
        guard velocities.count >= 32 else { return 50.0 }
        
        let velocityMagnitudes = velocities.map { Float($0.magnitude) }
        guard !velocityMagnitudes.isEmpty else { return 50.0 }
        
        let n = vDSP_Length(nextPowerOfTwo(for: velocityMagnitudes.count))
        var realp = [Float](velocityMagnitudes)
        if realp.count < Int(n) {
            realp.append(contentsOf: Array(repeating: Float(0), count: Int(n) - realp.count))
        }
        var imagp = [Float](repeating: 0, count: Int(n))
        
        let score: Double = realp.withUnsafeMutableBufferPointer { realp_ptr in
            imagp.withUnsafeMutableBufferPointer { imagp_ptr in
                var splitComplex = DSPSplitComplex(realp: realp_ptr.baseAddress!, imagp: imagp_ptr.baseAddress!)
                
                let log2n = vDSP_Length(log2(Float(n)))
                guard let fftSetUp = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return 50.0 }
                defer { vDSP_destroy_fftsetup(fftSetUp) }
                
                vDSP_fft_zip(fftSetUp, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
                
                var magnitudes = [Float](repeating: 0.0, count: Int(n/2))
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(n/2))
                
                let totalPower = vDSP.sum(magnitudes)
                guard totalPower > 1e-6, !totalPower.isNaN, !totalPower.isInfinite else { return 50.0 }
                
                guard let maxMagnitude = magnitudes.max() else { return 50.0 }
                guard maxMagnitude > 0, !maxMagnitude.isNaN, !maxMagnitude.isInfinite else { return 50.0 }
                
                guard let dominantFrequencyIndex = magnitudes.firstIndex(of: maxMagnitude) else { return 50.0 }
                guard dominantFrequencyIndex >= 0, dominantFrequencyIndex < magnitudes.count else { return 50.0 }
                
                let dominantFrequencyPower = magnitudes[dominantFrequencyIndex]
                guard !dominantFrequencyPower.isNaN, !dominantFrequencyPower.isInfinite else { return 50.0 }
                
                let spectralPurity = dominantFrequencyPower / totalPower
                guard !spectralPurity.isNaN, !spectralPurity.isInfinite else { return 50.0 }
                
                let score = Double(spectralPurity * 100)
                guard !score.isNaN, !score.isInfinite else { return 50.0 }
                
                return min(100.0, max(0.0, score))
            }
        }
        
        return score.isNaN || score.isInfinite ? 50.0 : score
    }
    
    private static func createTimelineFromSpectrum(velocities: [VelocitySample], score: Double) -> [SPARCPoint] {
        return velocities.map { SPARCPoint(sparc: score, timestamp: Date(timeIntervalSince1970: $0.timestamp)) }
    }
    
    private static func calculatePerRepScores(velocities: [VelocitySample2D], repCount: Int) -> [Double] {
        guard repCount > 0, velocities.count >= repCount else { return [] }
        
        let samplesPerRep = velocities.count / repCount
        guard samplesPerRep > 0 else { return [] }
        
        var perRepScores: [Double] = []
        for i in 0..<repCount {
            let start = i * samplesPerRep
            let end = min((i + 1) * samplesPerRep, velocities.count)
            guard start >= 0, start < velocities.count, end > start else { continue }
            let repVelocities = Array(velocities[start..<end])
            guard !repVelocities.isEmpty else { continue }
            let score = calculateSPARCScore2D(velocities: repVelocities)
            guard !score.isNaN, !score.isInfinite else { continue }
            perRepScores.append(score)
        }
        
        return perRepScores
    }
    
    private static func nextPowerOfTwo(for number: Int) -> Int {
        var n = number
        n -= 1
        n |= n >> 1
        n |= n >> 2
        n |= n >> 4
        n |= n >> 8
        n |= n >> 16
        n += 1
        return n
    }
    
    // MARK: - 2D Plane Detection and Projection
    
    private enum ProjectionPlane: CustomStringConvertible {
        case xy, xz, yz
        
        var description: String {
            switch self {
            case .xy: return "XY"
            case .xz: return "XZ"
            case .yz: return "YZ"
            }
        }
    }
    
    /// Find best 2D plane by analyzing motion distribution across axes
    private static func findBestProjectionPlane(_ positions: [SIMD3<Float>]) -> ProjectionPlane {
        guard positions.count >= 2 else { return .xy }
        
        var minX = positions[0].x, maxX = positions[0].x
        var minY = positions[0].y, maxY = positions[0].y
        var minZ = positions[0].z, maxZ = positions[0].z
        
        // Find axis ranges
        for pos in positions {
            minX = min(minX, pos.x); maxX = max(maxX, pos.x)
            minY = min(minY, pos.y); maxY = max(maxY, pos.y)
            minZ = min(minZ, pos.z); maxZ = max(maxZ, pos.z)
        }
        
        let rangeX = maxX - minX
        let rangeY = maxY - minY
        let rangeZ = maxZ - minZ
        
        // Determine which two axes have most motion
        let ranges = [(rangeX, "X"), (rangeY, "Y"), (rangeZ, "Z")]
        let sorted = ranges.sorted { $0.0 > $1.0 }
        
        let axis1 = sorted[0].1
        let axis2 = sorted[1].1
        
        if (axis1 == "X" && axis2 == "Y") || (axis1 == "Y" && axis2 == "X") {
            return .xy
        } else if (axis1 == "X" && axis2 == "Z") || (axis1 == "Z" && axis2 == "X") {
            return .xz
        } else {
            return .yz
        }
    }
    
    /// Project 3D position to 2D based on chosen plane
    private static func projectTo2D(_ pos: SIMD3<Float>, plane: ProjectionPlane) -> SIMD2<Float> {
        switch plane {
        case .xy: return SIMD2<Float>(pos.x, pos.y)
        case .xz: return SIMD2<Float>(pos.x, pos.z)
        case .yz: return SIMD2<Float>(pos.y, pos.z)
        }
    }
}

