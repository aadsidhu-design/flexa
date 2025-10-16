import Foundation

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
    let sparcScore: Double
    let gameSpecificData: String
    
    // Detailed Data Arrays
    let sparcDataOverTime: [SPARCDataPoint]
    let romPerRep: [Double]
    let repTimestamps: [Date]
    let movementQualityScores: [Double]
    
    // Survey Data
    let preSurveyData: PreSurveyData
    let postSurveyData: PostSurveyData?
    
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
    let painReductionScore: Double?
    
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
    postSurvey: PostSurveyData?,
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
        // Prefer per-rep ROM if available; fallback to legacy romData
        let romSeries: [Double] = !performanceData.romPerRep.isEmpty ? performanceData.romPerRep : performanceData.romData
        self.avgROM = romSeries.isEmpty ? 0 : romSeries.reduce(0, +) / Double(romSeries.count)
        self.maxROM = romSeries.max() ?? 0
        self.totalROM = romSeries.reduce(0, +)
        self.aiScore = performanceData.aiScore
        self.aiFeedback = performanceData.aiFeedback
        self.sparcScore = performanceData.sparcScore
        self.gameSpecificData = performanceData.gameSpecificData
        
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
        if let postSurvey {
            self.painReductionScore = Double(preSurvey.painLevel - postSurvey.painLevel)
        } else {
            self.painReductionScore = nil
        }
        
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

enum SPARCDataSource: String, Codable {
    case arkit
    case imu
    case vision
}

struct SPARCDataPoint: Codable {
    let timestamp: Date
    let sparcValue: Double
    let movementPhase: String // "acceleration", "deceleration", "steady"
    let jointAngles: [String: Double] // Joint name to angle mapping
    let confidence: Double
    let dataSource: SPARCDataSource
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
    let sparcScore: Double
    let gameSpecificData: String
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

// MARK: - Azure Extensions

extension ComprehensiveSessionData {
    func toDictionary() -> [String: Any] {
        // Create a well-structured, validated dictionary
        var dictionary: [String: Any] = [:]
        
        // Core session info
        dictionary["id"] = id
        dictionary["userID"] = userID
        dictionary["sessionNumber"] = sessionNumber
        dictionary["exerciseName"] = exerciseName
        dictionary["timestamp"] = ISO8601DateFormatter().string(from: timestamp)
        dictionary["duration"] = duration
        
        // Performance metrics
        dictionary["performance"] = [
            "totalScore": totalScore,
            "totalReps": totalReps,
            "avgROM": avgROM.isNaN ? 0 : avgROM,
            "maxROM": maxROM.isNaN ? 0 : maxROM,
            "totalROM": totalROM.isNaN ? 0 : totalROM,
            "aiScore": aiScore,
            "aiFeedback": aiFeedback,
            "sparcScore": sparcScore.isNaN ? 0 : sparcScore,
            "gameSpecificData": gameSpecificData
        ]
        
        // Time series data
        dictionary["timeSeries"] = [
            "sparcDataOverTime": sparcDataOverTime.map { dataPoint in
                [
                    "sparcValue": dataPoint.sparcValue.isNaN ? 0 : dataPoint.sparcValue,
                    "timestamp": ISO8601DateFormatter().string(from: dataPoint.timestamp)
                ]
            },
            "romPerRep": romPerRep.map { $0.isNaN ? 0 : $0 },
            "repTimestamps": repTimestamps.map { ISO8601DateFormatter().string(from: $0) },
            "movementQualityScores": movementQualityScores.map { $0.isNaN ? 0 : $0 }
        ]
        
        // Survey data
        dictionary["surveys"] = [
            "preSurvey": [
                "painLevel": preSurveyData.painLevel,
                "exerciseReadiness": preSurveyData.exerciseReadiness ?? 0,
                "previousExerciseHours": preSurveyData.previousExerciseHours ?? 0,
                "timestamp": ISO8601DateFormatter().string(from: preSurveyData.timestamp)
            ],
            "postSurvey": postSurveyData.map { postSurvey in
                [
                    "painLevel": postSurvey.painLevel,
                    "funRating": postSurvey.funRating,
                    "difficultyRating": postSurvey.difficultyRating,
                    "enjoymentRating": postSurvey.enjoymentRating,
                    "perceivedExertion": postSurvey.perceivedExertion ?? 0,
                    "willingnessToRepeat": postSurvey.willingnessToRepeat ?? 0,
                    "timestamp": ISO8601DateFormatter().string(from: postSurvey.timestamp)
                ]
            } ?? []
        ]
        
        // Goals and progress
        dictionary["goals"] = [
            "before": [
                "dailyReps": goalsBeforeSession.dailyReps,
                "weeklyMinutes": goalsBeforeSession.weeklyMinutes,
                "targetROM": goalsBeforeSession.targetROM.isNaN ? 0 : goalsBeforeSession.targetROM,
                "preferredGames": goalsBeforeSession.preferredGames
            ],
            "after": [
                "dailyReps": goalsAfterSession.dailyReps,
                "weeklyMinutes": goalsAfterSession.weeklyMinutes,
                "targetROM": goalsAfterSession.targetROM.isNaN ? 0 : goalsAfterSession.targetROM,
                "preferredGames": goalsAfterSession.preferredGames
            ],
            "progress": [
                "romGoalProgress": goalProgressMetrics.romGoalProgress.isNaN ? 0 : goalProgressMetrics.romGoalProgress,
                "repsGoalProgress": goalProgressMetrics.repsGoalProgress.isNaN ? 0 : goalProgressMetrics.repsGoalProgress,
                "consistencyImprovement": goalProgressMetrics.consistencyImprovement.isNaN ? 0 : goalProgressMetrics.consistencyImprovement,
                "painReductionGoal": goalProgressMetrics.painReductionGoal.isNaN ? 0 : goalProgressMetrics.painReductionGoal,
                "goalAdjustmentRecommendation": goalProgressMetrics.goalAdjustmentRecommendation
            ]
        ]
        
        // Analytics
        dictionary["analytics"] = [
            "exerciseEfficiency": exerciseEfficiency.isNaN ? 0 : exerciseEfficiency,
            "consistencyScore": consistencyScore.isNaN ? 0 : consistencyScore,
            "fatigueIndex": fatigueIndex.isNaN ? 0 : fatigueIndex,
            "improvementRate": improvementRate.isNaN ? 0 : improvementRate,
            "painReductionScore": (painReductionScore ?? 0) as Any
        ]
        
        // Sensor data (optional)
        if let accelAvg = accelAvgMagnitude, !accelAvg.isNaN {
            dictionary["sensorData"] = [
                "accelAvgMagnitude": accelAvg,
                "accelPeakMagnitude": (accelPeakMagnitude ?? 0) as Any,
                "gyroAvgMagnitude": (gyroAvgMagnitude ?? 0) as Any,
                "gyroPeakMagnitude": (gyroPeakMagnitude ?? 0) as Any
            ]
        }
        
        // Environment data
        dictionary["environment"] = [
            "deviceOrientation": deviceOrientation,
            "lightingConditions": lightingConditions,
            "exerciseEnvironment": exerciseEnvironment
        ]
        
        // Streak data if available
        if let streak = streakAtSession {
            dictionary["streak"] = [
                "currentStreak": streak.currentStreak,
                "longestStreak": streak.longestStreak,
                "lastExerciseDate": ISO8601DateFormatter().string(from: streak.lastExerciseDate)
            ]
        }
        
        // Metadata
        dictionary["metadata"] = [
            "schemaVersion": 2,
            "createdAt": ISO8601DateFormatter().string(from: timestamp),
            "dataIntegrity": "validated"
        ]
        
        return dictionary
    }
    
    func validateData() -> (isValid: Bool, errors: [String]) {
        var errors: [String] = []
        
        // Validate required fields
        if id.isEmpty { errors.append("Session ID is empty") }
        if userID.isEmpty { errors.append("User ID is empty") }
        if exerciseName.isEmpty { errors.append("Exercise name is empty") }
        if duration <= 0 { errors.append("Duration must be positive") }
        
        // Validate numeric fields
        if totalReps < 0 { errors.append("Total reps cannot be negative") }
        if totalScore < 0 { errors.append("Total score cannot be negative") }
        
        // Validate ROM values
        if avgROM < 0 { errors.append("Average ROM cannot be negative") }
        if maxROM < 0 { errors.append("Max ROM cannot be negative") }
        if totalROM < 0 { errors.append("Total ROM cannot be negative") }
        
        // Validate survey data ranges
        if preSurveyData.painLevel < 0 || preSurveyData.painLevel > 10 {
            errors.append("Pre-survey pain level must be 0-10")
        }
        if let readiness = preSurveyData.exerciseReadiness, readiness < 1 || readiness > 5 {
            errors.append("Pre-survey exercise readiness must be 1-5")
        }
        
        if let postSurvey = postSurveyData {
            if postSurvey.painLevel < 0 || postSurvey.painLevel > 10 {
                errors.append("Post-survey pain level must be 0-10")
            }
            if postSurvey.funRating < 0 || postSurvey.funRating > 10 {
                errors.append("Post-survey fun rating must be 0-10")
            }
        }
        
        // Validate time series data consistency
        if romPerRep.count != repTimestamps.count {
            errors.append("ROM per rep count doesn't match rep timestamps count")
        }
        
        return (errors.isEmpty, errors)
    }
    
    static func fromDictionary(_ dict: [String: Any]) -> ComprehensiveSessionData? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let session = try? JSONDecoder().decode(ComprehensiveSessionData.self, from: data) else {
            return nil
        }
        return session
    }
}

extension ComprehensiveSessionData {
    func toExerciseSessionData() -> ExerciseSessionData {
        let romPoints: [ROMPoint]
        if repTimestamps.count == romPerRep.count {
            romPoints = zip(romPerRep, repTimestamps).map { ROMPoint(angle: $0.0, timestamp: $0.1) }
        } else {
            romPoints = []
        }

        let sparcPoints: [SPARCPoint] = sparcDataOverTime.map {
            SPARCPoint(sparc: $0.sparcValue, timestamp: $0.timestamp)
        }

        return ExerciseSessionData(
            id: id,
            exerciseType: exerciseName,
            score: totalScore,
            reps: totalReps,
            maxROM: maxROM,
            averageROM: avgROM,
            duration: duration,
            timestamp: timestamp,
            romHistory: romPerRep,
            sparcHistory: movementQualityScores,
            romData: romPoints,
            sparcData: sparcPoints,
            aiScore: aiScore,
            painPre: preSurveyData.painLevel,
            painPost: postSurveyData?.painLevel,
            sparcScore: sparcScore,
            formScore: consistencyScore,
            consistency: consistencyScore,
            peakVelocity: 0,
            motionSmoothnessScore: exerciseEfficiency,
            accelAvgMagnitude: accelAvgMagnitude,
            accelPeakMagnitude: accelPeakMagnitude,
            gyroAvgMagnitude: gyroAvgMagnitude,
            gyroPeakMagnitude: gyroPeakMagnitude,
            aiFeedback: aiFeedback,
            goalsAfter: goalsAfterSession
        )
    }
}
