import Foundation

class MovementPatternAnalyzer: ObservableObject {
    @Published var compensatoryMovements: [CompensatoryMovement] = []
    @Published var movementQualityScore: Double = 100
    @Published var suggestions: [MovementSuggestion] = []
    
    private var recentPoses: [SimplifiedPoseKeypoints] = []
    private let maxPoseHistory = 30 // Keep last 30 poses for analysis
    
    func analyzePose(_ keypoints: SimplifiedPoseKeypoints, exerciseType: String) {
        // Add to history
        recentPoses.append(keypoints)
        if recentPoses.count > maxPoseHistory {
            recentPoses.removeFirst()
        }
        
        // Clear previous analysis
        compensatoryMovements.removeAll()
        suggestions.removeAll()
        
        if let gameType = GameType.fromDisplayName(exerciseType) {
            switch gameType {
            case .fruitSlicer, .followCircle, .constellationMaker:
                analyzeArmRaisePattern(keypoints)
            case .wallClimbers:
                analyzeWallClimbersPattern(keypoints)
            case .fanOutFlame:
                analyzeHammerPattern(keypoints)
            case .balloonPop:
                analyzeArmRaisePattern(keypoints)
            case .makeYourOwn:
                analyzeGeneralPattern(keypoints)
            }
        } else {
            // Legacy / custom exercise names
            switch exerciseType.lowercased() {
            case "fruit slicer", "arm raise", "pendulum swing", "pendulum circles", "arm raises":
                analyzeArmRaisePattern(keypoints)
            case "wall climbers", "wall climb":
                analyzeWallClimbersPattern(keypoints)
            case "hammer time", "fan out the flame", "scapular retractions":
                analyzeHammerPattern(keypoints)
            default:
                analyzeGeneralPattern(keypoints)
            }
        }
        
        // Calculate overall movement quality
        calculateMovementQuality()
    }
    
    private func analyzeArmRaisePattern(_ keypoints: SimplifiedPoseKeypoints) {
        // Check for shoulder hiking
        if let leftShoulder = keypoints.leftShoulder,
           let rightShoulder = keypoints.rightShoulder,
           keypoints.leftShoulderConfidence > 0.5, keypoints.rightShoulderConfidence > 0.5 {
            
            let shoulderHeightDiff = abs(leftShoulder.y - rightShoulder.y)
            if shoulderHeightDiff > 0.1 { // Threshold for shoulder asymmetry
                compensatoryMovements.append(
                    CompensatoryMovement(
                        type: .shoulderHiking,
                        severity: min(shoulderHeightDiff * 10, 1.0),
                        description: "One shoulder is higher than the other"
                    )
                )
                suggestions.append(
                    MovementSuggestion(
                        title: "Keep Shoulders Level",
                        description: "Focus on keeping both shoulders at the same height during the movement",
                        priority: .high
                    )
                )
            }
        }
        
        // Check for trunk lean
        if let leftShoulder = keypoints.leftShoulder,
           let rightShoulder = keypoints.rightShoulder,
           let leftHip = keypoints.leftHip,
           let rightHip = keypoints.rightHip,
           keypoints.leftShoulderConfidence > 0.5, keypoints.rightShoulderConfidence > 0.5 {
            
            let shoulderMidpoint = CGPoint(
                x: (leftShoulder.x + rightShoulder.x) / 2,
                y: (leftShoulder.y + rightShoulder.y) / 2
            )
            let hipMidpoint = CGPoint(
                x: (leftHip.x + rightHip.x) / 2,
                y: (leftHip.y + rightHip.y) / 2
            )
            
            let trunkLean = abs(shoulderMidpoint.x - hipMidpoint.x)
            if trunkLean > 0.08 { // Threshold for trunk lean
                compensatoryMovements.append(
                    CompensatoryMovement(
                        type: .trunkLean,
                        severity: min(trunkLean * 12, 1.0),
                        description: "Leaning to one side during movement"
                    )
                )
                suggestions.append(
                    MovementSuggestion(
                        title: "Maintain Upright Posture",
                        description: "Keep your torso straight and avoid leaning to either side",
                        priority: .medium
                    )
                )
            }
        }
        
        // Check for elbow position
        if let leftShoulder = keypoints.leftShoulder,
           let leftElbow = keypoints.leftElbow,
           keypoints.leftShoulderConfidence > 0.5, keypoints.leftElbowConfidence > 0.5 {
            
            let elbowBehindShoulder = leftElbow.x < leftShoulder.x - 0.05
            if elbowBehindShoulder {
                compensatoryMovements.append(
                    CompensatoryMovement(
                        type: .elbowDrift,
                        severity: 0.6,
                        description: "Elbow drifting behind shoulder line"
                    )
                )
                suggestions.append(
                    MovementSuggestion(
                        title: "Keep Elbow Forward",
                        description: "Maintain your elbow in line with or slightly in front of your shoulder",
                        priority: .medium
                    )
                )
            }
        }
    }
    
    private func analyzeWallClimbersPattern(_ keypoints: SimplifiedPoseKeypoints) {
        // Check for excessive forward head posture
        if let nose = keypoints.nose,
           let leftShoulder = keypoints.leftShoulder,
           let rightShoulder = keypoints.rightShoulder,
           keypoints.leftShoulderConfidence > 0.5, keypoints.rightShoulderConfidence > 0.5 {
            
            let shoulderMidpoint = CGPoint(
                x: (leftShoulder.x + rightShoulder.x) / 2,
                y: (leftShoulder.y + rightShoulder.y) / 2
            )
            
            let headForward = nose.x - shoulderMidpoint.x
            if headForward > 0.1 {
                compensatoryMovements.append(
                    CompensatoryMovement(
                        type: .forwardHeadPosture,
                        severity: min(headForward * 8, 1.0),
                        description: "Head positioned too far forward"
                    )
                )
                suggestions.append(
                    MovementSuggestion(
                        title: "Neutral Head Position",
                        description: "Keep your head in line with your spine, chin slightly tucked",
                        priority: .high
                    )
                )
            }
        }
    }
    
    private func analyzeHammerPattern(_ keypoints: SimplifiedPoseKeypoints) {
        // Check for wrist alignment
        if let leftElbow = keypoints.leftElbow,
           let leftWrist = keypoints.leftWrist,
           keypoints.leftElbowConfidence > 0.5 {
            
            let wristDeviation = abs(leftWrist.x - leftElbow.x)
            if wristDeviation > 0.08 {
                compensatoryMovements.append(
                    CompensatoryMovement(
                        type: .wristDeviation,
                        severity: min(wristDeviation * 10, 1.0),
                        description: "Wrist not aligned with forearm"
                    )
                )
                suggestions.append(
                    MovementSuggestion(
                        title: "Align Wrist with Forearm",
                        description: "Keep your wrist straight and in line with your forearm",
                        priority: .medium
                    )
                )
            }
        }
    }
    
    private func analyzeGeneralPattern(_ keypoints: SimplifiedPoseKeypoints) {
        // General posture check
        if let leftShoulder = keypoints.leftShoulder,
           let rightShoulder = keypoints.rightShoulder,
           keypoints.leftShoulderConfidence > 0.5, keypoints.rightShoulderConfidence > 0.5 {
            
            let shoulderAsymmetry = abs(leftShoulder.y - rightShoulder.y)
            if shoulderAsymmetry > 0.12 {
                suggestions.append(
                    MovementSuggestion(
                        title: "Check Your Posture",
                        description: "Maintain balanced posture throughout the exercise",
                        priority: .low
                    )
                )
            }
        }
    }
    
    private func calculateMovementQuality() {
        var qualityScore: Double = 100
        
        for movement in compensatoryMovements {
            let penalty = movement.severity * movement.type.qualityImpact
            qualityScore -= penalty
        }
        
        movementQualityScore = max(qualityScore, 0)
    }
    
    func getTopSuggestion() -> MovementSuggestion? {
        return suggestions.sorted { $0.priority.rawValue > $1.priority.rawValue }.first
    }
    
    func hasSignificantIssues() -> Bool {
        return compensatoryMovements.contains { $0.severity > 0.7 }
    }
}

struct CompensatoryMovement {
    let type: CompensatoryMovementType
    let severity: Double // 0.0 to 1.0
    let description: String
}

enum CompensatoryMovementType {
    case shoulderHiking
    case trunkLean
    case elbowDrift
    case forwardHeadPosture
    case wristDeviation
    case excessiveArching
    
    var qualityImpact: Double {
        switch self {
        case .shoulderHiking: return 15
        case .trunkLean: return 20
        case .elbowDrift: return 10
        case .forwardHeadPosture: return 12
        case .wristDeviation: return 8
        case .excessiveArching: return 18
        }
    }
}

struct MovementSuggestion {
    let title: String
    let description: String
    let priority: SuggestionPriority
}

enum SuggestionPriority: Int, CaseIterable {
    case low = 1
    case medium = 2
    case high = 3
    
    var color: String {
        switch self {
        case .low: return "blue"
        case .medium: return "orange"
        case .high: return "red"
        }
    }
}
