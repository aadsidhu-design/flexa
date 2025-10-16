import Foundation

/// Comprehensive session data structure for game results and analysis
struct ExerciseSessionData: Identifiable, Codable {
    let id: String
    let exerciseType: String // Renamed from gameType for clarity
    let score: Int
    var reps: Int
    var maxROM: Double
    var averageROM: Double // Average ROM across all reps
    let duration: TimeInterval
    let timestamp: Date
    var romHistory: [Double] // ROM per individual rep
    var repTimestamps: [Date]
    var sparcHistory: [Double] // SPARC per individual rep
    let romData: [ROMPoint] // For backwards compatibility
    var sparcData: [SPARCPoint] // For backwards compatibility
    let aiScore: Int?
    let painPre: Int?
    let painPost: Int?
    var sparcScore: Double // Overall SPARC score
    let formScore: Double
    let consistency: Double
    var peakVelocity: Double
    let motionSmoothnessScore: Double
    // Optional sensor aggregates
    let accelAvgMagnitude: Double?
    let accelPeakMagnitude: Double?
    let gyroAvgMagnitude: Double?
    let gyroPeakMagnitude: Double?
    // Extended upload fields
    let aiFeedback: String?
    let goalsAfter: UserGoals?

    init(
        id: String = UUID().uuidString,
        exerciseType: String,
        score: Int,
        reps: Int,
        maxROM: Double,
        averageROM: Double = 0,
        duration: TimeInterval,
        timestamp: Date = Date(),
        romHistory: [Double] = [],
        repTimestamps: [Date] = [],
        sparcHistory: [Double] = [],
        romData: [ROMPoint] = [],
        sparcData: [SPARCPoint] = [],
        aiScore: Int? = nil,
        painPre: Int? = nil,
        painPost: Int? = nil,
        sparcScore: Double = 0,
        formScore: Double = 0,
        consistency: Double = 0,
        peakVelocity: Double = 0,
        motionSmoothnessScore: Double = 0,
        accelAvgMagnitude: Double? = nil,
        accelPeakMagnitude: Double? = nil,
        gyroAvgMagnitude: Double? = nil,
        gyroPeakMagnitude: Double? = nil,
        aiFeedback: String? = nil,
        goalsAfter: UserGoals? = nil
    ) {
        let resolvedRomHistory = romHistory
        let computedAverageROM: Double
        if averageROM != 0 {
            computedAverageROM = averageROM
        } else if !resolvedRomHistory.isEmpty {
            computedAverageROM = resolvedRomHistory.reduce(0, +) / Double(resolvedRomHistory.count)
        } else {
            computedAverageROM = 0
        }

        let normalizedRepTimestamps: [Date]
        if repTimestamps.count == resolvedRomHistory.count {
            normalizedRepTimestamps = repTimestamps
        } else if repTimestamps.isEmpty {
            if resolvedRomHistory.isEmpty {
                normalizedRepTimestamps = []
            } else {
                let sessionStart = timestamp.addingTimeInterval(-max(duration, 0))
                let step = resolvedRomHistory.count > 1 ? duration / Double(resolvedRomHistory.count - 1) : 0
                normalizedRepTimestamps = (0..<resolvedRomHistory.count).map { index in
                    sessionStart.addingTimeInterval(Double(index) * step)
                }
            }
        } else if repTimestamps.count > resolvedRomHistory.count {
            normalizedRepTimestamps = Array(repTimestamps.prefix(resolvedRomHistory.count))
        } else {
            var padded = repTimestamps
            let remaining = resolvedRomHistory.count - repTimestamps.count
            let lastTimestamp = repTimestamps.last ?? timestamp
            let paddingStep = remaining > 0 ? max(duration / Double(resolvedRomHistory.count), 0.5) : 0
            for idx in 1...remaining {
                padded.append(lastTimestamp.addingTimeInterval(Double(idx) * paddingStep))
            }
            normalizedRepTimestamps = padded
        }

        self.id = id
        self.exerciseType = exerciseType
        self.score = score
        self.reps = reps
        self.maxROM = maxROM
        self.averageROM = computedAverageROM
        self.duration = duration
        self.timestamp = timestamp
        self.romHistory = resolvedRomHistory
        self.repTimestamps = normalizedRepTimestamps
        self.sparcHistory = sparcHistory
        self.romData = romData
        self.sparcData = sparcData
        self.aiScore = aiScore
        self.painPre = painPre
        self.painPost = painPost
        self.sparcScore = sparcScore
        self.formScore = formScore
        self.consistency = consistency
        self.peakVelocity = peakVelocity
        self.motionSmoothnessScore = motionSmoothnessScore
        self.accelAvgMagnitude = accelAvgMagnitude
        self.accelPeakMagnitude = accelPeakMagnitude
        self.gyroAvgMagnitude = gyroAvgMagnitude
        self.gyroPeakMagnitude = gyroPeakMagnitude
        self.aiFeedback = aiFeedback
        self.goalsAfter = goalsAfter
    }
}

struct ROMPoint: Codable {
    let angle: Double
    let timestamp: Date
}

struct SPARCPoint: Codable {
    let sparc: Double
    let timestamp: Date
}

struct UserGoals: Codable {
    var dailyReps: Int
    var weeklyMinutes: Int
    var targetROM: Double
    var targetSmoothness: Double
    var targetAIScore: Double
    var targetPainImprovement: Double
    var weeklyReps: Int
    var preferredGames: [String]
    var painReduction: Bool
    
    init(dailyReps: Int = 7, weeklyMinutes: Int = 150, targetROM: Double = 90, targetSmoothness: Double = 0.8, targetAIScore: Double = 85.0, targetPainImprovement: Double = 0.0, weeklyReps: Int = 300, preferredGames: [String] = [], painReduction: Bool = false) {
        self.dailyReps = dailyReps
        self.weeklyMinutes = weeklyMinutes
        self.targetROM = targetROM
        self.targetSmoothness = targetSmoothness
        self.targetAIScore = targetAIScore
        self.targetPainImprovement = targetPainImprovement
        self.weeklyReps = weeklyReps
        self.preferredGames = preferredGames
        self.painReduction = painReduction
    }
}