import Foundation
import FirebaseFirestore

struct ComprehensiveSessionData: Codable, Identifiable {
    let id: String
    let userID: String
    let sessionNumber: Int
    let exerciseName: String
    let timestamp: Date
    let duration: TimeInterval
    
    // Performance Metrics
    let totalScore: Int
    let totalReps: Int
    let avgROM: Double
    let maxROM: Double
    let totalROM: Double
    let aiScore: Int
    let aiFeedback: String
    
    // Detailed Data Arrays
    let sparcDataOverTime: [SPARCDataPoint]
    let romPerRep: [Double]
    let repTimestamps: [Date]
    let movementQualityScores: [Double]
    
    // Survey Data
    let preSurveyData: PreSurveyData
    let postSurveyData: PostSurveyData
    
    // Goals Tracking
    let goalsBeforeSession: UserGoals
    let goalsAfterSession: UserGoals
    let goalProgressMetrics: GoalProgressMetrics
    let streakAtSession: StreakData?
    
    // Advanced Analytics
    let exerciseEfficiency: Double
    let consistencyScore: Double
    let fatigueIndex: Double
    let improvementRate: Double
    let painReductionScore: Double
    
    // Sensor Aggregates (optional for backward compatibility)
    let accelAvgMagnitude: Double?
    let accelPeakMagnitude: Double?
    let gyroAvgMagnitude: Double?
    let gyroPeakMagnitude: Double?
    
    // Device & Environment Data
    let deviceOrientation: String
    let lightingConditions: String
    let exerciseEnvironment: String
    
    init(
        userID: String,
        sessionNumber: Int,
        exerciseName: String,
        duration: TimeInterval,
        performanceData: ExercisePerformanceData,
        preSurvey: PreSurveyData,
        postSurvey: PostSurveyData,
        goalsBefore: UserGoals,
        goalsAfter: UserGoals,
        streakAtSession: StreakData? = nil
    ) {
        self.id = UUID().uuidString
        self.userID = userID
        self.sessionNumber = sessionNumber
        self.exerciseName = exerciseName
        self.timestamp = Date()
        self.duration = duration
        
        // Performance metrics
        self.totalScore = performanceData.score
        self.totalReps = performanceData.reps
        self.avgROM = performanceData.romData.isEmpty ? 0 : performanceData.romData.reduce(0, +) / Double(performanceData.romData.count)
        self.maxROM = performanceData.romData.max() ?? 0
        self.totalROM = performanceData.romData.reduce(0, +)
        self.aiScore = performanceData.aiScore
        self.aiFeedback = performanceData.aiFeedback
        
        // Detailed arrays
        self.sparcDataOverTime = performanceData.sparcDataPoints
        self.romPerRep = performanceData.romPerRep
        self.repTimestamps = performanceData.repTimestamps
        self.movementQualityScores = performanceData.movementQualityScores
        
        // Survey data
        self.preSurveyData = preSurvey
        self.postSurveyData = postSurvey
        
        // Goals
        self.goalsBeforeSession = goalsBefore
        self.goalsAfterSession = goalsAfter
        self.goalProgressMetrics = GoalProgressMetrics(before: goalsBefore, after: goalsAfter, sessionData: performanceData)
        self.streakAtSession = streakAtSession
        
        // Advanced analytics
        self.exerciseEfficiency = Self.calculateEfficiency(performanceData: performanceData)
        self.consistencyScore = Self.calculateSimpleConsistency(romData: performanceData.romPerRep)
        self.fatigueIndex = Self.calculateFatigueIndex(qualityScores: performanceData.movementQualityScores)
        self.improvementRate = Self.calculateImprovementRate(sessionNumber: sessionNumber, currentPerformance: performanceData)
        self.painReductionScore = Double(preSurvey.painLevel - postSurvey.painLevel)
        
        // Sensor aggregates
        self.accelAvgMagnitude = performanceData.accelAvg
        self.accelPeakMagnitude = performanceData.accelPeak
        self.gyroAvgMagnitude = performanceData.gyroAvg
        self.gyroPeakMagnitude = performanceData.gyroPeak
        
        // Environment data
        self.deviceOrientation = "Portrait" // Could be dynamic
        self.lightingConditions = "Good" // Could use camera/sensors
        self.exerciseEnvironment = "Home" // Could be user-selected
    }
    
    // MARK: - Advanced Calculations
    
    private static func calculateEfficiency(performanceData: ExercisePerformanceData) -> Double {
        guard !performanceData.romPerRep.isEmpty else { return 0 }
        let avgROM = performanceData.romPerRep.reduce(0, +) / Double(performanceData.romPerRep.count)
        let timeEfficiency = Double(performanceData.reps) / (performanceData.duration / 60.0) // reps per minute
        return (avgROM / 90.0) * min(timeEfficiency / 10.0, 1.0) * 100 // Normalized efficiency score
    }
    
    private static func calculateSimpleConsistency(romData: [Double]) -> Double {
        guard romData.count > 1 else { return 100 }
        let mean = romData.reduce(0, +) / Double(romData.count)
        let variance = romData.map { pow($0 - mean, 2) }.reduce(0, +) / Double(romData.count)
        let standardDeviation = sqrt(variance)
        let coefficientOfVariation = standardDeviation / mean
        return max(0, 100 - (coefficientOfVariation * 100)) // Higher score = more consistent
    }
    
    private static func calculateFatigueIndex(qualityScores: [Double]) -> Double {
        guard qualityScores.count > 2 else { return 0 }
        let firstThird = Array(qualityScores.prefix(qualityScores.count / 3))
        let lastThird = Array(qualityScores.suffix(qualityScores.count / 3))
        
        let firstAvg = firstThird.reduce(0, +) / Double(firstThird.count)
        let lastAvg = lastThird.reduce(0, +) / Double(lastThird.count)
        
        return max(0, (firstAvg - lastAvg) / firstAvg * 100) // Higher = more fatigue
    }
    
    private static func calculateImprovementRate(sessionNumber: Int, currentPerformance: ExercisePerformanceData) -> Double {
        // This would ideally compare with previous sessions
        // For now, return a baseline improvement based on performance
        let baselineImprovement = Double(currentPerformance.aiScore) / 100.0
        let sessionFactor = min(Double(sessionNumber) / 10.0, 1.0) // Improvement over sessions
        return baselineImprovement * sessionFactor * 100
    }
}

struct SPARCDataPoint: Codable {
    let timestamp: Date
    let sparcValue: Double
    let movementPhase: String // "acceleration", "deceleration", "steady"
    let jointAngles: [String: Double] // Joint name to angle mapping
}

struct ExercisePerformanceData {
    let score: Int
    let reps: Int
    let duration: TimeInterval
    let romData: [Double]
    let romPerRep: [Double]
    let repTimestamps: [Date]
    let sparcDataPoints: [SPARCDataPoint]
    let movementQualityScores: [Double]
    let aiScore: Int
    let aiFeedback: String
    // Optional sensor aggregates
    let accelAvg: Double?
    let accelPeak: Double?
    let gyroAvg: Double?
    let gyroPeak: Double?
}

struct PreSurveyData: Codable {
    var painLevel: Int
    let timestamp: Date
    let exerciseReadiness: Int? // 1-5 scale
    let previousExerciseHours: Int? // Hours since last exercise
}

struct PostSurveyData: Codable {
    var painLevel: Int
    var funRating: Int
    var difficultyRating: Int
    var enjoymentRating: Int
    var perceivedExertion: Int? // 1-10 scale
    var willingnessToRepeat: Int? // 1-5 scale
    let timestamp: Date
}

struct GoalProgressMetrics: Codable {
    let romGoalProgress: Double // Percentage towards ROM goal
    let repsGoalProgress: Double // Percentage towards daily reps goal
    let consistencyImprovement: Double
    let painReductionGoal: Double
    let goalAdjustmentRecommendation: String
    
    init(before: UserGoals, after: UserGoals, sessionData: ExercisePerformanceData) {
        self.romGoalProgress = min(100, (sessionData.romData.max() ?? 0) / before.targetROM * 100)
        self.repsGoalProgress = min(100, Double(sessionData.reps) / Double(before.dailyReps) * 100)
        self.consistencyImprovement = 0 // Would calculate based on historical data
        self.painReductionGoal = 0 // Would track pain reduction over time
        
        // Generate goal adjustment recommendation
        if sessionData.romData.max() ?? 0 > before.targetROM * 0.9 {
            self.goalAdjustmentRecommendation = "Consider increasing ROM goal by 10-15 degrees"
        } else if sessionData.romData.max() ?? 0 < before.targetROM * 0.6 {
            self.goalAdjustmentRecommendation = "Consider reducing ROM goal to build confidence"
        } else {
            self.goalAdjustmentRecommendation = "Current goals are appropriate"
        }
    }
}

// MARK: - Firebase Extensions

extension ComprehensiveSessionData {
    func toDictionary() -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        guard let data = try? encoder.encode(self),
              let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        
        return dictionary
    }
    
    static func fromDictionary(_ dict: [String: Any]) -> ComprehensiveSessionData? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let session = try? JSONDecoder().decode(ComprehensiveSessionData.self, from: data) else {
            return nil
        }
        return session
    }
}
