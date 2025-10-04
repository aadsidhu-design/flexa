import Foundation
import CoreGraphics
import SceneKit

class BodyMeasurementsTracker: ObservableObject {
    // Adaptive body measurements with confidence tracking
    @Published var measurements = AdaptiveBodyMeasurements()
    
    private let maxSamples = 30 // Keep last 30 measurements for averaging
    private var measurementHistory: [String: [(value: Double, confidence: Double, timestamp: TimeInterval)]] = [:]
    
    func updateMeasurement(key: String, value: Double, confidence: Double) {
        let timestamp = CACurrentMediaTime()
        
        if measurementHistory[key] == nil {
            measurementHistory[key] = []
        }
        
        // Add new measurement
        measurementHistory[key]?.append((value: value, confidence: confidence, timestamp: timestamp))
        
        // Keep only recent measurements
        if let count = measurementHistory[key]?.count, count > maxSamples {
            measurementHistory[key]?.removeFirst(count - maxSamples)
        }
        
        // Update adaptive measurement
        updateAdaptiveMeasurement(key: key)
    }
    
    private func updateAdaptiveMeasurement(key: String) {
        guard let history = measurementHistory[key], !history.isEmpty else { return }
        
        // Calculate weighted average based on confidence
        let totalWeight = history.reduce(0) { $0 + $1.confidence }
        guard totalWeight > 0 else { return }
        
        let weightedSum = history.reduce(0) { $0 + ($1.value * $1.confidence) }
        let adaptiveValue = weightedSum / totalWeight
        
        // Calculate overall confidence (average of recent high-confidence measurements)
        let recentMeasurements = history.suffix(10)
        let avgConfidence = recentMeasurements.reduce(0) { $0 + $1.confidence } / Double(recentMeasurements.count)
        
        // Update the adaptive measurements
        measurements.updateMeasurement(key: key, value: adaptiveValue, confidence: avgConfidence)
    }
    
    func getMeasurement(key: String) -> (value: Double, confidence: Double)? {
        return measurements.getMeasurement(key: key)
    }
    
    func getConfidentMeasurement(key: String, minConfidence: Double = 0.7) -> Double? {
        if let (value, confidence) = getMeasurement(key: key), confidence >= minConfidence {
            return value
        }
        return nil
    }
}

struct AdaptiveBodyMeasurements {
    private var measurements: [String: (value: Double, confidence: Double)] = [:]
    
    mutating func updateMeasurement(key: String, value: Double, confidence: Double) {
        measurements[key] = (value: value, confidence: confidence)
    }
    
    func getMeasurement(key: String) -> (value: Double, confidence: Double)? {
        return measurements[key]
    }
    
    // Standard body measurement keys
    static let shoulderWidth = "shoulder_width"
    static let armLength = "arm_length"
    static let forearmLength = "forearm_length"
    static let upperarmLength = "upperarm_length"
    static let neckToShoulder = "neck_to_shoulder"
    static let shoulderToHip = "shoulder_to_hip"
    static let eyeToEye = "eye_to_eye"
    static let headHeight = "head_height"
    static let torsoWidth = "torso_width"
    static let hipWidth = "hip_width"
}
