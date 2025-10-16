
import SwiftUI
import Combine

enum NavigationPath: View, Hashable {
    case instructions(GameType)
    case game(GameType, PreSurveyData)
    case customExerciseCreator
    case customExerciseGame(CustomExercise)
    case analyzing(ExerciseSessionData)
    case results(ExerciseSessionData)

    @ViewBuilder
    var body: some View {
        switch self {
        case .instructions(let gameType):
            GameInstructionsView(gameType: gameType)
        case .game(let gameType, let preSurveyData):
            CleanGameHostView(gameType: gameType, preSurveyData: preSurveyData)
        case .customExerciseCreator:
            CustomExerciseCreatorView()
        case .customExerciseGame(let exercise):
            CustomExerciseGameView(exercise: exercise)
        case .analyzing(let sessionData):
            AnalyzingView(sessionData: sessionData)
        case .results(let sessionData):
            ResultsView(sessionData: sessionData)
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .instructions(let gameType):
            hasher.combine(gameType)
        case .game(let gameType, _):
            hasher.combine(gameType)
            hasher.combine("game")
        case .customExerciseCreator:
            hasher.combine("customExerciseCreator")
        case .customExerciseGame(let exercise):
            hasher.combine(exercise.id)
            hasher.combine("customExerciseGame")
        case .analyzing(_):
            hasher.combine("analyzing")
        case .results(_):
            hasher.combine("results")
        }
    }

    static func == (lhs: NavigationPath, rhs: NavigationPath) -> Bool {
        lhs.hashValue == rhs.hashValue
    }
}

class NavigationCoordinator: ObservableObject {
    static let shared = NavigationCoordinator()
    @Published var path = [NavigationPath]()

    private func performOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async {
                work()
            }
        }
    }

    func showInstructions(for gameType: GameType) {
        performOnMain { [self] in
            print("🧭 [Navigation] → Instructions for \(gameType)")
            self.path.append(.instructions(gameType))
            print("🧭 [Navigation] Path depth: \(self.path.count)")
        }
    }

    func startGame(gameType: GameType, preSurveyData: PreSurveyData) {
        performOnMain { [self] in
            print("🧭 [Navigation] → Game: \(gameType) (pain: \(preSurveyData.painLevel))")
            self.path.append(.game(gameType, preSurveyData))
            print("🧭 [Navigation] Path depth: \(self.path.count)")
        }
    }

    func showResults(sessionData: ExerciseSessionData) {
        performOnMain { [self] in
            print("🧭 [Navigation] → Results (reps: \(sessionData.reps), maxROM: \(sessionData.maxROM)°)")
            // If we're currently showing the analyzing view, replace it with results
            if let last = self.path.last {
                switch last {
                case .analyzing(_):
                    self.path.removeLast()
                    self.path.append(.results(sessionData))
                    print("🧭 [Navigation] Replaced analyzing with results (depth: \(self.path.count))")
                default:
                    self.path.append(.results(sessionData))
                    print("🧭 [Navigation] Path depth: \(self.path.count)")
                }
            } else {
                self.path.append(.results(sessionData))
                print("🧭 [Navigation] Path depth: \(self.path.count)")
            }
        }
    }

    func showAnalyzing(sessionData: ExerciseSessionData) {
        performOnMain { [self] in
            print("🧭 [Navigation] → Analyzing (reps: \(sessionData.reps), maxROM: \(sessionData.maxROM)°)")
            self.path.append(.analyzing(sessionData))
            print("🧭 [Navigation] Path depth: \(self.path.count)")
        }
    }

    func goHome() {
        performOnMain { [self] in
            print("🧭 [Navigation] → Home (clearing \(self.path.count) views)")
            self.path.removeAll()
            // Switch to Home tab (index 0) for instant navigation
            NotificationCenter.default.post(name: NSNotification.Name("NavigateToTab"), object: nil, userInfo: ["tabIndex": 0])
        }
    }

    func pop() {
        performOnMain { [self] in
            print("🧭 [Navigation] ← Pop (from depth \(self.path.count))")
            if !self.path.isEmpty {
                self.path.removeLast()
            }
            print("🧭 [Navigation] Path depth: \(self.path.count)")
        }
    }
    
    func clearAll() {
        performOnMain { [self] in
            print("🧭 [Navigation] 🗑️ Clearing all navigation paths (was \(self.path.count) deep)")
            self.path.removeAll()
            print("🧭 [Navigation] ✅ Navigation stack cleared")
        }
    }
    
    // Show calibration wizard if available in app
    func showCalibrationWizard() {
        performOnMain {
            print("🧭 [Navigation] → Calibration Wizard")
            NotificationCenter.default.post(name: NSNotification.Name("ShowCalibrationWizard"), object: nil)
        }
    }
    
    // Navigate to custom exercise creator
    func showCustomExerciseCreator() {
        performOnMain { [self] in
            print("🧭 [Navigation] → Custom Exercise Creator")
            self.path.append(.customExerciseCreator)
            print("🧭 [Navigation] Path depth: \(self.path.count)")
        }
    }
    
    // Navigate to custom exercise game
    func showCustomExerciseGame(exercise: CustomExercise) {
        performOnMain { [self] in
            print("🧭 [Navigation] → Custom Exercise Game: \(exercise.name)")
            self.path.append(.customExerciseGame(exercise))
            print("🧭 [Navigation] Path depth: \(self.path.count)")
        }
    }
    
    // Map results exerciseType (display name) to GameType for instant routing
    static func mapExerciseNameToGameType(_ name: String) -> GameType {
        if let mapped = GameType.fromDisplayName(name) {
            return mapped
        }
        if name.lowercased().hasPrefix("make your own") { return .makeYourOwn }
        return .fruitSlicer
    }
    
    private func buildComprehensiveSession(sessionData: ExerciseSessionData, analysis: ExerciseAnalysis, preSurvey: PreSurveyData, postSurvey: PostSurveyData?) -> ComprehensiveSessionData {
    // Prefer actual rep timestamps if available from motion service
    let repTimestamps = SimpleMotionService.shared.romPerRepTimestampsDates
        // Use REAL SPARC data points with actual timestamps instead of fake ones
    let sparcPoints = SimpleMotionService.shared.sparcService.getSPARCDataPoints()
        let perf = ExercisePerformanceData(
            score: sessionData.score,
            reps: sessionData.reps,
            duration: sessionData.duration,
            romData: sessionData.romHistory,
            romPerRep: sessionData.romHistory,
            repTimestamps: repTimestamps,
            sparcDataPoints: sparcPoints,
            movementQualityScores: Array(repeating: 0, count: max(1, sessionData.romHistory.count)),
            aiScore: sessionData.aiScore ?? analysis.overallPerformance,
            aiFeedback: analysis.specificFeedback,
            sparcScore: sessionData.sparcHistory.last ?? 0.0,
            gameSpecificData: "{}",
            accelAvg: nil, accelPeak: nil, gyroAvg: nil, gyroPeak: nil
        )
        let goalsBefore = LocalDataManager.shared.getCachedGoals()
        let sessionNumber = LocalDataManager.shared.nextSessionNumber()
        let streak = LocalDataManager.shared.getCachedStreak()
        
        return ComprehensiveSessionData(
            userID: "local",
            sessionNumber: sessionNumber,
            exerciseName: sessionData.exerciseType,
            duration: sessionData.duration,
            performanceData: perf,
            preSurvey: preSurvey,
            postSurvey: postSurvey,
            goalsBefore: goalsBefore,
            goalsAfter: goalsBefore, // Will be updated by goals system
            streakAtSession: streak
        )
    }
}
