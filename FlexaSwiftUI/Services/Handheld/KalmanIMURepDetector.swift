import Foundation
import CoreMotion
import simd

/// Detects repetitions for handheld games using smoothed gyroscope data.
final class KalmanIMURepDetector: ObservableObject {
    
    enum GameType: CustomStringConvertible {
        case fruitSlicer
        case fanOutFlame

        var description: String {
            switch self {
            case .fruitSlicer:
                return "Fruit Slicer"
            case .fanOutFlame:
                return "Fan Out Flame"
            }
        }
    }
    
    @Published private(set) var currentReps: Int = 0
    @Published private(set) var lastRepTimestamp: TimeInterval = 0
    
    private var gameType: GameType = .fruitSlicer
    private var lastTimestamp: TimeInterval = 0
    private var isInitialized = false
    
    // Smoothing
    private var smoothedVelocity: Float = 0.0
    private let smoothingFactor: Float = 0.2
    
    // Rep Detection
    private var lastDirection: Int = 0
    private let velocityThreshold: Float = 0.1
    private let repCooldown: TimeInterval = 0.4
    
    // ROM
    private let romThreshold: Double = 5.0
    var romProvider: (() -> Double)?
    
    var onRepDetected: ((Int, TimeInterval) -> Void)?
    
    init() {
        FlexaLog.motion.info("🔄 [IMURepDetector] Initialized (Simple)")
    }
    
    func startSession(gameType: GameType) {
        self.gameType = gameType
        resetState()
        FlexaLog.motion.info("🔄 [IMURepDetector] Started session for \(gameType)")
    }
    
    func stopSession() {
        let reps = self.currentReps
        FlexaLog.motion.info("🔄 [IMURepDetector] Session stopped - final reps: \(reps)")
    }
    
    func resetState() {
        currentReps = 0
        lastRepTimestamp = 0
        lastTimestamp = 0
        isInitialized = false
        smoothedVelocity = 0.0
        lastDirection = 0
    }
    
    func processGyroscope(_ rotationRate: CMRotationRate, timestamp: TimeInterval) {
        guard isInitialized else {
            isInitialized = true
            lastTimestamp = timestamp
            return
        }
        
        let dt = timestamp - lastTimestamp
        guard dt > 0 else { return }
        
        let measurement: Float
        switch gameType {
        case .fruitSlicer:
            measurement = Float(rotationRate.y) // Pitch
        case .fanOutFlame:
            measurement = Float(rotationRate.z) // Yaw
        }
        
        // Apply exponential moving average as a low-pass filter
        smoothedVelocity = (smoothingFactor * measurement) + ((1.0 - smoothingFactor) * smoothedVelocity)
        
        detectRep(timestamp: timestamp)
        
        lastTimestamp = timestamp
    }
    
    private func detectRep(timestamp: TimeInterval) {
        let currentDirection = smoothedVelocity > velocityThreshold ? 1 : (smoothedVelocity < -velocityThreshold ? -1 : 0)
        
        if currentDirection != 0 && currentDirection != lastDirection {
            if lastDirection != 0 { // Avoid counting a rep on the first direction change
                let currentROM = romProvider?() ?? 0.0
                if currentROM > romThreshold {
                    if timestamp - lastRepTimestamp > repCooldown {
                        currentReps += 1
                        lastRepTimestamp = timestamp
                        let reps = self.currentReps
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else { return }
                            self.onRepDetected?(reps, timestamp)
                        }
                    }
                }
            }
            lastDirection = currentDirection
        }
    }
}
