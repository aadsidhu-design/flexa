import Foundation
import Combine

class GoalsAndStreaksService: ObservableObject {
    @Published var currentGoals: UserGoals = UserGoals()
    @Published var streakData: StreakData = StreakData()
    @Published var todayProgress: DailyProgress = DailyProgress()
    @Published var weeklyProgress: WeeklyProgress = WeeklyProgress()
    
    private let firebaseService = FirebaseService()
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        loadUserData()
    }
    
    func loadUserData() {
        // Load from local cache instantly - NO Firebase calls!
        let localData = LocalDataManager.shared
        self.currentGoals = localData.getCachedGoals()
        self.streakData = localData.getCachedStreak()
        self.calculateProgress()
        
        print("⚡ [GOALS] Loaded from local cache instantly")
        
        // Firebase loading is handled elsewhere - local cache only
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
            self.currentGoals = cachedGoals ?? UserGoals()
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
        
        // Sync to Firebase in background
        Task.detached(priority: .background) {
            do {
                try await self.firebaseService.saveUserGoals(newGoals)
            } catch {
                print("⚠️ [GOALS] Error syncing goals to Firebase: \(error)")
            }
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
        
        // Load from local cache instantly - NO Firebase calls!
        let localData = LocalDataManager.shared
        let sessions = localData.getCachedSessions()
        
        // Calculate progress from local sessions
        let todaySessions = sessions.filter { calendar.isDate($0.timestamp, inSameDayAs: today) }
        let todayReps = todaySessions.reduce(0) { $0 + $1.reps }
        let todayMinutes = todaySessions.reduce(0) { $0 + Int($1.duration / 60) }
        let todayBestROM = todaySessions.compactMap(\.maxROM).max() ?? 0
        
        let weekSessions = sessions.filter { $0.timestamp >= weekStart }
        let weekReps = weekSessions.reduce(0) { $0 + $1.reps }
        let weekMinutes = weekSessions.reduce(0) { $0 + Int($1.duration / 60) }
        
        self.todayProgress.repsCompleted = todayReps
        self.todayProgress.minutesExercised = todayMinutes
        self.todayProgress.bestROM = todayBestROM
        self.todayProgress.gamesPlayed = todaySessions.count
        
        self.weeklyProgress.totalReps = weekReps
        self.weeklyProgress.totalMinutes = weekMinutes
        self.weeklyProgress.totalSessions = weekSessions.count
        
        print("⚡ [GOALS] Progress calculated from local cache")
    }
    
    func getGoalProgress(for goalType: GoalType) -> Double {
        switch goalType {
        case .sessions:
            return min(Double(todayProgress.repsCompleted) / Double(currentGoals.dailyReps), 1.0)
        case .rom:
            return min(todayProgress.bestROM / currentGoals.targetROM, 1.0)
        case .smoothness:
            return min(todayProgress.bestROM / currentGoals.targetROM, 1.0)
        case .totalReps:
            return min(Double(todayProgress.repsCompleted) / Double(currentGoals.dailyReps), 1.0)
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
}

struct DailyProgress {
    var date: Date
    var repsCompleted: Int
    var minutesExercised: Int
    var gamesPlayed: Int
    var bestROM: Double
    
    init(date: Date = Date(), repsCompleted: Int = 0, minutesExercised: Int = 0, gamesPlayed: Int = 0, bestROM: Double = 0) {
        self.date = date
        self.repsCompleted = repsCompleted
        self.minutesExercised = minutesExercised
        self.gamesPlayed = gamesPlayed
        self.bestROM = bestROM
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

