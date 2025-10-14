//
//  IMUDirectionRepDetector.swift
//  FlexaSwiftUI
//
//  Simple IMU gyroscope-based rep detection using direction changes
//

import Foundation
import CoreMotion

/// Detects reps based purely on IMU gyroscope direction changes
/// No thresholds, no cooldowns - just raw direction reversals
class IMUDirectionRepDetector {
    
    private var lastDirection: Int = 0  // -1 = left/down, 0 = neutral, 1 = right/up
    private var currentReps: Int = 0
    private var lastGyroReading: CMRotationRate?
    private let directionChangeThreshold: Double = 0.087  // ~5 degrees/second in radians
    
    var onRepDetected: ((Int, TimeInterval) -> Void)?
    
    func reset() {
        lastDirection = 0
        currentReps = 0
        lastGyroReading = nil
    }
    
    /// Process gyroscope data and detect direction changes
    func processGyro(_ rotationRate: CMRotationRate, timestamp: TimeInterval) {
        // For pendulum swings (Fruit Slicer, Fan Out Flame):
        // Use the dominant rotation axis (usually Y for side-to-side, X for forward-back)
        
        // Find dominant axis
        let absX = abs(rotationRate.x)
        let absY = abs(rotationRate.y)
        let absZ = abs(rotationRate.z)
        
        let dominantValue: Double
        if absX > absY && absX > absZ {
            dominantValue = rotationRate.x
        } else if absY > absX && absY > absZ {
            dominantValue = rotationRate.y
        } else {
            dominantValue = rotationRate.z
        }
        
        // Determine current direction
        let currentDirection: Int
        if abs(dominantValue) < directionChangeThreshold {
            currentDirection = 0  // Neutral/stopped
        } else if dominantValue > 0 {
            currentDirection = 1  // Positive direction
        } else {
            currentDirection = -1  // Negative direction
        }
        
        // Detect direction reversal (1 → -1 or -1 → 1)
        if lastDirection != 0 && currentDirection != 0 && lastDirection != currentDirection {
            // Direction changed! Count as a rep
            currentReps += 1
            onRepDetected?(currentReps, timestamp)
            
            print("🔄 [IMU-Rep] Direction change detected! \(lastDirection) → \(currentDirection) | Rep #\(currentReps) | Gyro: \(String(format: "%.3f", dominantValue))")
        }
        
        // Update last direction (only if not neutral)
        if currentDirection != 0 {
            lastDirection = currentDirection
        }
        
        lastGyroReading = rotationRate
    }
}
