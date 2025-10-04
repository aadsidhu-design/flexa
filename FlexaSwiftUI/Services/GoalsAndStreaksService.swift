import Foundation
import Combine

class GoalsAndStreaksService: ObservableObject {
    @Published var currentGoals: UserGoals = UserGoals()
    @Published var streakData: StreakData = StreakData()
    @Published var todayProgress: DailyProgress = DailyProgress()
    @Published var weeklyProgress: WeeklyProgress = WeeklyProgress()
    @Published var weeklyPainChangePerWeekday: [Double] = Array(repeating: 0.0, count: 7) // Mon..Sun fixed buckets
    
    private var backendService: BackendService?
    private var cancellables = Set<AnyCancellable>()
    
    init(backendService: BackendService? = nil) {
        self.backendService = backendService
        loadUserData()
        // Observe session upload completion to refresh goals/streaks/progress promptly
        NotificationCenter.default.addObserver(forName: .sessionUploadCompleted, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.calculateProgress()
            // No detached background work required here - keep refresh local-first and lightweight
        }
    }

    func configureBackendService(_ service: BackendService) {
        self.backendService = service
    }
    
    func loadUserData() {
        // Load from local cache instantly - completely local-first!
        let localData = LocalDataManager.shared
        self.currentGoals = localData.getCachedGoals()
        self.streakData = localData.getCachedStreak()
        self.calculateProgress()
        
        print("⚡ Goals loaded from local cache - fully local-first")
        
        // Goals are now completely local-first with post-session uploads only
    }
    
    func loadGoalsAndStreaks() async {
        let overallStartTime = Date()
        print("🎯 [GOALS-DEBUG] === Starting loadGoalsAndStreaks ===")
        
        // Load from local cache first
        let cacheStartTime = Date()
        print("🎯 [GOALS-DEBUG] Step 1: Accessing LocalDataManager...")
        let localData = LocalDataManager.shared
        let cacheAccessTime = Date().timeIntervalSince(cacheStartTime)
        print("🎯 [GOALS-DEBUG] ✅ LocalDataManager accessed in \(String(format: "%.3f", cacheAccessTime))s")
        
        let goalsLoadStart = Date()
        print("🎯 [GOALS-DEBUG] Step 2: Loading cached goals...")
        let cachedGoals = localData.getCachedGoals()
        let goalsLoadTime = Date().timeIntervalSince(goalsLoadStart)
        print("🎯 [GOALS-DEBUG] ✅ Cached goals loaded in \(String(format: "%.3f", goalsLoadTime))s")
        
        let streakLoadStart = Date()
        print("🎯 [GOALS-DEBUG] Step 3: Loading cached streak...")
        let cachedStreak = localData.getCachedStreak()
        let streakLoadTime = Date().timeIntervalSince(streakLoadStart)
        print("🎯 [GOALS-DEBUG] ✅ Cached streak loaded in \(String(format: "%.3f", streakLoadTime))s")

        await MainActor.run {
            let uiUpdateStart = Date()
            self.currentGoals = cachedGoals
            self.streakData = cachedStreak
            let uiUpdateTime = Date().timeIntervalSince(uiUpdateStart)
            print("🎯 [GOALS-DEBUG] ✅ UI state updated in \(String(format: "%.3f", uiUpdateTime))s")
        }
        
        // Calculate progress from cached sessions
        let sessionsLoadStart = Date()
        print("🎯 [GOALS-DEBUG] Step 4: Loading comprehensive sessions...")
        let cachedSessions = localData.getCachedComprehensiveSessions()
        let sessionsLoadTime = Date().timeIntervalSince(sessionsLoadStart)
        print("🎯 [GOALS-DEBUG] ✅ Comprehensive sessions loaded: \(cachedSessions.count) sessions in \(String(format: "%.3f", sessionsLoadTime))s")
        
        let progressCalcStart = Date()
        print("🎯 [GOALS-DEBUG] Step 5: Calculating progress...")
        calculateProgress()
        let progressCalcTime = Date().timeIntervalSince(progressCalcStart)
        print("🎯 [GOALS-DEBUG] ✅ Progress calculated in \(String(format: "%.3f", progressCalcTime))s")
        
        let totalTime = Date().timeIntervalSince(overallStartTime)
        print("🎯 [GOALS-DEBUG] 🎯 TOTAL loadGoalsAndStreaks time: \(String(format: "%.3f", totalTime))s")
        print("🎯 [GOALS-DEBUG] === loadGoalsAndStreaks Complete ===")
    }
    
    func updateGoals(_ newGoals: UserGoals) {
        currentGoals = newGoals
        
        // Save locally instantly
        LocalDataManager.shared.saveGoals(newGoals)
        
        // Sync to backend in background via Firebase
        Task { [weak self] in
            guard let self = self, let backend = self.backendService else { return }
            do {
                try await backend.saveUserGoals(newGoals)
            } catch {
                FlexaLog.backend.error("Failed to sync goals to backend: \(error.localizedDescription)")
            }
        }
    }
    
    func updateProgressFromSession(_ session: ExerciseSessionData) {
        // This method is called from HomeView to update progress from cached sessions
        // The actual progress calculation is done in calculateProgress() method
        // This is just a placeholder for compatibility
    }
    
    func refreshGoals() {
        // Recalculate progress from local data
        calculateProgress()
    }
    
    func resetDailyProgress() {
        let today = Date()
        if !Calendar.current.isDate(todayProgress.date, inSameDayAs: today) {
            todayProgress = DailyProgress(date: today)
        }
    }
    
    func recordExerciseSession(_ session: ExerciseSessionData) {
        // Update daily progress
        todayProgress.repsCompleted += session.reps
        todayProgress.minutesExercised += Int(session.duration / 60)
        todayProgress.gamesPlayed += 1
        
        if session.maxROM > todayProgress.bestROM {
            todayProgress.bestROM = session.maxROM
        }
        
        // Update smoothness (use SPARC score from session)
        if session.sparcScore > todayProgress.bestSmoothness {
            todayProgress.bestSmoothness = session.sparcScore
        }
        
        // Update streak
        updateStreak()
        
        // Just update UI state - comprehensive upload happens after post-survey
        print("📊 [GOALS] Updated progress from session locally")
    }

    private func updateStreak() {
        let calendar = Calendar.current
        let today = Date()
        
        // Check if last exercise was yesterday or today
        if calendar.isDate(streakData.lastExerciseDate, inSameDayAs: today) {
            // Already exercised today, no streak change
            return
        } else if calendar.isDate(streakData.lastExerciseDate, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: today) ?? Date()) {
            // Exercised yesterday, continue streak
            streakData = StreakData(
                currentStreak: streakData.currentStreak + 1,
                longestStreak: max(streakData.longestStreak, streakData.currentStreak + 1),
                lastExerciseDate: today,
                totalDays: streakData.totalDays + 1
            )
        } else {
            // Streak broken, start new
            streakData = StreakData(
                currentStreak: 1,
                longestStreak: max(streakData.longestStreak, 1),
                lastExerciseDate: today,
                totalDays: streakData.totalDays + 1
            )
        }
    }
    
    private func calculateProgress() {
        let calendar = Calendar.current
        let today = Date()
        
        // Reset daily progress if it's a new day
        if !calendar.isDate(todayProgress.date, inSameDayAs: today) {
            todayProgress = DailyProgress(date: today)
        }
        
        // Calculate weekly progress
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        weeklyProgress = WeeklyProgress(weekStart: weekStart)
        
        // Load from local cache instantly - use comprehensive sessions for richer data
        let localData = LocalDataManager.shared
        let comprehensiveSessions = localData.getCachedComprehensiveSessions()
        
        // Calculate progress from comprehensive sessions (more accurate)
        let todaySessions = comprehensiveSessions.filter { calendar.isDate($0.timestamp, inSameDayAs: today) }
        let todayReps = todaySessions.reduce(0) { $0 + $1.totalReps }
        let todayMinutes = todaySessions.reduce(0) { $0 + Int($1.duration / 60) }
        
        // Compute today's averages
        // ROM: prefer per-rep ROM across all today's sessions; fallback to session avgROM
        let todayRepROMs = todaySessions.flatMap { $0.romPerRep }
        let todayAvgROM: Double
        if !todayRepROMs.isEmpty {
            todayAvgROM = todayRepROMs.reduce(0, +) / Double(todayRepROMs.count)
        } else {
            let todayAvgROMs = todaySessions.map { $0.avgROM }.filter { $0 > 0 }
            todayAvgROM = todayAvgROMs.isEmpty ? 0 : todayAvgROMs.reduce(0, +) / Double(todayAvgROMs.count)
        }
        // SPARC: use session-level SPARC score (already 0-100 scale)
        let todaySmoothnessValues = todaySessions.compactMap { $0.sparcScore > 0 ? $0.sparcScore : nil }
        let todayAvgSmoothness = todaySmoothnessValues.isEmpty ? 0 : todaySmoothnessValues.reduce(0, +) / Double(todaySmoothnessValues.count)
        
        // Compute yesterday's averages for improvement calculation
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let yesterdaySessions = comprehensiveSessions.filter { calendar.isDate($0.timestamp, inSameDayAs: yesterday) }
    // Yesterday's averages are computed for potential future features but not used presently.
    // Keep placeholder underscores to avoid unused-variable warnings during builds.
    _ = yesterdaySessions.flatMap { $0.romPerRep }
    _ = yesterdaySessions.map { $0.avgROM }
    _ = yesterdaySessions.compactMap { $0.sparcScore > 0 ? $0.sparcScore : nil }
        
        // Daily averages computed above will be used directly for progress
        
        let weekSessions = comprehensiveSessions.filter { $0.timestamp >= weekStart }
        let weekReps = weekSessions.reduce(0) { $0 + $1.totalReps }
        let weekMinutes = weekSessions.reduce(0) { $0 + Int($1.duration / 60) }
        
        self.todayProgress.repsCompleted = todayReps
        self.todayProgress.minutesExercised = todayMinutes
        // Store daily averages (ROM in degrees, Smoothness 0-100)
        self.todayProgress.bestROM = todayAvgROM
        self.todayProgress.bestSmoothness = todayAvgSmoothness
        self.todayProgress.gamesPlayed = todaySessions.count
        
        self.weeklyProgress.totalReps = weekReps
        self.weeklyProgress.totalMinutes = weekMinutes
        self.weeklyProgress.totalSessions = weekSessions.count

        // Compute average pain-change (postPain - prePain) per fixed weekday Mon..Sun
        // We'll map Calendar weekday (1 = Sunday ... 7 = Saturday) to index 0..6 for Mon..Sun
        var buckets: [Double] = Array(repeating: 0.0, count: 7)
        var counts: [Int] = Array(repeating: 0, count: 7)

        for session in weekSessions {
            // Use survey pain fields from the comprehensive session data
            guard let post = session.postSurveyData?.painLevel else { continue }
            let pre = session.preSurveyData.painLevel
            let painChange = Double(post - pre)
            let wkday = calendar.component(.weekday, from: session.timestamp) // 1..7 Sun..Sat
            // Convert to Mon..Sun index: weekday 2 (Mon) -> 0, ..., 1 (Sun) -> 6
            let monIndex = (wkday + 5) % 7 // maps Sun(1)->6, Mon(2)->0, ..., Sat(7)->5
            buckets[monIndex] += painChange
            counts[monIndex] += 1
        }

        for i in 0..<7 {
            if counts[i] > 0 {
                buckets[i] = buckets[i] / Double(counts[i])
            } else {
                buckets[i] = 0.0
            }
        }

        self.weeklyPainChangePerWeekday = buckets
        
        print("⚡ [GOALS] Progress calculated from local cache")
    }
    
    func getGoalProgress(for goalType: GoalType) -> Double {
        switch goalType {
        case .sessions:
            return min(Double(todayProgress.gamesPlayed) / Double(currentGoals.dailyReps), 1.0)
        case .rom:
            return min(todayProgress.bestROM / currentGoals.targetROM, 1.0)
        case .smoothness:
            return min(todayProgress.bestSmoothness / (currentGoals.targetSmoothness * 100.0), 1.0)
        case .totalReps:
            return min(Double(todayProgress.gamesPlayed) / Double(currentGoals.dailyReps), 1.0)
        case .aiScore:
            return 0.0
        case .painImprovement:
            return 0.0
        }
    }
    
    func getStreakMotivation() -> String {
        switch streakData.currentStreak {
        case 0: return "Start your journey today! 🌟"
        case 1: return "Day one complete! 🔥"
        case 2...6: return "Building momentum! \(streakData.currentStreak) days strong! 💪"
        case 7...13: return "One week streak! You're on fire! 🔥"
        case 14...29: return "Two weeks! Incredible dedication! ⭐"
        case 30...59: return "One month streak! You're unstoppable! 🚀"
        case 60...99: return "Two months! Rehabilitation champion! 🏆"
        default: return "Legendary streak! \(streakData.currentStreak) days! 👑"
        }
    }
    
    func getNextMilestone() -> (days: Int, message: String) {
        let current = streakData.currentStreak
        let milestones = [7, 14, 30, 60, 100, 365]
        
        for milestone in milestones {
            if current < milestone {
                return (milestone - current, "Next milestone: \(milestone) days")
            }
        }
        
        return (0, "You've achieved all milestones! 🎉")
    }
    
    func getAdditionalGoals() -> [GoalData] {
        return [
            GoalData(type: .aiScore, targetValue: currentGoals.targetAIScore, currentValue: 0, isEnabled: currentGoals.targetAIScore > 0),
            GoalData(type: .painImprovement, targetValue: currentGoals.targetPainImprovement, currentValue: 0, isEnabled: currentGoals.targetPainImprovement > 0),
            GoalData(type: .totalReps, targetValue: Double(currentGoals.weeklyReps), currentValue: 0, isEnabled: currentGoals.weeklyReps > 0)
        ].filter { $0.isEnabled }
    }
}

struct DailyProgress {
    var date: Date
    var repsCompleted: Int
    var minutesExercised: Int
    var gamesPlayed: Int
    var bestROM: Double // Actually stores average ROM for the day
    var bestSmoothness: Double // Actually stores average smoothness for the day
    
    init(date: Date = Date(), repsCompleted: Int = 0, minutesExercised: Int = 0, gamesPlayed: Int = 0, bestROM: Double = 0, bestSmoothness: Double = 0) {
        self.date = date
        self.repsCompleted = repsCompleted
        self.minutesExercised = minutesExercised
        self.gamesPlayed = gamesPlayed
        self.bestROM = bestROM
        self.bestSmoothness = bestSmoothness
    }
}

struct WeeklyProgress {
    var weekStart: Date
    var minutesCompleted: Int
    var daysActive: Int
    var totalReps: Int
    var totalMinutes: Int
    var totalSessions: Int
    
    init(weekStart: Date = Date(), minutesCompleted: Int = 0, daysActive: Int = 0) {
        self.weekStart = weekStart
        self.minutesCompleted = minutesCompleted
        self.daysActive = daysActive
        self.totalReps = 0
        self.totalMinutes = minutesCompleted
        self.totalSessions = 0
    }
}

