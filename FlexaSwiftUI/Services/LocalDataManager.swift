import Foundation

class LocalDataManager: ObservableObject {
    static let shared = LocalDataManager()
    
    private let userDefaults = UserDefaults.standard
    private let comprehensiveSessionsKey = "cached_comprehensive_sessions"
    private let goalsKey = "cached_user_goals"
    private let streaksKey = "cached_streak_data"
    private let sessionSeqBaseKey = "session_sequence_base"
    private let sessionFilesKey = "cached_session_files"
    private let sessionSeqNeedsSeedKey = "session_sequence_needs_seed"
    private let sessionSeqLastNumberKey = "session_sequence_last_number"
    
    private init() {
        if userDefaults.object(forKey: sessionSeqNeedsSeedKey) == nil {
            userDefaults.set(true, forKey: sessionSeqNeedsSeedKey)
        }
    }
    
    // MARK: - Comprehensive Sessions (main data structure)
    func saveComprehensiveSession(_ session: ComprehensiveSessionData) {
        var sessions = getCachedComprehensiveSessions()
        sessions.append(session)
        
        // Keep only last 50 sessions for performance
        if sessions.count > 50 {
            sessions = Array(sessions.suffix(50))
        }
        if let encoded = try? JSONEncoder().encode(sessions) {
            userDefaults.set(encoded, forKey: comprehensiveSessionsKey)
            print("💾 [LOCAL] ✅ Saved comprehensive session with ROM/SPARC data locally")
        }

        // Update session sequence tracking (local-first)
        updateLastSessionNumberIfNeeded(session.sessionNumber)
        userDefaults.set(false, forKey: sessionSeqNeedsSeedKey)
        let desiredBase = max(0, session.sessionNumber - sessions.count)
        if desiredBase != getSessionSequenceBase() {
            setSessionSequenceBase(desiredBase)
        }
        
        // Update goals from session data
        saveGoals(session.goalsAfterSession)
        
        // Update streak from session
        updateStreakFromSession(session)
    }

    func replaceComprehensiveSessions(_ sessions: [ComprehensiveSessionData]) {
        let sorted = sessions.sorted { $0.timestamp > $1.timestamp }
        let limited = Array(sorted.prefix(50))
        if let encoded = try? JSONEncoder().encode(limited) {
            userDefaults.set(encoded, forKey: comprehensiveSessionsKey)
            print("💾 [LOCAL] Replaced comprehensive session cache with remote sync")
        }

        let maxSessionNumber = limited.map { $0.sessionNumber }.max() ?? 0
        updateLastSessionNumberIfNeeded(maxSessionNumber)
        userDefaults.set(false, forKey: sessionSeqNeedsSeedKey)
        let desiredBase = max(0, maxSessionNumber - limited.count)
        if desiredBase != getSessionSequenceBase() {
            setSessionSequenceBase(desiredBase)
        }
    }
    
    func getCachedComprehensiveSessions() -> [ComprehensiveSessionData] {
        guard let data = userDefaults.data(forKey: comprehensiveSessionsKey),
              let sessions = try? JSONDecoder().decode([ComprehensiveSessionData].self, from: data) else {
            return []
        }
        return sessions.sorted { $0.timestamp > $1.timestamp }
    }
    
    // MARK: - Backwards compatibility for ExerciseSessionData
    func getCachedSessions() -> [ExerciseSessionData] {
        return getCachedComprehensiveSessions().map { $0.toExerciseSessionData() }
    }
    
    func getRecentSessions(limit: Int = 5) -> [ExerciseSessionData] {
        return Array(getCachedSessions().prefix(limit))
    }
    
    func getTodaySessions() -> [ExerciseSessionData] {
        let sessions = getCachedSessions()
        return sessions.filter { Calendar.current.isDateInToday($0.timestamp) }
    }
    
    // MARK: - Additional compatibility methods for Appwrite reads elimination
    func getStoredSessions() -> [ExerciseSessionData] {
        return getCachedSessions()
    }
    
    func getStoredGoals() -> UserGoals? {
        return getCachedGoals()
    }
    
    // MARK: - Goals
    func saveGoals(_ goals: UserGoals) {
        if let encoded = try? JSONEncoder().encode(goals) {
            userDefaults.set(encoded, forKey: goalsKey)
            print("💾 [LOCAL] Saved goals locally")
        }
    }
    
    func getCachedGoals() -> UserGoals {
        guard let data = userDefaults.data(forKey: goalsKey),
              let goals = try? JSONDecoder().decode(UserGoals.self, from: data) else {
            return UserGoals() // Default goals
        }
        return goals
    }
    
    // MARK: - Streaks
    func saveStreak(_ streak: StreakData) {
        if let encoded = try? JSONEncoder().encode(streak) {
            userDefaults.set(encoded, forKey: streaksKey)
            print("💾 [LOCAL] Saved streak locally")
        }
    }
    
    func getCachedStreak() -> StreakData {
        guard let data = userDefaults.data(forKey: streaksKey),
              let streak = try? JSONDecoder().decode(StreakData.self, from: data) else {
            return StreakData() // Default streak
        }
        return streak
    }
    
    private func updateStreakFromSession(_ session: ComprehensiveSessionData) {
        let calendar = Calendar.current
        let today = session.timestamp
        var currentStreak = getCachedStreak()
        
        // Check if last exercise was yesterday or today
        if calendar.isDate(currentStreak.lastExerciseDate, inSameDayAs: today) {
            // Same day, don't increment streak
            return
        } else if calendar.isDate(currentStreak.lastExerciseDate, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: today) ?? Date()) {
            // Yesterday, increment streak
            currentStreak = StreakData(
                currentStreak: currentStreak.currentStreak + 1,
                longestStreak: max(currentStreak.longestStreak, currentStreak.currentStreak + 1),
                lastExerciseDate: today,
                totalDays: currentStreak.totalDays + 1
            )
        } else {
            // Gap in streak, reset to 1
            currentStreak = StreakData(
                currentStreak: 1,
                longestStreak: max(currentStreak.longestStreak, 1),
                lastExerciseDate: today,
                totalDays: currentStreak.totalDays + 1
            )
        }
        
        saveStreak(currentStreak)
    }
    
    // MARK: - NO CLOUD SYNC - Only comprehensive upload after post-survey
    // Backend (Appwrite) is used for an optional comprehensive upload; local-first behavior is preserved.
    // Appwrite is ONLY used for:
    // 1. Authentication (when enabled)
    // 2. Single comprehensive upload after post-survey (via SessionUploadService)
    // 3. Initial data load on fresh app installs (if needed)
    
        func uploadComprehensiveSessionToBackend(_ session: ComprehensiveSessionData) {
            // Use existing SessionUploadService for comprehensive upload
            let uploadService = SessionUploadService()
            uploadService.uploadSessionData(session) { result in
                switch result {
                case .success():
                    print("🔄 [UPLOAD] Comprehensive session uploaded to backend")
                case .failure(let error):
                    print("⚠️ [UPLOAD] Failed to upload session: \(error)")
                }
            }
    }

    // MARK: - Session Number Sequence (mostly local)
    // We keep a base offset persisted; sessionNumber = base + localCount + 1
    // If the user clears local data in settings, you can refresh the base from server count and continue locally.
    func nextSessionNumber() -> Int {
        return getLastSessionNumber() + 1
    }
    
    func getSessionSequenceBase() -> Int {
        return userDefaults.integer(forKey: sessionSeqBaseKey)
    }
    
    func setSessionSequenceBase(_ base: Int) {
        let current = userDefaults.integer(forKey: sessionSeqBaseKey)
        guard current != base else { return }
        userDefaults.set(base, forKey: sessionSeqBaseKey)
        print("💾 [LOCAL] Session sequence base set to \(base)")
    }

    func shouldSeedSessionSequenceFromRemote() -> Bool {
        if !getCachedComprehensiveSessions().isEmpty {
            userDefaults.set(false, forKey: sessionSeqNeedsSeedKey)
            return false
        }
        if userDefaults.object(forKey: sessionSeqNeedsSeedKey) == nil {
            userDefaults.set(true, forKey: sessionSeqNeedsSeedKey)
        }
        return userDefaults.bool(forKey: sessionSeqNeedsSeedKey)
    }

    func markSessionSequenceSeeded(with latestNumber: Int) {
        updateLastSessionNumberIfNeeded(latestNumber)
        let retainedCount = getCachedComprehensiveSessions().count
        let desiredBase = max(0, latestNumber - retainedCount)
        if desiredBase != getSessionSequenceBase() {
            setSessionSequenceBase(desiredBase)
        }
        userDefaults.set(false, forKey: sessionSeqNeedsSeedKey)
    }

    func markSessionSequenceNeedsReseed() {
        userDefaults.set(true, forKey: sessionSeqNeedsSeedKey)
    }

    func getLastSessionNumber() -> Int {
        if userDefaults.object(forKey: sessionSeqLastNumberKey) != nil {
            return userDefaults.integer(forKey: sessionSeqLastNumberKey)
        }
        let maxLocal = getCachedComprehensiveSessions().map { $0.sessionNumber }.max() ?? 0
        userDefaults.set(maxLocal, forKey: sessionSeqLastNumberKey)
        return maxLocal
    }

    func updateLastSessionNumberIfNeeded(_ number: Int) {
        guard number > 0 else { return }
        let current = userDefaults.integer(forKey: sessionSeqLastNumberKey)
        if number > current {
            userDefaults.set(number, forKey: sessionSeqLastNumberKey)
            print("💾 [LOCAL] Session sequence advanced to #\(number)")
        }
    }

    // MARK: - Session Files for Graphing
    func saveSessionFile(_ sessionFile: SessionFile) {
        var sessionFiles = getCachedSessionFiles()
        sessionFiles.append(sessionFile)
        
        // Keep only last 100 session files for performance
        if sessionFiles.count > 100 {
            sessionFiles = Array(sessionFiles.suffix(100))
        }
        
        if let encoded = try? JSONEncoder().encode(sessionFiles) {
            userDefaults.set(encoded, forKey: sessionFilesKey)
            print("💾 [LOCAL] Saved session file for graphing: \(sessionFile.exerciseType)")
        }
    }
    
    func getCachedSessionFiles() -> [SessionFile] {
        guard let data = userDefaults.data(forKey: sessionFilesKey),
              let files = try? JSONDecoder().decode([SessionFile].self, from: data) else {
            return []
        }
        return files.sorted { $0.timestamp > $1.timestamp }
    }
    
    func getLatestSessionFile() -> SessionFile? {
        return getCachedSessionFiles().first
    }
    
    // MARK: - Clear Local Data (sessions, goals, streak, timelines) - RESETS daily progress
    func clearLocalData() {
        userDefaults.removeObject(forKey: comprehensiveSessionsKey)
        userDefaults.removeObject(forKey: goalsKey)
        userDefaults.removeObject(forKey: streaksKey)
        userDefaults.removeObject(forKey: sessionFilesKey)
        
        // Reset session sequence base to 0 so daily sessions start fresh
        setSessionSequenceBase(0)
    markSessionSequenceNeedsReseed()
        
        // Remove sensor timelines directory
        let fm = FileManager.default
        let urls = fm.urls(for: .documentDirectory, in: .userDomainMask)
        if let base = urls.first {
            let dir = base.appendingPathComponent("sensor_timelines", isDirectory: true)
            if fm.fileExists(atPath: dir.path) {
                try? fm.removeItem(at: dir)
            }
        }
        print("🧹 [LOCAL] Cleared local data caches and timelines - reset daily progress")
    }
}
