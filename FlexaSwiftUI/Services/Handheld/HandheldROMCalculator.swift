// 907
//  HandheldROMCalculator.swift
//  FlexaSwiftUI
//
//  Created by Copilot on 10/6/25.
//
//  📐 ROM CALCULATION FOR HANDHELD GAMES
//  Converts 3D spatial trajectories to physiological ROM in degrees
//

import Foundation
import simd
import Combine

struct HandheldRepTrajectory: Sendable {
    let positions: [SIMD3<Float>]
    let timestamps: [TimeInterval]
}

/// Calculates Range of Motion from 3D position trajectories
final class HandheldROMCalculator: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var currentROM: Double = 0.0
    @Published private(set) var maxROM: Double = 0.0
    @Published private(set) var romPerRep: [Double] = []

    // MARK: - Motion Profile

    enum MotionProfile {
        case pendulum
        case circular
        case freeform
    }
    
    // MARK: - Private State
    
    private var motionProfile: MotionProfile = .pendulum
    private var armLength: Double { CalibrationDataManager.shared.currentCalibration?.armLength ?? 0.7 }
    private var arkitBaselinePosition: SIMD3<Float>? // Always set to first valid ARKit position
    private var positions: [SIMD3<Float>] = []
    private var timestamps: [TimeInterval] = []
    private var currentRepPositions: [SIMD3<Float>] = []
    private var currentRepTimestamps: [TimeInterval] = []
    private var currentRepArcLength: Double = 0.0
    private var currentCircularRadius: Double = 0.0
    private var currentRepMaxCircularRadius: Double = 0.0
    private var repTrajectories: [HandheldRepTrajectory] = []
    
    // MARK: - Circular Motion Tracking
    private var maxCircularRadius: Double = 0.0
    // `currentCircularRadius` is declared above for live tracking; avoid duplicate declaration
    private var circularMotionCenter: SIMD3<Double>?
    private var circularSampleCount: Int = 0
    
    // MARK: - Raw Position Validation
    private let minSegmentLength: Double = 0.001  // Minimum movement to count (very small, raw)
    private let minArcLength: Double = 0.08  // Minimum 8cm arc to be valid rep (reduce false small-movements)
    // No per-rep baseline needed; always use arkitBaselinePosition
    
    private let queue = DispatchQueue(label: "com.flexa.rom.calculator", qos: .userInitiated)
    private let segmentNoiseThreshold: Double = 0.0008
    private let directionSmoothing: Double = 0.12
    // Direction-change detection
    private var lastTangent: SIMD3<Float> = SIMD3<Float>(0,0,0)
    private var lastTangentSign: Int = 0
    private var smoothedTangentMagnitude: Double = 0.0
    private let directionHysteresisThreshold: Double = 0.06 // m/s threshold to avoid noise (tighter)
    private var lastDirectionChangeTimestamp: TimeInterval = 0
    
    var onROMUpdated: ((Double) -> Void)?
    var onRepROMRecorded: ((Double) -> Void)?
    var onRepDetected: ((_ repCount: Int, _ timestamp: TimeInterval) -> Void)?
    
    // MARK: - Public API
    
    func startSession(profile: MotionProfile = .pendulum) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.motionProfile = profile
            self.resetLocked()
            self.arkitBaselinePosition = nil // Reset baseline at session start
            FlexaLog.motion.debug("📐 [HandheldROM] Session started: profile=\(String(describing: profile)), arm=\(String(format: "%.2f", self.armLength))m")
        }
    }

    func configure(profile: MotionProfile) {
        queue.async { [weak self] in
            self?.motionProfile = profile
        }
    }
    
    func setReferencePosition(_ position: SIMD3<Float>) {
        queue.async { [weak self] in
            self?.arkitBaselinePosition = position
        }
    }
    
    func processPosition(_ position: SIMD3<Float>, timestamp: TimeInterval) {
        queue.async { [weak self] in
            guard let self = self else { return }

            // Always use first valid ARKit position as baseline
            if self.arkitBaselinePosition == nil {
                self.arkitBaselinePosition = position
            }
            guard let baseline = self.arkitBaselinePosition else { return }

            // Compute relative position to baseline (like FollowCircle)
            let relPosition = position - baseline

            self.positions.append(relPosition)
            self.timestamps.append(timestamp)
            self.currentRepPositions.append(relPosition)
            self.currentRepTimestamps.append(timestamp)

            if self.motionProfile == .circular {
                let currentDouble = SIMD3<Double>(Double(relPosition.x), Double(relPosition.y), Double(relPosition.z))
                if self.circularMotionCenter == nil {
                    self.circularMotionCenter = currentDouble
                    self.circularSampleCount = 1
                } else if var center = self.circularMotionCenter {
                    let sampleCount = Double(self.circularSampleCount)
                    center = (center * sampleCount + currentDouble) / (sampleCount + 1.0)
                    self.circularMotionCenter = center
                    self.circularSampleCount += 1
                    let radius = distance(currentDouble, center)
                    self.currentCircularRadius = radius
                    self.currentRepMaxCircularRadius = max(self.currentRepMaxCircularRadius, radius)
                    self.maxCircularRadius = max(self.maxCircularRadius, radius)
                }
            }

            if self.currentRepPositions.count >= 2 {
                let lastPos = self.currentRepPositions[self.currentRepPositions.count - 2]
                let segment = relPosition - lastPos
                let segmentLength = Double(length(segment))
                if segmentLength >= self.minSegmentLength {
                    self.currentRepArcLength += segmentLength
                }
            }

            // Direction-change detection for pendulum-like motions
            if self.motionProfile == .pendulum {
                // Compute tangent vector (current - previous) / dt
                if self.currentRepTimestamps.count >= 2 {
                    let i = self.currentRepTimestamps.count - 1
                    let dt = max(1e-3, self.currentRepTimestamps[i] - self.currentRepTimestamps[i-1])
                    let prev = self.currentRepPositions[i-1]
                    let curr = self.currentRepPositions[i]
                    let tangent = (curr - prev) / Float(dt)
                    let tangentMag = Double(length(tangent))
                    // EMA smoothing
                    self.smoothedTangentMagnitude = self.smoothedTangentMagnitude * (1.0 - self.directionSmoothing) + tangentMag * self.directionSmoothing
                    // Determine sign along dominant motion axis (use best projection plane)
                    let plane = self.findBestProjectionPlane(self.currentRepPositions)
                    let prev2D = self.projectTo2D(prev, plane: plane)
                    let curr2D = self.projectTo2D(curr, plane: plane)
                    let dx = Double(curr2D.x - prev2D.x)
                    let sign = dx > 0 ? 1 : (dx < 0 ? -1 : 0)

                    if self.lastTangentSign == 0 {
                        self.lastTangentSign = sign
                    } else if sign != 0 && sign != self.lastTangentSign {
                        // Potential direction reversal; confirm magnitude is above hysteresis
                        if self.smoothedTangentMagnitude >= self.directionHysteresisThreshold {
                            let now = Date().timeIntervalSince1970
                            // require some minimal arc since last rep to avoid chatter
                            if (now - self.lastDirectionChangeTimestamp) > 0.25 && self.currentRepArcLength >= self.minArcLength {
                                // Found a direction-change rep
                                self.lastDirectionChangeTimestamp = now
                                // Complete rep and reset live buffers
                                self.currentRepArcLength = max(self.currentRepArcLength, self.currentRepArcLength)
                                self.completeRep(timestamp: now)
                                // Notify about rep detection on main thread
                                DispatchQueue.main.async {
                                    self.onRepDetected?(1, now)
                                }
                            }
                            self.lastTangentSign = sign
                        }
                    }
                }
            }
            // ROM is only calculated at rep completion
        }
    }
    

    func completeRep(timestamp: TimeInterval) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let arcLength = self.calculateFinalArcLength()
            let repROM = self.calculateRepROM()
            
            // ROM calculation complete - silent during gameplay
            guard arcLength >= self.minArcLength else {
                self.currentRepPositions.removeAll()
                self.currentRepTimestamps.removeAll()
                self.currentRepArcLength = 0.0
                self.currentRepMaxCircularRadius = 0.0
                return
            }
            
            DispatchQueue.main.async {
                self.currentROM = repROM  // Update ROM once per rep (not live)
                self.romPerRep.append(repROM)
                if repROM > self.maxROM { self.maxROM = repROM }
                self.onRepROMRecorded?(repROM)
                self.onROMUpdated?(repROM)  // Notify once per rep
            }
            
            if !self.currentRepPositions.isEmpty {
                self.repTrajectories.append(HandheldRepTrajectory(positions: self.currentRepPositions, timestamps: self.currentRepTimestamps))
            }

            // ✅ CRITICAL FIX: Reset ALL baseline positions to prevent ROM accumulation
            self.currentRepPositions.removeAll()
            self.currentRepTimestamps.removeAll()
            self.currentRepArcLength = 0.0
            self.currentRepMaxCircularRadius = 0.0
            // Do not reset arkitBaselinePosition; keep for session
            
            // For circular motion, reset center tracking for next rep
            if self.motionProfile == .circular {
                self.circularMotionCenter = nil
                self.circularSampleCount = 0
            }

            DispatchQueue.main.async {
                self.currentROM = 0.0
                self.onROMUpdated?(0.0)
            }
        }
    }
    
    /// Calculate final arc length for completed rep using 2D projection
    private func calculateFinalArcLength() -> Double {
        guard currentRepPositions.count >= 2 else { return 0.0 }
        let bestPlane = findBestProjectionPlane(currentRepPositions)
        return calculateArcLengthOn2DPlane(currentRepPositions, plane: bestPlane)
    }
    
    func endSession() -> (avgROM: Double, maxROM: Double, romPerRep: [Double]) {
        return queue.sync {
            let avgROM = romPerRep.isEmpty ? 0 : romPerRep.reduce(0, +) / Double(romPerRep.count)
            FlexaLog.motion.debug("📐 [HandheldROM] Session ended: avgROM=\(String(format: "%.1f", avgROM))°, maxROM=\(String(format: "%.1f", self.maxROM))°")
            return (avgROM, maxROM, romPerRep)
        }
    }
    
    func reset() { queue.async { [weak self] in self?.resetLocked() } }
    func getRepTrajectories() -> [HandheldRepTrajectory] { queue.sync { repTrajectories } }
    
    /// Get the ROM value of the most recently completed rep
    func getLastRepROM() -> Double {
        return queue.sync { romPerRep.last ?? 0.0 }
    }
    
    /// Reset live ROM to zero immediately (for instant UI feedback between reps)
    func resetLiveROM() {
        queue.async { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.currentROM = 0.0
                self.onROMUpdated?(0.0)
            }
        }
    }
    
    // MARK: - ROM Calculation Methods
    
    private func calculateCurrentROM() -> Double {
        switch motionProfile {
        case .circular: return calculateROMFromRadius(currentCircularRadius)
        case .pendulum, .freeform: 
            // Real-time ROM from raw 3D arc (no 2D projection yet - that happens at rep end)
            return calculateROMFromArcLength(currentRepArcLength, projectTo2D: false)
        }
    }
    
    private func calculateRepROM() -> Double {
        switch motionProfile {
        case .circular:
            return calculateROMFromRadius(currentRepMaxCircularRadius)
        case .pendulum, .freeform:
            // At rep end: detect best plane from all rep positions using variance, then calculate final ROM
            guard currentRepPositions.count >= 2 else { return 0.0 }
            let bestPlane = findBestProjectionPlane(currentRepPositions)
            let finalArcLength = calculateArcLengthOn2DPlane(currentRepPositions, plane: bestPlane)
            return calculateROMFromArcLength(finalArcLength, projectTo2D: true, bestPlane: bestPlane)
        }
    }
    
    private func calculateROMFromArcLength(_ arcLength: Double, projectTo2D: Bool = false, bestPlane: ProjectionPlane = .xy) -> Double {
        guard armLength > 0 else { return 0.0 }
        let angle = (arcLength / armLength) * 180.0 / .pi
        // Add 3 degree rightward offset
        let offsetAngle = angle + 3.0
        // Clamp to a physiologically plausible maximum for a single rep
        // Most shoulder abduction ROMs should be <= 180 degrees; protect against runaway values
        let clamped = min(max(offsetAngle, 0.0), 180.0)
        if offsetAngle != clamped {
            FlexaLog.motion.warning("⚠️ [HandheldROM] Raw angle \(offsetAngle)° clamped to \(clamped)° to avoid anomaly (arcLength=\(String(format: "%.3f", arcLength)), arm=\(String(format: "%.2f", self.armLength))m)")
        }
        return clamped
    }
    
    private func calculateROMFromRadius(_ radius: Double) -> Double {
    guard armLength > 0 else { return 0.0 }
    let ratio = max(0.0, min(radius / armLength, 1.0))
    let angle = asin(ratio) * 180.0 / .pi
    // Add 3 degree rightward offset
    let offsetAngle = angle + 3.0
    return min(max(offsetAngle, 0.0), 90.0)
    }

    /// Calculate arc length on a specific 2D plane
    /// If PCA mapping is available, prefer PCA projection for more accurate planar mapping.
    private func calculateArcLengthOn2DPlane(_ positions: [SIMD3<Float>], plane: ProjectionPlane) -> Double {
        guard positions.count >= 2 else { return 0.0 }
        
        // Attempt PCA mapping for more robust projection
        if let mapper = pca2DMapper(for: positions) {
            // Map to double precision 2D for stability, then compute arc-length with outlier filtering
            var pts2D: [SIMD2<Double>] = positions.map { mapper($0) }
            // Outlier removal: median filter on distances
            if pts2D.count >= 5 {
                let window = 3
                var filtered: [SIMD2<Double>] = []
                for i in 0..<pts2D.count {
                    let start = max(0, i - window)
                    let end = min(pts2D.count - 1, i + window)
                    let subset = pts2D[start...end]
                    // median of x and y separately
                    let xs = subset.map { $0.x }.sorted()
                    let ys = subset.map { $0.y }.sorted()
                    filtered.append(SIMD2<Double>(xs[xs.count/2], ys[ys.count/2]))
                }
                pts2D = filtered
            }

            // Compute robust arc-length with segment noise threshold (in meters)
            var total: Double = 0.0
            for i in 1..<pts2D.count {
                let dx = pts2D[i].x - pts2D[i-1].x
                let dy = pts2D[i].y - pts2D[i-1].y
                let segment = sqrt(dx*dx + dy*dy)
                if segment >= segmentNoiseThreshold {
                    total += segment
                }
            }
            return total
        }

        // Fallback to axis projection
        let positions2D = positions.map { pos in
            projectTo2D(pos, plane: plane)
        }
        
        var total: Double = 0.0
        for i in 1..<positions2D.count {
            let segmentLength = Double(distance(positions2D[i], positions2D[i-1]))
            if segmentLength >= segmentNoiseThreshold { total += segmentLength }
        }
        return total
    }
    
    private func arcLength(for positions: [SIMD3<Float>]) -> Double {
        guard positions.count >= 2 else { return 0.0 }
        var total: Double = 0.0
        for i in 1..<positions.count {
            let segmentLength = Double(distance(positions[i], positions[i-1]))
            if segmentLength >= segmentNoiseThreshold { total += segmentLength }
        }
        return total
    }
    
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
    
    /// Smoothed plane selection to prevent sudden axis switches and arc length spikes
    private var previousPlane: ProjectionPlane = .xy
    private var planeSwitchCounter: Int = 0
    private let planeSwitchThreshold: Int = 5 // Require 5 consecutive frames before switching (reduce jitter)
    private func findBestProjectionPlane(_ positions: [SIMD3<Float>]) -> ProjectionPlane {
        guard positions.count >= 2 else { return previousPlane }

        // Calculate mean for each axis
        let meanX = positions.reduce(0.0) { $0 + Double($1.x) } / Double(positions.count)
        let meanY = positions.reduce(0.0) { $0 + Double($1.y) } / Double(positions.count)
        let meanZ = positions.reduce(0.0) { $0 + Double($1.z) } / Double(positions.count)

        // Calculate variance for each axis
        let varX = positions.reduce(0.0) { $0 + pow(Double($1.x) - meanX, 2) } / Double(positions.count)
        let varY = positions.reduce(0.0) { $0 + pow(Double($1.y) - meanY, 2) } / Double(positions.count)
        let varZ = positions.reduce(0.0) { $0 + pow(Double($1.z) - meanZ, 2) } / Double(positions.count)

        // Sort by variance - highest variance = most motion
        let variances = [(varX, "X"), (varY, "Y"), (varZ, "Z")]
        let sorted = variances.sorted { $0.0 > $1.0 }

        let axis1 = sorted[0].1  // Highest variance axis
        let axis2 = sorted[1].1  // Second highest variance axis

        var candidatePlane: ProjectionPlane = .xy
        if (axis1 == "X" && axis2 == "Y") || (axis1 == "Y" && axis2 == "X") {
            candidatePlane = .xy
        } else if (axis1 == "X" && axis2 == "Z") || (axis1 == "Z" && axis2 == "X") {
            candidatePlane = .xz
        } else {
            candidatePlane = .yz
        }

        // Smoothed switching: only switch if candidate is dominant for several frames
        if candidatePlane != previousPlane {
            planeSwitchCounter += 1
            if planeSwitchCounter >= planeSwitchThreshold {
                FlexaLog.motion.info("📐 [HandheldROM] Plane switched from \(self.previousPlane) to \(candidatePlane) after \(self.planeSwitchCounter) consecutive frames.")
                previousPlane = candidatePlane
                planeSwitchCounter = 0
            } else {
                // Log attempted switch for diagnostics
                FlexaLog.motion.debug("📐 [HandheldROM] Plane switch attempt: \(self.previousPlane) → \(candidatePlane) (\(self.planeSwitchCounter)/\(self.planeSwitchThreshold))")
            }
        } else {
            planeSwitchCounter = 0
        }
        return previousPlane
    }
    
    /// PCA-based projection: compute principal axes for the positions and project 3D to 2D
    /// We cache the last principal axes to smooth across frames and prevent jitter.
    private var lastPrincipalX: SIMD3<Double>? = nil
    private var lastPrincipalY: SIMD3<Double>? = nil
    private let principalSmoothingAlpha: Double = 0.12

    private func projectTo2D(_ pos: SIMD3<Float>, plane: ProjectionPlane) -> SIMD2<Float> {
        // If a historical PCA basis exists, use it mapped to XY/XZ/YZ planes as before
        switch plane {
        case .xy: return SIMD2<Float>(pos.x, pos.y)
        case .xz: return SIMD2<Float>(pos.x, pos.z)
        case .yz: return SIMD2<Float>(pos.y, pos.z)
        }
    }

    /// Robust PCA projection that generates a 2D coordinate frame (pc1, pc2) for the given positions.
    /// Returns a function that maps 3D SIMD3<Float> to 2D SIMD2<Float]. This is used only inside
    /// calculateArcLengthOn2DPlane when passing PCA-based best plane (not the enum).
    private func pca2DMapper(for positions: [SIMD3<Float>]) -> ((SIMD3<Float>) -> SIMD2<Double>)? {
        guard positions.count >= 3 else { return nil }
        let pts = positions.map { SIMD3<Double>(Double($0.x), Double($0.y), Double($0.z)) }
        let centroid = pts.reduce(SIMD3<Double>(0,0,0), { $0 + $1 }) / Double(pts.count)

        // Build covariance
        var cov = simd_double3x3(rows: [SIMD3<Double>(0,0,0), SIMD3<Double>(0,0,0), SIMD3<Double>(0,0,0)])
        for p in pts {
            let d = p - centroid
            cov.columns.0 += SIMD3<Double>(d.x * d.x, d.y * d.x, d.z * d.x)
            cov.columns.1 += SIMD3<Double>(d.x * d.y, d.y * d.y, d.z * d.y)
            cov.columns.2 += SIMD3<Double>(d.x * d.z, d.y * d.z, d.z * d.z)
        }
    let invCount = 1.0 / Double(pts.count)
    cov.columns.0 *= invCount
    cov.columns.1 *= invCount
    cov.columns.2 *= invCount

        // Use SVD via simd to extract principal components
        // Note: simd doesn't export SVD; we approximate using eigenvectors via power iteration for the top two
        func dominantEigenvector(of m: simd_double3x3) -> SIMD3<Double> {
            var v = SIMD3<Double>(0.6, 0.3, 0.1)
            for _ in 0..<12 {
                let mv = m * v
                let mag = sqrt(mv.x*mv.x + mv.y*mv.y + mv.z*mv.z) + 1e-12
                v = mv / mag
            }
            return normalizeOrFail(v)
        }

        let e1 = dominantEigenvector(of: cov)
        // Deflate to find second eigenvector
        let lambda1Vec = simd_double3x3(rows: [e1 * dot(e1, cov.columns.0), e1 * dot(e1, cov.columns.1), e1 * dot(e1, cov.columns.2)])
        let cov2 = cov - lambda1Vec
        let e2 = dominantEigenvector(of: cov2)
        let e2Ortho = normalizeOrFail(e2 - e1 * dot(e1, e2))

        // Smooth principal axes
        if let lastX = lastPrincipalX, let lastY = lastPrincipalY {
            let blendedX = lastX * (1.0 - principalSmoothingAlpha) + e1 * principalSmoothingAlpha
            let blendedY = lastY * (1.0 - principalSmoothingAlpha) + e2Ortho * principalSmoothingAlpha
            lastPrincipalX = normalizeOrFail(blendedX)
            lastPrincipalY = normalizeOrFail(blendedY)
        } else {
            lastPrincipalX = e1
            lastPrincipalY = e2Ortho
        }

        guard let pcx = lastPrincipalX, let pcy = lastPrincipalY else { return nil }

        return { (p3: SIMD3<Float>) -> SIMD2<Double> in
            let pd = SIMD3<Double>(Double(p3.x), Double(p3.y), Double(p3.z)) - centroid
            return SIMD2<Double>(dot(pd, pcx), dot(pd, pcy))
        }
    }

    private func normalizeOrFail(_ v: SIMD3<Double>) -> SIMD3<Double> {
        let mag = sqrt(v.x*v.x + v.y*v.y + v.z*v.z)
        guard mag > 1e-12 else { return SIMD3<Double>(1, 0, 0) }
        return v / mag
    }


    private func resetLocked() {
        DispatchQueue.main.async {
            self.currentROM = 0.0
            self.maxROM = 0.0
            self.romPerRep.removeAll()
        }
    arkitBaselinePosition = nil
        positions.removeAll()
        timestamps.removeAll()
        currentRepPositions.removeAll()
        currentRepTimestamps.removeAll()
        currentRepArcLength = 0.0
        repTrajectories.removeAll()
        maxCircularRadius = 0.0
        currentRepMaxCircularRadius = 0.0
        currentCircularRadius = 0.0
        circularMotionCenter = nil
        circularSampleCount = 0
        FlexaLog.motion.debug("📐 [HandheldROM] State reset")
    }

    /// Public API to reset the live ROM without clearing recorded rep history.
    /// Useful to immediately clear the live UI value when a rep is detected.
    private func resetLiveROMLocked() {
        // Reset the current live rep buffers but keep historical rep data
        self.currentRepPositions.removeAll()
        self.currentRepTimestamps.removeAll()
        self.currentRepArcLength = 0.0
        self.currentRepMaxCircularRadius = 0.0
    // legacy baseline variables removed; no-op

        DispatchQueue.main.async {
            self.currentROM = 0.0
            self.onROMUpdated?(0.0)
        }
        FlexaLog.motion.debug("📐 [HandheldROM] Live ROM reset via resetLiveROM()")
    }

    func getLiveROMEstimate() -> Double {
        return queue.sync {
            return self.calculateCurrentROM()
        }
    }
}
