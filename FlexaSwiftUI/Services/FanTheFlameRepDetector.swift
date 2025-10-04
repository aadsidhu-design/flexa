//
//  FanTheFlameRepDetector.swift
//  FlexaSwiftUI
//
//  Created by Copilot on 10/2/25.
//  Fan the Flame rep detection using IMU gyroscope direction changes
//

import Foundation
import CoreMotion
import Combine

/// Direction-change based rep detection for Fan the Flame game
/// Uses IMU gyroscope (rotation rate) to detect left and right swings
/// Each direction change = 1 rep (left swing = rep, right swing = rep)
class FanTheFlameRepDetector: ObservableObject {
    
    // MARK: - Published Properties
    @Published var currentReps: Int = 0
    @Published var lastSwingDirection: SwingDirection = .none
    @Published var currentAngularVelocity: Double = 0.0
    
    // MARK: - Swing Direction
    enum SwingDirection {
        case left       // Negative angular velocity (counter-clockwise)
        case right      // Positive angular velocity (clockwise)
        case none       // No movement or below threshold
        
        var description: String {
            switch self {
            case .left: return "←"
            case .right: return "→"
            case .none: return "•"
            }
        }
    }
    
    // MARK: - Configuration
    
    /// Minimum angular velocity to consider as deliberate movement (rad/s)
    /// ~0.8 rad/s ≈ 45 degrees/second - requires moderate deliberate swing
    private let minAngularVelocityThreshold: Double = 0.8
    
    /// Peak decay threshold - velocity must drop below this to reset for next swing
    /// Prevents counting multiple reps from one continuous movement
    private let peakDecayThreshold: Double = 0.3
    
    /// Smoothing factor for angular velocity (exponential moving average)
    /// Higher = more responsive but noisier, lower = smoother but laggier
    private let smoothingAlpha: Double = 0.35

    /// Window size for additional averaging to tame gyro jitter
    private let angularVelocityWindowSize = 5
    
    // MARK: - State Tracking
    private var smoothedAngularVelocity: Double = 0.0
    private var lastPeakVelocity: Double = 0.0
    private var lastPeakDirection: SwingDirection = .none
    private var isInPeak: Bool = false
    private var consecutiveFramesAboveThreshold: Int = 0
    private let minConsecutiveFrames: Int = 3 // Must sustain velocity for 3 frames
    private var lastRepDirection: SwingDirection = .none
    private var angularVelocityWindow: [Double] = []
    
    // Callback fired when rep detected: (repCount, direction, peakVelocity)
    var onRepDetected: ((Int, SwingDirection, Double) -> Void)?
    
    // MARK: - Initialization
    init() {
        FlexaLog.motion.info("🎯 [FanFlameDetector] Initialized with:")
        FlexaLog.motion.info("  minAngularVelocity: \(String(format: "%.2f", self.minAngularVelocityThreshold)) rad/s (~\(Int(self.minAngularVelocityThreshold * 57.3))°/s)")
        FlexaLog.motion.info("  peakDecayThreshold: \(String(format: "%.2f", self.peakDecayThreshold)) rad/s")
    }
    
    // MARK: - Rep Detection Logic
    
    /// Process device motion update to detect swings
    /// Call this from CMMotionManager updates (typically 60Hz)
    func processMotion(_ motion: CMDeviceMotion) {
        // Extract yaw rotation rate (Z-axis - rotation around vertical)
        // Positive = clockwise (right swing), Negative = counter-clockwise (left swing)
        let rawAngularVelocity = motion.rotationRate.z

        angularVelocityWindow.append(rawAngularVelocity)
        if angularVelocityWindow.count > angularVelocityWindowSize {
            angularVelocityWindow.removeFirst()
        }
        let windowAveragedVelocity = angularVelocityWindow.reduce(0.0, +) / Double(angularVelocityWindow.count)
        
        // Apply exponential smoothing to reduce noise
        if smoothedAngularVelocity == 0.0 {
            smoothedAngularVelocity = windowAveragedVelocity
        } else {
            smoothedAngularVelocity = (smoothingAlpha * windowAveragedVelocity) + ((1.0 - smoothingAlpha) * smoothedAngularVelocity)
        }
        
        // Update published velocity for UI
        DispatchQueue.main.async { [weak self] in
            self?.currentAngularVelocity = self?.smoothedAngularVelocity ?? 0.0
        }
        
        // Determine current swing direction
        let magnitude = abs(smoothedAngularVelocity)
        let currentDirection: SwingDirection = {
            if magnitude < minAngularVelocityThreshold {
                return .none
            }
            return smoothedAngularVelocity > 0 ? .right : .left
        }()
        
        // Track consecutive frames above threshold (prevents jitter)
        if magnitude >= minAngularVelocityThreshold {
            consecutiveFramesAboveThreshold += 1
        } else {
            consecutiveFramesAboveThreshold = 0
        }
        
        // PEAK DETECTION STATE MACHINE
        
        if !isInPeak {
            // NOT IN PEAK: Look for start of deliberate movement
            
            // Require sustained velocity above threshold
            guard consecutiveFramesAboveThreshold >= minConsecutiveFrames else { return }
            guard currentDirection != .none else { return }
            
            // Starting a new peak
            isInPeak = true
            lastPeakVelocity = magnitude
            lastPeakDirection = currentDirection
            
            FlexaLog.motion.debug("🔄 [FanFlameDetector] Peak started: \(currentDirection.description) vel=\(String(format: "%.2f", self.smoothedAngularVelocity))")
            
        } else {
            // IN PEAK: Track peak and detect when it ends
            
            // Update peak if velocity is higher in SAME direction
            if currentDirection == lastPeakDirection && magnitude > lastPeakVelocity {
                lastPeakVelocity = magnitude
                FlexaLog.motion.debug("🔄 [FanFlameDetector] Peak updated: \(String(format: "%.2f", self.lastPeakVelocity))")
            }
            
            // Check for direction change or velocity drop (end of swing)
            let hasDirectionChanged = (currentDirection != .none && currentDirection != lastPeakDirection)
            let hasVelocityDecayed = magnitude < peakDecayThreshold
            let hasValidDirectionChange = hasDirectionChanged && lastPeakDirection != .none && lastRepDirection != lastPeakDirection
            
            if hasDirectionChanged || hasVelocityDecayed {
                // PEAK ENDED - Check if this was a valid rep
                if hasValidDirectionChange && lastPeakVelocity >= minAngularVelocityThreshold {
                    // VALID REP DETECTED!
                    currentReps += 1
                    lastRepDirection = lastPeakDirection
                    
                    FlexaLog.motion.info("✅ [FanFlameDetector] Rep #\(self.currentReps) detected! Direction: \(self.lastPeakDirection.description), Peak velocity: \(String(format: "%.2f", self.lastPeakVelocity)) rad/s")
                    
                    // Update UI
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.lastSwingDirection = self.lastPeakDirection
                    }
                    
                    // Fire callback
                    onRepDetected?(currentReps, lastPeakDirection, lastPeakVelocity)
                    
                } else {
                    let reason: String
                    if !hasValidDirectionChange {
                        reason = "no direction change"
                    } else {
                        reason = "below threshold"
                    }
                    FlexaLog.motion.debug("❌ [FanFlameDetector] Peak rejected: \(reason)")
                }
                
                // Reset peak state
                isInPeak = false
                lastPeakVelocity = 0.0
                consecutiveFramesAboveThreshold = 0
            }
        }
    }
    
    // MARK: - Session Management
    
    /// Reset detector state for new game session
    func reset() {
        currentReps = 0
        lastSwingDirection = .none
        currentAngularVelocity = 0.0
        smoothedAngularVelocity = 0.0
        lastPeakVelocity = 0.0
        lastPeakDirection = .none
        isInPeak = false
        consecutiveFramesAboveThreshold = 0
        lastRepDirection = .none
        angularVelocityWindow.removeAll(keepingCapacity: false)
        
        FlexaLog.motion.info("🔄 [FanFlameDetector] Reset for new session")
    }
    
    // MARK: - Diagnostics
    
    /// Get human-readable state description for debugging
    func getStateDescription() -> String {
        let directionIcon = lastSwingDirection.description
        let velocityStr = String(format: "%.2f", currentAngularVelocity)
        let peakStr = isInPeak ? "🔴 IN PEAK" : "⚪ IDLE"
        
        return "\(directionIcon) \(velocityStr) rad/s | \(peakStr) | Reps: \(currentReps)"
    }
}
