//
//
//  IMUDirectionRepDetector.swift
//  FlexaSwiftUI
//
//  Simple velocity-based rep detection using acceleration integration
//

import Foundation
import CoreMotion

/// Simple rep detector: integrate 3D acceleration (gravity removed) to get velocity, detect sign changes
///
/// DEPRECATION NOTE: This class is a rep detector only. IMU-derived ROM is deprecated across the
/// system — ROM values are now computed exclusively via ARKit in `HandheldROMCalculator`.
/// Keep this detector for low-latency rep detection and diagnostics only.
class IMUDirectionRepDetector {

    /// Allow callers to silence high-frequency IMU debug traces while keeping
    /// essential startup/info messages and rep-detection callbacks.
    /// For example, FruitSlicer sets this to false to avoid console spam.
    var verboseLoggingEnabled: Bool = true

    
    // MARK: - State
    private var currentReps: Int = 0
    private var lastRepTimestamp: TimeInterval = 0
    
    // Simple thresholds
    private let cooldownPeriod: TimeInterval = 0.3  // seconds between reps
    private let velocityThreshold: Double = 0.1     // m/s - base threshold for movement
    private let peakActivationMultiplier: Double = 1.8
    private let valleyThresholdMultiplier: Double = 0.3
    private let strictPeakValidation: Double = 1.98
    private let directionChangeDotThreshold: Double = -0.2 // <= -0.2 indicates clear reversal
    
    // Velocity integration state
    private var velocity3D: SIMD3<Double> = SIMD3<Double>(0, 0, 0)
    private var lastTimestamp: TimeInterval = 0
    private var lastVelocitySign: Int = 0  // -1, 0, or 1
    private var lastVelocityVector: SIMD3<Double> = SIMD3<Double>(0, 0, 0)
    
    // Hysteresis peak tracking
    private var isPeakActive: Bool = false
    private var peakMagnitude: Double = 0
    private var lastForwardMagnitude: Double = 0
    
    // Gravity calibration
    private var gravityVector: SIMD3<Double>?
    private var calibrationSamples: [SIMD3<Double>] = []
    private let calibrationSampleCount = 30
    
    var onRepDetected: ((Int, TimeInterval) -> Void)?
    var romProvider: (() -> Double)?
    
    // MARK: - Public API
    
    func startSession(axis: IMUDirectionRepDetector.Axis = .y) {
        reset()
        if verboseLoggingEnabled {
            FlexaLog.motion.info("⚡️ [IMURep] Started simple velocity integration rep detection")
        } else {
            // Keep a minimal info log for non-verbose modes so callers can
            // still detect that the detector started if needed.
            FlexaLog.motion.debug("⚡️ [IMURep] Detector started (minimal logging)")
        }
    }
    
    func stopSession() {
        reset()
    }
    
    func resetState() {
        reset()
    }
    
    private func reset() {
        currentReps = 0
        lastRepTimestamp = 0
        velocity3D = SIMD3<Double>(0, 0, 0)
        lastTimestamp = 0
        lastVelocitySign = 0
        gravityVector = nil
        calibrationSamples.removeAll()
    }
    
    // MARK: - Processing
    
    func processDeviceMotion(_ motion: CMDeviceMotion, timestamp: TimeInterval) {
        // Get gravity vector from CoreMotion (already calibrated)
        let gravity = SIMD3<Double>(
            motion.gravity.x,
            motion.gravity.y,
            motion.gravity.z
        )
        
        // Calibrate gravity if needed (use CoreMotion's gravity for initial samples)
        if gravityVector == nil {
            calibrationSamples.append(gravity)
            if calibrationSamples.count >= calibrationSampleCount {
                // Average all samples to get stable gravity vector
                let sum = calibrationSamples.reduce(SIMD3<Double>(0, 0, 0), +)
                let avgGravity = sum / Double(calibrationSampleCount)
                gravityVector = avgGravity
                FlexaLog.motion.info("🎯 [IMURep] Gravity calibrated: \(String(format: "%.3f, %.3f, %.3f", avgGravity.x, avgGravity.y, avgGravity.z))")
            }
            return
        }
        
        // Get user acceleration (CoreMotion already removes gravity)
        let userAccel = SIMD3<Double>(
            motion.userAcceleration.x,
            motion.userAcceleration.y,
            motion.userAcceleration.z
        )
        
        // Integrate acceleration to get velocity
        if lastTimestamp > 0 {
            let dt = timestamp - lastTimestamp
            if dt > 0 && dt < 0.5 {  // Sanity check
                velocity3D += userAccel * dt
                
                // Apply damping to prevent drift
                velocity3D *= 0.95
                
                // Use primary axis (Y) for direction and forward magnitude
                let forwardMagnitude = abs(velocity3D.y)
                let currentSign = velocity3D.y > 0 ? 1 : -1
                let threshold = velocityThreshold

                if !isPeakActive {
                    // Look for significant peak to activate
                    if forwardMagnitude >= max(threshold * peakActivationMultiplier, threshold) {
                        isPeakActive = true
                        peakMagnitude = forwardMagnitude
                        if verboseLoggingEnabled {
                            FlexaLog.motion.debug("⚡️ [IMURep] Peak activated: mag=\(String(format: "%.4f", forwardMagnitude)) m/s")
                        }
                    }
                } else {
                    // Track peak magnitude while active
                    if forwardMagnitude > peakMagnitude { peakMagnitude = forwardMagnitude }

                    // Check for direction reversal through a valley
                    let magnitudeDecreasing = forwardMagnitude < lastForwardMagnitude
                    var dirReversed = false
                    let lastVec = lastVelocityVector
                    let lastLen = sqrt(lastVec.x*lastVec.x + lastVec.y*lastVec.y + lastVec.z*lastVec.z)
                    let currLen = sqrt(velocity3D.x*velocity3D.x + velocity3D.y*velocity3D.y + velocity3D.z*velocity3D.z)
                    if lastLen > 1e-6 && currLen > 1e-6 {
                        let dotVal = (lastVec.x*velocity3D.x + lastVec.y*velocity3D.y + lastVec.z*velocity3D.z) / (lastLen * currLen)
                        dirReversed = dotVal <= directionChangeDotThreshold
                    }
                    // Also consider explicit axis sign change as reversal
                    if !dirReversed && lastVelocitySign != 0 && currentSign != lastVelocitySign { dirReversed = true }

                    if magnitudeDecreasing && forwardMagnitude < threshold * valleyThresholdMultiplier && dirReversed {
                                if peakMagnitude >= threshold * strictPeakValidation {
                            if timestamp - lastRepTimestamp > cooldownPeriod {
                                self.currentReps += 1
                                self.lastRepTimestamp = timestamp
                                self.onRepDetected?(self.currentReps, timestamp)
                                // Always emit a concise rep-detected info line regardless of
                                // verboseLoggingEnabled so callers (and the UI) can react.
                                FlexaLog.motion.info("✅ [IMURep] Rep #\(self.currentReps) detected")
                            } else {
                                if verboseLoggingEnabled {
                                    FlexaLog.motion.debug("⏳ [IMURep] Peak valid but in cooldown")
                                }
                            }
                        } else {
                            if verboseLoggingEnabled {
                                FlexaLog.motion.debug("🫥 [IMURep] Peak too small: \(String(format: "%.4f", self.peakMagnitude)) m/s (need \(String(format: "%.4f", threshold * self.strictPeakValidation)) m/s)")
                            }
                        }
                        // Reset hysteresis for next cycle
                        isPeakActive = false
                        peakMagnitude = 0
                    }
                }

                // Update tracking state for next sample
                lastForwardMagnitude = forwardMagnitude
                lastVelocitySign = currentSign
                lastVelocityVector = velocity3D
            }
        }
        
        lastTimestamp = timestamp
    }
    
    // MARK: - Axis enum (for compatibility)
    enum Axis {
        case x, y, z
    }
}
