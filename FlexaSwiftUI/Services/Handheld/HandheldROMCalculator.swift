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
    private var referencePosition: SIMD3<Float>?
    private var baselinePosition: SIMD3<Float>?
    private var positions: [SIMD3<Float>] = []
    private var timestamps: [TimeInterval] = []
    private var currentRepPositions: [SIMD3<Float>] = []
    private var currentRepTimestamps: [TimeInterval] = []
    private var currentRepStartTime: TimeInterval = 0
    private var currentRepArcLength: Double = 0.0
    private var currentRepDirection: simd_double3?
    private var repTrajectories: [HandheldRepTrajectory] = []
    
    // MARK: - Circular Motion Tracking
    private var maxCircularRadius: Double = 0.0
    private var currentRepMaxCircularRadius: Double = 0.0
    private var currentCircularRadius: Double = 0.0
    private var circularMotionCenter: SIMD3<Double>?
    private var circularSampleCount: Int = 0
    
    // MARK: - Raw Position Validation
    private let minSegmentLength: Double = 0.001  // Minimum movement to count (very small, raw)
    private let minArcLength: Double = 0.05  // Minimum 5cm arc to be valid rep
    private var repBaselinePosition: SIMD3<Float>?  // Baseline at rep START
    
    private let queue = DispatchQueue(label: "com.flexa.rom.calculator", qos: .userInitiated)
    private let segmentNoiseThreshold: Double = 0.0008
    private let directionSmoothing: Double = 0.12
    
    var onROMUpdated: ((Double) -> Void)?
    var onRepROMRecorded: ((Double) -> Void)?
    
    // MARK: - Public API
    
    func startSession(profile: MotionProfile = .pendulum) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.motionProfile = profile
            self.resetLocked()
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
            self?.referencePosition = position
            self?.baselinePosition = position
        }
    }
    
    func processPosition(_ position: SIMD3<Float>, timestamp: TimeInterval) {
        queue.async { [weak self] in
            guard let self = self else { return }

            self.positions.append(position)
            self.timestamps.append(timestamp)
            self.currentRepPositions.append(position)
            self.currentRepTimestamps.append(timestamp)

            if self.baselinePosition == nil { 
                self.baselinePosition = position
                self.repBaselinePosition = position
            }

            if self.motionProfile == .circular {
                let currentDouble = SIMD3<Double>(Double(position.x), Double(position.y), Double(position.z))
                if self.circularMotionCenter == nil { 
                    self.circularMotionCenter = currentDouble
                    self.circularSampleCount = 1 
                }
                else if var center = self.circularMotionCenter {
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
                // Use raw positions - no filtering
                let lastPos = self.currentRepPositions[self.currentRepPositions.count - 2]
                let segment = position - lastPos
                let segmentLength = Double(length(segment))
                
                if segmentLength >= self.minSegmentLength {
                    self.currentRepArcLength += segmentLength
                }
            }
            
            let rom = self.calculateCurrentROM()
            
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.currentROM = rom
                if rom > self.maxROM { self.maxROM = rom }
                self.onROMUpdated?(rom)
            }
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
                self.romPerRep.append(repROM)
                if repROM > self.maxROM { self.maxROM = repROM }
                self.onRepROMRecorded?(repROM)
            }
            
            if !self.currentRepPositions.isEmpty {
                self.repTrajectories.append(HandheldRepTrajectory(positions: self.currentRepPositions, timestamps: self.currentRepTimestamps))
            }

            // ✅ CRITICAL FIX: Reset ALL baseline positions to prevent ROM accumulation
            self.currentRepPositions.removeAll()
            self.currentRepTimestamps.removeAll()
            self.currentRepArcLength = 0.0
            self.currentRepMaxCircularRadius = 0.0
            self.repBaselinePosition = nil
            self.baselinePosition = nil  // Reset global baseline
            
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
        return min(max(angle, 0.0), 360.0)
    }
    
    private func calculateROMFromRadius(_ radius: Double) -> Double {
        guard armLength > 0 else { return 0.0 }
        let ratio = max(0.0, min(radius / armLength, 1.0))
        let angle = asin(ratio) * 180.0 / .pi
        return min(max(angle, 0.0), 90.0)
    }

    /// Calculate arc length on a specific 2D plane
    private func calculateArcLengthOn2DPlane(_ positions: [SIMD3<Float>], plane: ProjectionPlane) -> Double {
        guard positions.count >= 2 else { return 0.0 }
        
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
    
    /// Find best 2D plane by analyzing motion variance across axes
    /// Uses variance instead of range to better capture motion distribution
    private func findBestProjectionPlane(_ positions: [SIMD3<Float>]) -> ProjectionPlane {
        guard positions.count >= 2 else { return .xy }
        
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
        
        if (axis1 == "X" && axis2 == "Y") || (axis1 == "Y" && axis2 == "X") {
            return .xy
        } else if (axis1 == "X" && axis2 == "Z") || (axis1 == "Z" && axis2 == "X") {
            return .xz
        } else {
            return .yz
        }
    }
    
    /// Project 3D position to 2D based on chosen plane
    private func projectTo2D(_ pos: SIMD3<Float>, plane: ProjectionPlane) -> SIMD2<Float> {
        switch plane {
        case .xy: return SIMD2<Float>(pos.x, pos.y)
        case .xz: return SIMD2<Float>(pos.x, pos.z)
        case .yz: return SIMD2<Float>(pos.y, pos.z)
        }
    }

    private func resetLocked() {
        DispatchQueue.main.async {
            self.currentROM = 0.0
            self.maxROM = 0.0
            self.romPerRep.removeAll()
        }
        referencePosition = nil
        baselinePosition = nil
        repBaselinePosition = nil
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
}
