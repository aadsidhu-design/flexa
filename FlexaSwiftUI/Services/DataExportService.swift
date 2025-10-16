//
//  DataExportService.swift
//  FlexaSwiftUI
//
//  Data export service for downloading all user data
//

import Foundation

class DataExportService {
    static let shared = DataExportService()
    
    private init() {}
    
    /// Export all user data to a JSON file
    /// Returns URL to the exported file, or nil if export failed
    func exportAllUserData() -> URL? {
        do {
            // Get all data from LocalDataManager
            let localData = LocalDataManager.shared
            
            // Gather all data
            let sessions = localData.getCachedComprehensiveSessions()
            let goals = localData.getCachedGoals()
            let streak = localData.getCachedStreak()
            let customExercises = CustomExerciseManager.shared.customExercises
            let sessionNumber = localData.getLastSessionNumber()
            let userId = UserDefaults.standard.string(forKey: "backend_anonymous_user_id") ?? "unknown"
            
            // Create export data structure
            let exportData: [String: Any] = [
                "exportDate": ISO8601DateFormatter().string(from: Date()),
                "appVersion": "1.0.0",
                "userId": userId,
                "sessionNumber": sessionNumber,
                "totalSessions": sessions.count,
                "goals": encodeGoals(goals),
                "streak": encodeStreak(streak),
                "customExercises": customExercises.map { encodeCustomExercise($0) },
                "sessions": sessions.map { encodeSession($0) }
            ]
            
            // Convert to JSON
            let jsonData = try JSONSerialization.data(withJSONObject: exportData, options: [.prettyPrinted, .sortedKeys])
            
            // Create export directory
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let flexaDirectory = documentsURL.appendingPathComponent("Flexa", isDirectory: true)
            
            if !FileManager.default.fileExists(atPath: flexaDirectory.path) {
                try FileManager.default.createDirectory(at: flexaDirectory, withIntermediateDirectories: true)
            }
            
            // Create filename with timestamp
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
            let timestamp = dateFormatter.string(from: Date())
            let filename = "Flexa_Export_\(timestamp).json"
            let fileURL = flexaDirectory.appendingPathComponent(filename)
            
            // Write to file
            try jsonData.write(to: fileURL, options: .atomic)
            
            FlexaLog.backend.info("📥 Data export successful: \(filename)")
            return fileURL
            
        } catch {
            FlexaLog.backend.error("📥 Data export failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Encoding Helpers
    
    private func encodeGoals(_ goals: UserGoals) -> [String: Any] {
        return [
            "dailyReps": goals.dailyReps,
            "weeklyReps": goals.weeklyReps,
            "targetROM": goals.targetROM,
            "targetSmoothness": goals.targetSmoothness,
            "targetAIScore": goals.targetAIScore,
            "targetPainImprovement": goals.targetPainImprovement
        ]
    }
    
    private func encodeStreak(_ streak: StreakData) -> [String: Any] {
        return [
            "currentStreak": streak.currentStreak,
            "longestStreak": streak.longestStreak,
            "lastExerciseDate": ISO8601DateFormatter().string(from: streak.lastExerciseDate),
            "totalDays": streak.totalDays
        ]
    }
    
    private func encodeCustomExercise(_ exercise: CustomExercise) -> [String: Any] {
        return [
            "id": exercise.id.uuidString,
            "name": exercise.name,
            "userDescription": exercise.userDescription,
            "trackingMode": exercise.trackingMode.rawValue,
            "jointToTrack": exercise.jointToTrack?.rawValue ?? "none",
            "movementType": exercise.repParameters.movementType.rawValue,
            "minimumROMThreshold": exercise.repParameters.minimumROMThreshold,
            "minimumDistanceThreshold": exercise.repParameters.minimumDistanceThreshold ?? 0,
            "directionality": exercise.repParameters.directionality.rawValue,
            "repCooldown": exercise.repParameters.repCooldown
        ]
    }
    
    private func encodeSession(_ session: ComprehensiveSessionData) -> [String: Any] {
        var sessionDict: [String: Any] = [
            "sessionNumber": session.sessionNumber,
            "exerciseName": session.exerciseName,
            "timestamp": ISO8601DateFormatter().string(from: session.timestamp),
            "duration": session.duration,
            "totalReps": session.totalReps,
            "avgROM": session.avgROM,
            "maxROM": session.maxROM,
            "sparcScore": session.sparcScore,
            "aiScore": session.aiScore,
            "romPerRep": session.romPerRep,
            "sparcHistory": session.sparcDataOverTime.map { $0.sparcValue }
        ]
        
        // Add survey data if available
        sessionDict["preSurvey"] = [
            "painLevel": session.preSurveyData.painLevel,
            "timestamp": ISO8601DateFormatter().string(from: session.preSurveyData.timestamp)
        ]
        
        if let postSurvey = session.postSurveyData {
            sessionDict["postSurvey"] = [
                "painLevel": postSurvey.painLevel,
                "timestamp": ISO8601DateFormatter().string(from: postSurvey.timestamp)
            ]
        }
        
        return sessionDict
    }
}
