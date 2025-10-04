import SwiftUI

// Simple navigation manager using @Published and environment objects
class NavigationManager: ObservableObject {
    @Published var currentTab: Int = 0
    @Published var showingGame: GameType?
    @Published var showingInstructions: GameType?
    @Published var showingResults: ExerciseSessionData?
    @Published var showingAnalyzing: ExerciseSessionData?
    @Published var showingPostSurvey: ExerciseSessionData?
    
    // Navigation methods
    func navigateToHome() {
        currentTab = 0
        dismissAll()
    }
    
    func navigateToGames() {
        currentTab = 1
        dismissAll()
    }
    
    func navigateToProgress() {
        currentTab = 2
        dismissAll()
    }
    
    func navigateToSettings() {
        currentTab = 3
        dismissAll()
    }
    
    func showInstructions(for gameType: GameType) {
        showingInstructions = gameType
    }
    
    func startGame(_ gameType: GameType) {
        showingGame = gameType
        showingInstructions = nil
    }
    
    func showAnalyzing(_ sessionData: ExerciseSessionData) {
        showingAnalyzing = sessionData
    }
    
    func showResults(_ sessionData: ExerciseSessionData) {
        showingResults = sessionData
        showingAnalyzing = nil
    }
    
    func showPostSurvey(_ sessionData: ExerciseSessionData) {
        showingPostSurvey = sessionData
    }
    
    func dismissAll() {
        showingGame = nil
        showingInstructions = nil
        showingResults = nil
        showingAnalyzing = nil
        showingPostSurvey = nil
    }
    
    func dismissGame() {
        showingGame = nil
    }
    
    func returnToGames() {
        dismissAll()
        currentTab = 1
    }
}
