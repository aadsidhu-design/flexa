import Foundation

final class LocalDataManager {
    static let shared = LocalDataManager()
    private init() {}
    
    // MARK: - Keys
    private let goalsKey = "local_user_goals_v1"
    private let streakKey = "local_streak_data_v1"
    private let sessionsKey = "local_exercise_sessions_v1"
    private let comprehensiveSessionsKey = "local_comprehensive_sessions_v1"
    private let sessionFilesKey = "local_session_files_v1"
    
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    // MARK: - Goals
    func saveGoals(_ goals: UserGoals) {
        if let data = try? encoder.encode(goals) {
            UserDefaults.standard.set(data, forKey: goalsKey)
        }
    }
    
    func getCachedGoals() -> UserGoals? {
        guard let data = UserDefaults.standard.data(forKey: goalsKey),
              let goals = try? decoder.decode(UserGoals.self, from: data) else {
            return nil
        }
        return goals
    }
    
    // MARK: - Streak
    func saveStreak(_ streak: StreakData) {
        if let data = try? encoder.encode(streak) {
            UserDefaults.standard.set(data, forKey: streakKey)
        }
    }
    
    func getCachedStreak() -> StreakData {
        if let data = UserDefaults.standard.data(forKey: streakKey),
           let streak = try? decoder.decode(StreakData.self, from: data) {
            return streak
        }
        return StreakData()
    }
    
    // MARK: - Sessions (basic ExerciseSessionData list)
    func cacheSessions(_ sessions: [ExerciseSessionData]) {
        if let data = try? encoder.encode(sessions) {
            UserDefaults.standard.set(data, forKey: sessionsKey)
        }
    }
    
    func getCachedSessions() -> [ExerciseSessionData] {
        guard let data = UserDefaults.standard.data(forKey: sessionsKey),
              let sessions = try? decoder.decode([ExerciseSessionData].self, from: data) else {
            return []
        }
        return sessions
    }
    
    // MARK: - Comprehensive sessions (placeholder list for compatibility)
    struct ComprehensiveSessionData: Codable, Identifiable {
        var id: String { UUID().uuidString }
        let exerciseName: String
        let totalReps: Int
        let duration: TimeInterval
        let timestamp: Date
        let romPerRep: [Double]
    }
    
    func cacheComprehensiveSessions(_ sessions: [ComprehensiveSessionData]) {
        if let data = try? encoder.encode(sessions) {
            UserDefaults.standard.set(data, forKey: comprehensiveSessionsKey)
        }
    }
    
    func getCachedComprehensiveSessions() -> [ComprehensiveSessionData] {
        guard let data = UserDefaults.standard.data(forKey: comprehensiveSessionsKey),
              let sessions = try? decoder.decode([ComprehensiveSessionData].self, from: data) else {
            return []
        }
        return sessions
    }
    
    // MARK: - SessionFile persistence
    func saveSessionFile(_ file: SessionFile) {
        var files = getSessionFiles()
        files.append(file)
        if let data = try? encoder.encode(files) {
            UserDefaults.standard.set(data, forKey: sessionFilesKey)
        }
    }
    
    func getSessionFiles() -> [SessionFile] {
        guard let data = UserDefaults.standard.data(forKey: sessionFilesKey),
              let files = try? decoder.decode([SessionFile].self, from: data) else {
            return []
        }
        return files
    }
}

