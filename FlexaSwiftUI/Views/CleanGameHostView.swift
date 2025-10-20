import SwiftUI
import AVFoundation

struct CleanGameHostView: View {
    let gameType: GameType
    let preSurveyData: PreSurveyData
    @EnvironmentObject var motionService: SimpleMotionService
    @EnvironmentObject var backendService: BackendService
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    @EnvironmentObject var goalsService: GoalsAndStreaksService
    
    @State private var gameScore: Int = 0
    @State private var repsCompleted: Int = 0
    @State private var currentROM: Double = 0.0
    @State private var maxROM: Double = 0.0
    @State private var timeRemaining: Int = 90
    @State private var gameStarted: Bool = false
    @State private var showResults: Bool = false
    @State private var showAnalyzing: Bool = false
    @State private var sessionData: ExerciseSessionData?
    @State private var aiAnalysis: ExerciseAnalysis?
    @State private var countdownTimer: Timer?
    
    var body: some View {
        Group {
            // Full screen game without camera overlay
            switch gameType {
            case .fruitSlicer:
                OptimizedFruitSlicerGameView()
                    .environmentObject(motionService)
                    .environmentObject(backendService)
                    .ignoresSafeArea()
            case .balloonPop:
                BalloonPopGameView()
                    .environmentObject(motionService)
                    .environmentObject(backendService)
                    .ignoresSafeArea()
            case .followCircle:
                FollowCircleGameView(
                    score: $gameScore,
                    reps: $repsCompleted,
                    rom: $currentROM,
                    isActive: $gameStarted
                )
                    .environmentObject(motionService)
                    .environmentObject(backendService)
            
            case .wallClimbers:
                WallClimbersGameView()
                    .environmentObject(motionService)
                    .environmentObject(backendService)
                    .ignoresSafeArea()
            case .fanOutFlame:
                FanOutTheFlameGameView()
                    .environmentObject(motionService)
                    .environmentObject(backendService)
                    .ignoresSafeArea()
            case .constellationMaker:
                SimplifiedConstellationGameView()
                    .environmentObject(motionService)
                    .environmentObject(backendService)
                    .ignoresSafeArea()
            case .makeYourOwn:
                MakeYourOwnGameView(
                    score: $gameScore,
                    reps: $repsCompleted,
                    rom: $currentROM,
                    isActive: $gameStarted
                )
                .environmentObject(motionService)
                .environmentObject(backendService)
                .ignoresSafeArea()
            
            }
        }
        .onAppear {
            setupAndStartGame()
        }
        .onDisappear {
            stopGame()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FruitSlicerGameEnded"))) { note in
            handleGameEnded(userInfo: note.userInfo, gameType: .fruitSlicer)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FollowCircleGameEnded"))) { note in
            FlexaLog.ui.info("📥 [CleanHost] FollowCircleGameEnded notification received")
            handleGameEnded(userInfo: note.userInfo, gameType: .followCircle)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("WitchBrewGameEnded"))) { note in
            FlexaLog.ui.warning("📥 [CleanHost] Legacy WitchBrewGameEnded notification received — mapping to Follow Circle")
            handleGameEnded(userInfo: note.userInfo, gameType: .followCircle)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ConstellationGameEnded"))) { note in
            handleGameEnded(userInfo: note.userInfo, gameType: .constellationMaker)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MountainGameEnded"))) { note in
            handleGameEnded(userInfo: note.userInfo, gameType: .wallClimbers)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FanFlameGameEnded"))) { note in
            handleGameEnded(userInfo: note.userInfo, gameType: .fanOutFlame)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("BalloonPopGameEnded"))) { note in
            handleGameEnded(userInfo: note.userInfo, gameType: .balloonPop)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MakeYourOwnGameEnded"))) { note in
            FlexaLog.ui.info("📥 [CleanHost] MakeYourOwnGameEnded notification received")
            handleGameEnded(userInfo: note.userInfo, gameType: .makeYourOwn)
        }
    }
    
    private func handleGameEnded(userInfo: [AnyHashable : Any]?, gameType: GameType) {
        FlexaLog.ui.info("📦 [CleanHost] handleGameEnded invoked for \(gameType.displayName, privacy: .public) — keys=\(userInfo?.keys.map { "\($0)" }.joined(separator: ",") ?? "nil", privacy: .public)")

        guard let ui = userInfo else {
            FlexaLog.ui.error("⚠️ [CleanHost] handleGameEnded called with nil userInfo")
            return
        }

        var resolvedSession: ExerciseSessionData?

        if let session = ui["exerciseSession"] as? ExerciseSessionData {
            resolvedSession = session
        } else if let encoded = ui["sessionDataJSON"] as? Data {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            if let decoded = try? decoder.decode(ExerciseSessionData.self, from: encoded) {
                resolvedSession = decoded
            } else {
                FlexaLog.ui.error("⚠️ [CleanHost] Failed to decode sessionDataJSON payload")
            }
        }

        if resolvedSession == nil {
            guard let score = ui["score"] as? Int,
                  let reps = ui["reps"] as? Int,
                  let maxROM = ui["maxROM"] as? Double,
                  let sparc = ui["sparcScore"] as? Double else {
                FlexaLog.ui.error("⚠️ [CleanHost] handleGameEnded missing core payload — userInfo=\(String(describing: userInfo), privacy: .public)")
                return
            }

            let romPerRepRaw = ui["romPerRep"] as? [Double] ?? []
            let sparcHistoryRaw = ui["sparcHistory"] as? [Double] ?? []
            let romPerRep = romPerRepRaw.filter { $0.isFinite }
            let sparcHistory = sparcHistoryRaw.filter { $0.isFinite }
            let safeMaxROM = maxROM.isFinite ? maxROM : 0
            let safeSparcScore = sparc.isFinite ? sparc : 0
            let duration = (ui["duration"] as? Double).map { max($0, 0) } ?? 90.0
            let timestamp = (ui["timestamp"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? Date()
            let repTimestampIntervals = ui["repTimestamps"] as? [Double] ?? []
            let repTimestamps = repTimestampIntervals.map { Date(timeIntervalSince1970: $0) }

            let sparcTimelineRaw = ui["sparcDataPoints"] as? [[String: Any]] ?? []
            let sparcPoints: [SPARCPoint] = sparcTimelineRaw.compactMap { point in
                guard let rawTime = point["timestamp"] as? Double,
                      let value = point["sparc"] as? Double else { return nil }
                return SPARCPoint(sparc: value, timestamp: Date(timeIntervalSince1970: rawTime))
            }

            let romTimelineRaw = ui["romDataPoints"] as? [[String: Any]] ?? []
            let romPoints: [ROMPoint] = romTimelineRaw.compactMap { point in
                guard let rawTime = point["timestamp"] as? Double,
                      let angle = point["angle"] as? Double else { return nil }
                return ROMPoint(angle: angle, timestamp: Date(timeIntervalSince1970: rawTime))
            }

            resolvedSession = ExerciseSessionData(
                exerciseType: gameType.displayName,
                score: score,
                reps: reps,
                maxROM: safeMaxROM,
                duration: duration,
                timestamp: timestamp,
                romHistory: romPerRep,
                repTimestamps: repTimestamps,
                sparcHistory: sparcHistory,
                romData: romPoints,
                sparcData: sparcPoints,
                sparcScore: safeSparcScore
            )

            FlexaLog.ui.info("📦 [CleanHost] Legacy payload converted → duration=\(String(format: "%.1f", duration), privacy: .public)s sparcPoints=\(sparcPoints.count, privacy: .public)")
        }

        guard let sessionData = resolvedSession else {
            FlexaLog.ui.error("⚠️ [CleanHost] Unable to resolve session payload for \(gameType.displayName, privacy: .public)")
            return
        }

        let normalizedSession = ExerciseSessionData(
            id: sessionData.id,
            exerciseType: sessionData.exerciseType.isEmpty ? gameType.displayName : sessionData.exerciseType,
            score: sessionData.score,
            reps: sessionData.reps,
            maxROM: sessionData.maxROM,
            averageROM: sessionData.averageROM,
            duration: max(sessionData.duration, 0.5),
            timestamp: sessionData.timestamp,
            romHistory: sessionData.romHistory,
            repTimestamps: sessionData.repTimestamps,
            sparcHistory: sessionData.sparcHistory,
            romData: sessionData.romData,
            sparcData: sessionData.sparcData,
            aiScore: sessionData.aiScore,
            painPre: sessionData.painPre,
            painPost: sessionData.painPost,
            sparcScore: sessionData.sparcScore,
            formScore: sessionData.formScore,
            consistency: sessionData.consistency,
            peakVelocity: sessionData.peakVelocity,
            motionSmoothnessScore: sessionData.motionSmoothnessScore,
            accelAvgMagnitude: sessionData.accelAvgMagnitude,
            accelPeakMagnitude: sessionData.accelPeakMagnitude,
            gyroAvgMagnitude: sessionData.gyroAvgMagnitude,
            gyroPeakMagnitude: sessionData.gyroPeakMagnitude,
            aiFeedback: sessionData.aiFeedback,
            goalsAfter: sessionData.goalsAfter
        )

        self.sessionData = normalizedSession
        // Update goals/streaks immediately so the goal circle increments after any session
        goalsService.recordExerciseSession(normalizedSession)
        goalsService.refreshGoals()
        FlexaLog.ui.info("📦 [CleanHost] SessionData ready — exercise=\(normalizedSession.exerciseType, privacy: .public) duration=\(String(format: "%.1f", normalizedSession.duration), privacy: .public)s reps=\(normalizedSession.reps, privacy: .public)")
        navigationCoordinator.showAnalyzing(sessionData: normalizedSession)
    }
    
    private func setupAndStartGame() {
        // Games handle their own motion service setup
        timeRemaining = 90 // Match game duration
        // Save pre-survey at session start - using direct LocalDataManager
        // Session file saving removed
        gameStarted = true
        startGameTimer()
    FlexaLog.ui.info("▶️ [CleanHost] Game started — type=\(gameType.displayName, privacy: .public) preSurveyPain=\(preSurveyData.painLevel, privacy: .public)")
    }
    
    private func stopGame() {
        gameStarted = false
        countdownTimer?.invalidate()
        countdownTimer = nil
        Task { @MainActor in
            motionService.stopSession()
        }
    FlexaLog.ui.info("⏹️ [CleanHost] stopGame invoked — type=\(gameType.displayName, privacy: .public) score=\(gameScore, privacy: .public) reps=\(repsCompleted, privacy: .public)")
        
        sessionData = ExerciseSessionData(
            exerciseType: gameType.displayName,
            score: gameScore,
            reps: repsCompleted,
            maxROM: maxROM,
            duration: 90 - TimeInterval(timeRemaining)
        )
    }
    
    private func startGameTimer() {
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if timeRemaining > 0 && gameStarted {
                timeRemaining -= 1
                
                // Update max ROM
                if currentROM > maxROM {
                    maxROM = currentROM
                }
            } else {
                timer.invalidate()
                gameStarted = false
                stopGame()
                // Only present analyzing if the hosted game didn't send a session payload
                if self.sessionData == nil {
                    self.sessionData = ExerciseSessionData(
                        exerciseType: gameType.displayName,
                        score: gameScore,
                        reps: repsCompleted,
                        maxROM: maxROM,
                        duration: 90 - TimeInterval(timeRemaining)
                    )
                    if let sessionData = self.sessionData {
                        navigationCoordinator.showAnalyzing(sessionData: sessionData)
                    }
                }
            }
        }
    }
    
    private func resetGame() {
        gameScore = 0
        repsCompleted = 0
        currentROM = 0.0
        maxROM = 0.0
        timeRemaining = 90
        gameStarted = false
        sessionData = nil
    }
    
    private func calculateAIScore() -> Int {
        let scoreComponent = min(100, gameScore / 10)
        let romComponent = min(100, Int(maxROM))
        let repsComponent = min(100, repsCompleted * 4)
        
        return (scoreComponent + romComponent + repsComponent) / 3
    }
    
    private func generateAIFeedback() -> String {
        let aiScore = calculateAIScore()
        
        switch aiScore {
        case 90...100:
            return "Excellent performance! Your form and range of motion were outstanding."
        case 75...89:
            return "Great job! You showed good control and consistency throughout the exercise."
        case 60...74:
            return "Good effort! Focus on maintaining steady movements and full range of motion."
        case 40...59:
            return "Keep practicing! Try to move more smoothly and reach your full range of motion."
        default:
            return "Good start! Remember to move slowly and focus on proper form over speed."
        }
    }
}

// Clean game views without extra UI elements
struct CleanFruitSlicerView: View {
    @Binding var score: Int
    @Binding var reps: Int
    @Binding var rom: Double
    @Binding var isActive: Bool
    
    var body: some View {
        // Minimal fruit slicer game
        Text("🍎 🍌 🍊")
            .font(.system(size: 60))
            .opacity(isActive ? 1.0 : 0.5)
    }
}

struct CleanArmRaiseView: View {
    @Binding var score: Int
    @Binding var reps: Int
    @Binding var rom: Double
    @Binding var isActive: Bool
    
    var body: some View {
        VStack {
            Text("↑")
                .font(.system(size: 80))
                .foregroundColor(.blue)
                .opacity(isActive ? 1.0 : 0.5)
            
            Text("Raise your arms")
                .font(.headline)
                .foregroundColor(.white)
        }
    }
}

struct CleanBalloonPopView: View {
    @Binding var score: Int
    @Binding var reps: Int
    @Binding var rom: Double
    @Binding var isActive: Bool
    
    var body: some View {
        Text("🎈 🎈 🎈")
            .font(.system(size: 60))
            .opacity(isActive ? 1.0 : 0.5)
    }
}

struct CleanGenericGameView: View {
    let gameType: GameType
    @Binding var score: Int
    @Binding var reps: Int
    @Binding var rom: Double
    @Binding var isActive: Bool
    
    var body: some View {
        VStack {
            Image(systemName: gameType.icon)
                .font(.system(size: 80))
                .foregroundColor(gameType.color)
                .opacity(isActive ? 1.0 : 0.5)
            
            Text(gameType.displayName)
                .font(.headline)
                .foregroundColor(.white)
        }
    }
}

#Preview {
    CleanGameHostView(
        gameType: GameType.fruitSlicer,
        preSurveyData: PreSurveyData(painLevel: 0, timestamp: Date(), exerciseReadiness: nil, previousExerciseHours: nil) // painLevel kept for compatibility
    )
}
