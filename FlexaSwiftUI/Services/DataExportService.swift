import Foundation
import UIKit

class DataExportService: ObservableObject {
    static let shared = DataExportService()
    
    private init() {}
    
    func exportAllUserData() -> URL? {
        // Create Flexa folder in Documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let flexaFolder = documentsPath.appendingPathComponent("Flexa", isDirectory: true)
        
        // Create folder if it doesn't exist
        try? FileManager.default.createDirectory(at: flexaFolder, withIntermediateDirectories: true)
        
        // Create filename with readable timestamp
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let exportURL = flexaFolder.appendingPathComponent("FlexaData_\(timestamp).json")
        
        do {
            // Gather comprehensive user data
            let exportData = gatherAllUserData()
            let sanitized = sanitizeJSONValue(exportData)
            guard let sanitizedDict = sanitized as? [String: Any] else { 
                throw NSError(domain: "DataExportService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to sanitize export payload"]) 
            }
            
            // Write to file with pretty formatting
            let jsonData = try JSONSerialization.data(withJSONObject: sanitizedDict, options: [.prettyPrinted, .sortedKeys])
            try jsonData.write(to: exportURL)
            
            print("✅ [DataExport] Successfully exported data to: \(exportURL.path)")
            print("📊 [DataExport] File size: \(jsonData.count / 1024) KB")
            
            return exportURL
        } catch {
            print("❌ [DataExport] Export error: \(error)")
            return nil
        }
    }
    
    private func gatherAllUserData() -> [String: Any] {
        var exportData: [String: Any] = [:]
        
        // Export timestamp
        exportData["exportDate"] = ISO8601DateFormatter().string(from: Date())
        exportData["appVersion"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        
        // User preferences
        let userDefaults = UserDefaults.standard.dictionaryRepresentation()
        let filteredDefaults = userDefaults.filter { key, _ in
            key.hasPrefix("flexa_") || key.contains("user") || key.contains("setting")
        }
        // Pre-sanitize preferences as they often contain Data and Date values (e.g., "user_goals")
        exportData["userPreferences"] = sanitizeJSONValue(filteredDefaults)
        
        // Session data (mock structure - replace with actual data source)
        exportData["sessionHistory"] = gatherSessionData()
        
        // Progress data
        exportData["progressMetrics"] = gatherProgressData()
        
        // SPARC data
        exportData["sparcAnalysis"] = gatherSPARCData()
        
        return exportData
    }

    // MARK: - JSON Sanitization
    // Recursively convert Foundation types into JSON-serializable values.
    // - Date -> ISO8601 string
    // - Data -> base64 string (attempt JSON decode first for readability)
    // - Dictionary/Array -> recursively sanitize
    // - Numbers/Strings/Bools/NSNull -> passthrough
    private func sanitizeJSONValue(_ value: Any) -> Any {
        switch value {
        case let dict as [String: Any]:
            var out: [String: Any] = [:]
            for (k, v) in dict {
                out[k] = sanitizeJSONValue(v)
            }
            return out
        case let array as [Any]:
            return array.map { sanitizeJSONValue($0) }
        case let date as Date:
            return ISO8601DateFormatter().string(from: date)
        case let data as Data:
            // Try to decode as JSON for readability; fallback to base64 string
            if let obj = try? JSONSerialization.jsonObject(with: data) {
                return sanitizeJSONValue(obj)
            }
            return data.base64EncodedString()
        case let num as NSNumber:
            return num
        case let str as String:
            return str
        case is NSNull:
            return NSNull()
        default:
            // As a last resort, stringify unknown types
            return String(describing: value)
        }
    }
    
    private func gatherSessionData() -> [[String: Any]] {
        // Use real session data from LocalDataManager
        let sessions = LocalDataManager.shared.getCachedComprehensiveSessions()
        
        return sessions.map { session in
            [
                "id": session.id,
                "date": ISO8601DateFormatter().string(from: session.timestamp),
                "exerciseType": session.exerciseName,
                "duration": session.duration,
                "totalScore": session.totalScore,
                "reps": session.totalReps,
                "maxROM": session.maxROM,
                "avgROM": session.avgROM,
                "consistencyScore": session.consistencyScore,
                "aiScore": session.aiScore,
                "sparcScore": session.sparcScore,
                "romPerRep": session.romPerRep,
                "preSurveyPain": session.preSurveyData.painLevel,
                "postSurveyPain": session.postSurveyData?.painLevel as Any? ?? NSNull(),
                "sessionNumber": session.sessionNumber,
                "gameSpecificData": session.gameSpecificData
            ]
        }
    }
    
    private func gatherProgressData() -> [String: Any] {
        let streak = LocalDataManager.shared.getCachedStreak()
        let goals = LocalDataManager.shared.getCachedGoals()
        let sessions = LocalDataManager.shared.getCachedComprehensiveSessions()
        
        let totalTime = sessions.reduce(0) { $0 + $1.duration }
        let avgROM = sessions.isEmpty ? 0 : sessions.map({ $0.maxROM }).reduce(0, +) / Double(sessions.count)
        let totalReps = sessions.reduce(0) { $0 + $1.totalReps }
        
        return [
            "totalSessions": sessions.count,
            "currentStreak": streak.currentStreak,
            "longestStreak": streak.longestStreak,
            "totalDaysActive": streak.totalDays,
            "totalExerciseTime": totalTime,
            "averageROM": avgROM,
            "totalReps": totalReps,
            "lastExerciseDate": ISO8601DateFormatter().string(from: streak.lastExerciseDate),
            "currentGoals": [
                "dailyReps": goals.dailyReps,
                "weeklyMinutes": goals.weeklyMinutes,
                "targetROM": goals.targetROM,
                "preferredGames": goals.preferredGames
            ]
        ]
    }
    
    private func gatherSPARCData() -> [String: Any] {
        let sessions = LocalDataManager.shared.getCachedComprehensiveSessions()
        let sessionFiles = LocalDataManager.shared.getCachedSessionFiles()
        
        let sparcValues = sessions.map { $0.sparcScore }
        let avgSPARC = sparcValues.isEmpty ? 0 : sparcValues.reduce(0, +) / Double(sparcValues.count)
        let bestSPARC = sparcValues.max() ?? 0
        let worstSPARC = sparcValues.min() ?? 0
        
        // Calculate trend from recent sessions
        let recentSessions = Array(sessions.prefix(10))
        let sparcTrend: String
        if recentSessions.count >= 2 {
            let recentAvg = recentSessions.prefix(5).map({ $0.sparcScore }).reduce(0, +) / Double(min(5, recentSessions.count))
            let olderAvg = recentSessions.suffix(5).map({ $0.sparcScore }).reduce(0, +) / Double(min(5, recentSessions.count))
            sparcTrend = recentAvg > olderAvg ? "improving" : (recentAvg < olderAvg ? "declining" : "stable")
        } else {
            sparcTrend = "insufficient_data"
        }
        
        return [
            "averageSPARC": avgSPARC,
            "bestSPARC": bestSPARC,
            "worstSPARC": worstSPARC,
            "sparcTrend": sparcTrend,
            "totalSPARCMeasurements": sparcValues.count,
            "sessionFilesCount": sessionFiles.count,
            "sparcHistoryData": sessionFiles.map { file in
                [
                    "exerciseType": file.exerciseType,
                    "timestamp": ISO8601DateFormatter().string(from: file.timestamp),
                    "sparcHistory": file.sparcHistory,
                    "reps": file.reps
                ]
            }
        ]
    }
    
    func shareExportedData(url: URL, from viewController: UIViewController) {
        let activityViewController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        
        // For iPad
        if let popover = activityViewController.popoverPresentationController {
            popover.sourceView = viewController.view
            popover.sourceRect = CGRect(x: viewController.view.bounds.midX, y: viewController.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        viewController.present(activityViewController, animated: true)
    }
}
