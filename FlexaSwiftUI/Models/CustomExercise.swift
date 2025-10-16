import Foundation
import SwiftUI

/// Represents a user-created custom exercise parsed by Gemini AI
struct CustomExercise: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var userDescription: String
    var trackingMode: TrackingMode
    var jointToTrack: JointToTrack?  // Only for camera exercises
    var repParameters: RepParameters
    var dateCreated: Date
    var timesCompleted: Int
    var averageROM: Double?
    var averageSPARC: Double?
    
    enum TrackingMode: String, Codable {
    case handheld  // ARKit + IMU tracking
    case camera    // BlazePose camera pose detection
    }
    
    enum JointToTrack: String, Codable {
        case armpit   // Shoulder ROM (elevation)
        case elbow    // Elbow flexion/extension

        func toCameraJointPreference() -> CameraJointPreference {
            switch self {
            case .armpit:
                return .armpit
            case .elbow:
                return .elbow
            }
        }
    }
    
    struct RepParameters: Codable, Hashable {
        var movementType: MovementType
        var minimumROMThreshold: Double  // Degrees
        var minimumDistanceThreshold: Double?  // For handheld (cm)
        var directionality: Directionality
        var repCooldown: Double  // Seconds between reps
        
        enum MovementType: String, Codable {
            case pendulum          // Forward/backward swings
            case circular          // Circular motion
            case vertical          // Up/down (elevation)
            case horizontal        // Side-to-side (abduction)
            case straightening     // Straightening (elbow extension)
            case mixed             // Multiple movement planes
        }
        
        enum Directionality: String, Codable {
            case bidirectional     // Count both directions (e.g., up+down = 1 rep)
            case unidirectional    // Count one direction only (e.g., only up)
            case cyclical          // Continuous cycles (e.g., circular)
        }
    }
    
    init(id: UUID = UUID(),
         name: String,
         userDescription: String,
         trackingMode: TrackingMode,
         jointToTrack: JointToTrack?,
         repParameters: RepParameters,
         dateCreated: Date = Date(),
         timesCompleted: Int = 0,
         averageROM: Double? = nil,
         averageSPARC: Double? = nil) {
        self.id = id
        self.name = name
        self.userDescription = userDescription
        self.trackingMode = trackingMode
        self.jointToTrack = jointToTrack
        self.repParameters = repParameters
        self.dateCreated = dateCreated
        self.timesCompleted = timesCompleted
        self.averageROM = averageROM
        self.averageSPARC = averageSPARC
    }
    
    /// Convert to display-friendly color
    var color: Color {
        switch repParameters.movementType {
        case .pendulum: return .orange
        case .circular: return .purple
        case .vertical: return .blue
        case .horizontal: return .cyan
        case .straightening: return .green
        case .mixed: return .pink
        }
    }
    
    /// Convert to display-friendly icon
    var icon: String {
        switch repParameters.movementType {
        case .pendulum: return "waveform.path"
        case .circular: return "circle.dotted"
        case .vertical: return "arrow.up.arrow.down"
        case .horizontal: return "arrow.left.arrow.right"
        case .straightening: return "arrow.up.forward"
        case .mixed: return "square.3.layers.3d"
        }
    }
    
    /// Brief description for card display
    var briefDescription: String {
        let mode = trackingMode == .handheld ? "Handheld" : "Camera"
        let joint = jointToTrack?.rawValue.capitalized ?? ""
        let movement = repParameters.movementType.rawValue.capitalized
        return "\(mode) · \(joint.isEmpty ? movement : "\(joint) · \(movement)")"
    }
}

/// Response structure from Gemini AI when parsing exercise description
struct AIExerciseAnalysis: Codable {
    var exerciseName: String
    var trackingMode: CustomExercise.TrackingMode
    var jointToTrack: CustomExercise.JointToTrack?
    var movementType: CustomExercise.RepParameters.MovementType
    var directionality: CustomExercise.RepParameters.Directionality
    var minimumROMThreshold: Double
    var minimumDistanceThreshold: Double?
    var repCooldown: Double
    var confidence: Double  // 0-1, how confident AI is in this analysis
    var reasoning: String   // AI explanation of its choices
    
    /// Convert to CustomExercise
    func toCustomExercise(userDescription: String) -> CustomExercise {
        let repParams = CustomExercise.RepParameters(
            movementType: movementType,
            minimumROMThreshold: minimumROMThreshold,
            minimumDistanceThreshold: minimumDistanceThreshold,
            directionality: directionality,
            repCooldown: repCooldown
        )
        
        return CustomExercise(
            name: exerciseName,
            userDescription: userDescription,
            trackingMode: trackingMode,
            jointToTrack: jointToTrack,
            repParameters: repParams
        )
    }
}

/// 🧠 Smart progression suggestion for custom exercises
struct ProgressionSuggestion: Identifiable {
    let id = UUID()
    let exerciseId: UUID
    let exerciseName: String
    let currentThreshold: Double
    let suggestedThreshold: Double
    let reason: String
    let confidence: Double  // 0-1, confidence in this suggestion
    
    var increasePercentage: Int {
        return Int(((suggestedThreshold - currentThreshold) / currentThreshold) * 100)
    }
}
