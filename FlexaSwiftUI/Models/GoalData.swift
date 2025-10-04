import Foundation
import SwiftUI

// MARK: - Goal Types
enum GoalType: String, CaseIterable, Identifiable, Codable {
    case sessions = "sessions"
    case rom = "rom"
    case smoothness = "smoothness"
    case aiScore = "aiScore"
    case painImprovement = "painImprovement"
    case totalReps = "totalReps"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .sessions: return "Sessions"
        case .rom: return "ROM"
        case .smoothness: return "Smoothness"
        case .aiScore: return "AI Score"
        case .painImprovement: return "Pain Improvement"
        case .totalReps: return "Total Reps"
        }
    }

    var metricDisplayName: String {
        switch self {
        case .rom:
            return "Average Range of Motion"
        case .smoothness:
            return "Average Smoothness"
        default:
            return displayName
        }
    }
    
    var icon: String {
        switch self {
        case .sessions: return "figure.walk"
        case .rom: return "arrow.up.and.down.circle"
        case .smoothness: return "waveform.path"
        case .aiScore: return "brain.head.profile"
        case .painImprovement: return "heart.text.square"
        case .totalReps: return "number.circle"
        }
    }
    
    var unit: String {
        switch self {
        case .sessions: return "sessions"
        case .rom: return "°"
        case .smoothness: return "score"
        case .aiScore: return "points"
        case .painImprovement: return "points"
        case .totalReps: return "reps"
        }
    }
    
    var color: Color {
        switch self {
        case .sessions: return .blue
        case .rom: return .green
        case .smoothness: return .purple
        case .aiScore: return .orange
        case .painImprovement: return .red
        case .totalReps: return .cyan
        }
    }
    
    var isMainGoal: Bool {
        return [.sessions, .rom, .smoothness].contains(self)
    }
}

// MARK: - Goal Data Model
struct GoalData: Identifiable, Codable {
    let id: UUID
    let type: GoalType
    var targetValue: Double
    var currentValue: Double
    var isEnabled: Bool
    
    init(type: GoalType, targetValue: Double, currentValue: Double = 0, isEnabled: Bool = true) {
        self.id = UUID()
        self.type = type
        self.targetValue = targetValue
        self.currentValue = currentValue
        self.isEnabled = isEnabled
    }
    
    var progress: Double {
        guard targetValue > 0 else { return 0 }
        return min(currentValue / targetValue, 1.0)
    }
    
    var isCompleted: Bool {
        return currentValue >= targetValue
    }
    
    var progressText: String {
        switch type {
        case .smoothness:
            // Display on 0–100 integer scale
            let cur = Int(currentValue.rounded())
            let tar = Int(targetValue.rounded())
            return "\(cur)/\(tar)"
        case .rom:
            // Whole degrees only
            let cur = Int(currentValue.rounded())
            let tar = Int(targetValue.rounded())
            return "\(cur)/\(tar)"
        default:
            return "\(Int(currentValue))/\(Int(targetValue))"
        }
    }
}

// MARK: - Goals Service
class GoalsService: ObservableObject {
    @Published var goals: [GoalData] = []
    
    init() {
        loadGoals()
    }
    
    func loadGoals() {
        // Use LocalDataManager for consistency with the rest of the app
        let localData = LocalDataManager.shared
        let userGoals = localData.getCachedGoals()
        
        // Convert UserGoals to GoalData array
        self.goals = [
            GoalData(type: .sessions, targetValue: Double(userGoals.dailyReps), currentValue: 0),
            GoalData(type: .rom, targetValue: userGoals.targetROM, currentValue: 0),
            GoalData(type: .smoothness, targetValue: userGoals.targetSmoothness * 100.0, currentValue: 0),
            GoalData(type: .aiScore, targetValue: userGoals.targetAIScore, currentValue: 0, isEnabled: userGoals.targetAIScore > 0),
            GoalData(type: .painImprovement, targetValue: userGoals.targetPainImprovement, currentValue: 0, isEnabled: userGoals.targetPainImprovement > 0),
            GoalData(type: .totalReps, targetValue: Double(userGoals.weeklyReps), currentValue: 0, isEnabled: userGoals.weeklyReps > 0)
        ]
    }
    
    func saveGoals() {
        // Convert GoalData array back to UserGoals and save via LocalDataManager
        let userGoals = UserGoals(
            dailyReps: Int(goals.first { $0.type == .sessions }?.targetValue ?? 7),
            weeklyMinutes: Int(goals.first { $0.type == .sessions }?.targetValue ?? 7) * 15, // Estimate
            targetROM: goals.first { $0.type == .rom }?.targetValue ?? 90.0,
            targetSmoothness: (goals.first { $0.type == .smoothness }?.targetValue ?? 80.0) / 100.0,
            targetAIScore: goals.first { $0.type == .aiScore }?.targetValue ?? 0,
            targetPainImprovement: goals.first { $0.type == .painImprovement }?.targetValue ?? 0,
            weeklyReps: Int(goals.first { $0.type == .totalReps }?.targetValue ?? 50)
        )
        LocalDataManager.shared.saveGoals(userGoals)
    }
    
    func updateGoal(type: GoalType, targetValue: Double) {
        if let index = goals.firstIndex(where: { $0.type == type }) {
            goals[index].targetValue = targetValue
            saveGoals()
        }
    }
    
    func updateProgress(type: GoalType, currentValue: Double) {
        if let index = goals.firstIndex(where: { $0.type == type }) {
            goals[index].currentValue = currentValue
            saveGoals()
        }
    }
    
    func toggleGoal(type: GoalType) {
        if let index = goals.firstIndex(where: { $0.type == type }) {
            goals[index].isEnabled.toggle()
            saveGoals()
        }
    }
    
    func getGoal(type: GoalType) -> GoalData? {
        return goals.first { $0.type == type }
    }
    
    func getMainGoals() -> [GoalData] {
        return goals.filter { $0.type.isMainGoal && $0.isEnabled }
    }
    
    func getAdditionalGoals() -> [GoalData] {
        return goals.filter { !$0.type.isMainGoal }
    }
    
    func updateProgressFromSession(_ session: ExerciseSessionData) {
        // Get today's sessions from LocalDataManager for accurate progress calculation
        let localData = LocalDataManager.shared
        let todaySessions = localData.getTodaySessions()
        
        // Update sessions count
        if let sessionsIndex = goals.firstIndex(where: { $0.type == .sessions }) {
            goals[sessionsIndex].currentValue = Double(todaySessions.count)
        }
        
        // Update ROM (calculate average ROM per rep across all sessions today)
        if let romIndex = goals.firstIndex(where: { $0.type == .rom }) {
            let totalReps = todaySessions.reduce(0) { $0 + $1.reps }
            let totalROMSum = todaySessions.reduce(0.0) { $0 + ($1.maxROM * Double($1.reps)) }
            goals[romIndex].currentValue = totalReps > 0 ? totalROMSum / Double(totalReps) : 0
        }
        
        // Update smoothness (use SPARC score directly 0-100 and keep best)
        if let smoothnessIndex = goals.firstIndex(where: { $0.type == .smoothness }) {
            let sparcScore = max(0, min(100, session.sparcScore))
            goals[smoothnessIndex].currentValue = max(goals[smoothnessIndex].currentValue, sparcScore)
        }
        
        // Update total reps
        if let repsIndex = goals.firstIndex(where: { $0.type == .totalReps }) {
            goals[repsIndex].currentValue = Double(todaySessions.reduce(0) { $0 + $1.reps })
        }
        
        // Don't save here - let GoalsAndStreaksService handle the saving
        // This prevents duplicate saves and keeps data consistent
    }
    
    func resetDailyProgress() {
        // Reset current values to 0 - they'll be recalculated from today's sessions
        for index in goals.indices {
            goals[index].currentValue = 0
        }
        // Don't save here - let GoalsAndStreaksService handle the saving
    }
    
    func refreshGoals() {
        // Reload goals from LocalDataManager to stay in sync
        loadGoals()
    }
}
