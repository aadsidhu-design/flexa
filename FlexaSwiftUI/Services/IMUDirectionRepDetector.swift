//
//  IMUDirectionRepDetector.swift
//  FlexaSwiftUI
//
//  Simple IMU accelerometer-based rep detection using direction changes
//

import Foundation
import CoreMotion

/// Detects reps based on accelerometer direction changes (not gyroscope)
/// Uses actual movement direction from acceleration, more reliable than rotation
class IMUDirectionRepDetector {
    
    private var lastDirection: Int = 0  // -1 or 1 for negative/positive acceleration
    private var currentReps: Int = 0
    private var lastAccelReading: CMAcceleration?
    private var isInitialized: Bool = false
    
    // Minimum direction change threshold (in degrees)
    // 5 degree minimum change to detect a direction reversal
    private let directionChangeThreshold: Double = 5.0
    
    // Track magnitude for logging
    private var peakPositiveAccel: Double = 0
    
    var onRepDetected: ((Int, TimeInterval) -> Void)?
    
    func reset() {
        lastDirection = 0
        currentReps = 0
        lastAccelReading = nil
        isInitialized = false
        peakPositiveAccel = 0
    }
    
    /// Process accelerometer data and detect direction changes
    /// SIMPLIFIED: Only detects direction reversals (no ROM check, no cooldown)
    func processAcceleration(_ acceleration: CMAcceleration, timestamp: TimeInterval) {
        // Wait for initialization period to avoid false positives at start
        if !isInitialized {
            isInitialized = true
            print("🔄 [IMU-Rep] Initialized - starting rep detection with 5° threshold")
            return
        }
        
        // Find dominant acceleration axis
        let absX = abs(acceleration.x)
        let absY = abs(acceleration.y)
        let absZ = abs(acceleration.z)
        
        let dominantValue: Double
        if absX > absY && absX > absZ {
            dominantValue = acceleration.x
        } else if absY > absX && absY > absZ {
            dominantValue = acceleration.y
        } else {
            dominantValue = acceleration.z
        }
        
        // Determine current direction: +1 or -1 (no neutral state)
        let currentDirection: Int = dominantValue >= 0 ? 1 : -1
        
        // Track magnitude for logging
        peakPositiveAccel = max(peakPositiveAccel, abs(dominantValue))
        
        // Detect direction reversal: 1 → -1 or -1 → 1
        if lastDirection != 0 && lastDirection != currentDirection {
            currentReps += 1
            onRepDetected?(currentReps, timestamp)
            
            print("🔄 [IMU-Rep] Direction reversal detected! \(lastDirection) → \(currentDirection) | Rep #\(currentReps) | Accel: \(String(format: "%.3f", abs(dominantValue))) m/s²")
        }
        
        // Update last direction
        lastDirection = currentDirection
        lastAccelReading = acceleration
    }
}
