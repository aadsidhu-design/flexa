import SwiftUI

struct HomeView: View {
    @EnvironmentObject var firebaseService: FirebaseService
    @EnvironmentObject var goalsService: GoalsService
    @EnvironmentObject var streaksService: GoalsAndStreaksService
    @EnvironmentObject var recommendationsEngine: RecommendationsEngine
    @EnvironmentObject var themeManager: ThemeManager

    @State private var recentSessions: [ExerciseSessionData] = []
    @State private var isLoading = true
    @State private var goalsLoaded = false

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 24) {
                    // Welcome Header
                    WelcomeHeader()
                        .padding(.top, 8)

                    // Goals Rings - Show loading state until goals are ready
                    if goalsLoaded {
                        ActivityRingsView()
                            .padding(.vertical, 8)
                    } else {
                        ActivityRingsLoadingView()
                            .padding(.vertical, 8)
                    }

                    // Streak Cards
                    ImprovedStreaksSection()
                        .padding(.vertical, 8)

                    // Recent Activities
                    if isLoading {
                        VStack {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            Text("Loading sessions...")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .frame(height: 80)
                    } else if !recentSessions.isEmpty {
                        RecentActivitiesSection(sessions: recentSessions)
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "clock")
                                .font(.title2)
                                .foregroundColor(.gray)
                            Text("No recent activities")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            Text("Start a game to see your sessions here")
                                .font(.caption)
                                .foregroundColor(.gray.opacity(0.7))
                        }
                        .frame(height: 100)
                        .padding()
                    }

                    Spacer(minLength: 60)
                }
                .padding(.horizontal, 16)
            }
            .background(themeManager.backgroundColor)
            .navigationBarHidden(true)
            .onAppear {
                loadRecentSessions()
                // Don't block UI with recommendations - load in background
                Task.detached(priority: .background) {
                    await recommendationsEngine.generatePersonalizedRecommendations()
                }
            }
        }
    }

    private func loadRecentSessions() {
        let overallStartTime = Date()
        print("🏠 [HOME-DEBUG] === Starting loadRecentSessions ===")
        
        isLoading = true
        print("🏠 [HOME-DEBUG] Step 1: Set loading state")
        
        // Load from local cache instantly - NO Firebase calls!
        let cacheStartTime = Date()
        print("🏠 [HOME-DEBUG] Step 2: Accessing LocalDataManager...")
        let localData = LocalDataManager.shared
        let cacheAccessTime = Date().timeIntervalSince(cacheStartTime)
        print("🏠 [HOME-DEBUG] ✅ LocalDataManager accessed in \(String(format: "%.3f", cacheAccessTime))s")
        
        let sessionsStartTime = Date()
        print("🏠 [HOME-DEBUG] Step 3: Loading recent sessions from cache...")
        self.recentSessions = localData.getRecentSessions(limit: 5)
        let sessionsLoadTime = Date().timeIntervalSince(sessionsStartTime)
        print("🏠 [HOME-DEBUG] ✅ Recent sessions loaded: \(recentSessions.count) sessions in \(String(format: "%.3f", sessionsLoadTime))s")
        
        self.isLoading = false
        print("🏠 [HOME-DEBUG] Step 4: Set loading complete")
        
        // Update goals from local sessions
        let goalsStartTime = Date()
        print("🏠 [HOME-DEBUG] Step 5: Loading today's sessions for goals...")
        let todaySessions = localData.getTodaySessions()
        let todayLoadTime = Date().timeIntervalSince(goalsStartTime)
        print("🏠 [HOME-DEBUG] ✅ Today's sessions loaded: \(todaySessions.count) sessions in \(String(format: "%.3f", todayLoadTime))s")
        
        let resetStartTime = Date()
        print("🏠 [HOME-DEBUG] Step 6: Resetting daily progress...")
        goalsService.resetDailyProgress()
        let resetTime = Date().timeIntervalSince(resetStartTime)
        print("🏠 [HOME-DEBUG] ✅ Daily progress reset in \(String(format: "%.3f", resetTime))s")
        
        let updateStartTime = Date()
        print("🏠 [HOME-DEBUG] Step 7: Updating goals from \(todaySessions.count) sessions...")
        todaySessions.forEach { session in
            let sessionUpdateStart = Date()
            goalsService.updateProgressFromSession(session)
            let sessionUpdateTime = Date().timeIntervalSince(sessionUpdateStart)
            print("🏠 [HOME-DEBUG] - Session \(session.id) processed in \(String(format: "%.3f", sessionUpdateTime))s")
        }
        let updateTime = Date().timeIntervalSince(updateStartTime)
        print("🏠 [HOME-DEBUG] ✅ Goals updated in \(String(format: "%.3f", updateTime))s")
        
        self.goalsLoaded = true
        print("🏠 [HOME-DEBUG] Step 8: Set goals loaded state")
        
        let totalTime = Date().timeIntervalSince(overallStartTime)
        print("🏠 [HOME-DEBUG] 🎯 TOTAL loadRecentSessions time: \(String(format: "%.3f", totalTime))s")
        print("🏠 [HOME-DEBUG] === loadRecentSessions Complete ===")
    }
}

struct WelcomeHeader: View {
    @EnvironmentObject var streaksService: GoalsAndStreaksService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(greetingText())
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }

    private func greetingText() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Good night"
        }
    }
}

struct ImprovedStreaksSection: View {
    @EnvironmentObject var streaksService: GoalsAndStreaksService

    var body: some View {
        VStack(spacing: 16) {
            Text("Streaks")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 16) {
                ImprovedStreakCard(
                    title: "Current Streak",
                    value: streaksService.streakData.currentStreak,
                    unit: "days",
                    icon: "flame.fill",
                    gradient: [.orange, .red],
                    description: ""
                )

                ImprovedStreakCard(
                    title: "Longest Streak",
                    value: streaksService.streakData.longestStreak,
                    unit: "days",
                    icon: "crown.fill",
                    gradient: [.yellow, .orange],
                    description: ""
                )
            }
        }
    }
}

struct ImprovedStreakCard: View {
    let title: String
    let value: Int
    let unit: String
    let icon: String
    let gradient: [Color]
    let description: String

    var body: some View {
        VStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 56, height: 56)
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
            }

            // Metrics
            Text("\(value)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text(unit.uppercased())
                .font(.caption)
                .foregroundColor(.gray)

            Text(title)
                .font(.subheadline)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            if !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.gray.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

struct ActivityRingsLoadingView: View {
    var body: some View {
        VStack(spacing: 24) {
            Text("Today's Goals")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(spacing: 16) {
                // Main loading ring
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 20)
                        .frame(width: 180, height: 180)
                    
                    VStack(spacing: 4) {
                        Text("Loading...")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.gray)
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    }
                }
                
                HStack(spacing: 20) {
                    // Two smaller loading rings
                    ForEach(0..<2, id: \.self) { _ in
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.15), lineWidth: 18)
                                .frame(width: 130, height: 130)
                            
                            VStack(spacing: 4) {
                                Text("...")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
        .redacted(reason: .placeholder)
    }
}

#Preview {
    HomeView()
        .environmentObject(FirebaseService())
        .environmentObject(GoalsService())
        .environmentObject(GoalsAndStreaksService())
        .environmentObject(RecommendationsEngine())
        .background(Color.black)
}
