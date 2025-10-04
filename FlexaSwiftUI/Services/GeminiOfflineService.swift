import Foundation
import Combine

class GeminiOfflineService: ObservableObject {
    @Published var isOfflineMode = false
    
    private let networkMonitor = NetworkMonitor()
    private var cancellables = Set<AnyCancellable>()
    
    // Offline AI analysis patterns
    private let offlineAnalysisTemplates = [
        "excellent": "Excellent form! Your movement shows great control and consistency.",
        "good": "Good technique overall. Focus on maintaining steady rhythm throughout.",
        "fair": "Fair performance. Try to keep movements smooth and controlled.",
        "needs_improvement": "Room for improvement. Focus on proper form over speed."
    ]
    
    init() {
        setupNetworkObserver()
    }
    
    private func setupNetworkObserver() {
        networkMonitor.$isConnected
            .sink { [weak self] isConnected in
                self?.isOfflineMode = !isConnected
                print("Gemini mode: \(isConnected ? "Online" : "Offline fallback")")
            }
            .store(in: &cancellables)
    }
    
    func analyzeExerciseSession(
        exerciseType: String,
        reps: Int,
        maxROM: Double,
        averageSPARC: Double,
        duration: TimeInterval
    ) async -> String {
        
        // Use online Gemini if available
        if networkMonitor.isConnected {
            return await performOnlineAnalysis(
                exerciseType: exerciseType,
                reps: reps,
                maxROM: maxROM,
                averageSPARC: averageSPARC,
                duration: duration
            )
        }
        
        // Fallback to offline analysis
        return generateOfflineAnalysis(
            exerciseType: exerciseType,
            reps: reps,
            maxROM: maxROM,
            averageSPARC: averageSPARC,
            duration: duration
        )
    }
    
    private func performOnlineAnalysis(
        exerciseType: String,
        reps: Int,
        maxROM: Double,
        averageSPARC: Double,
        duration: TimeInterval
    ) async -> String {
        // TODO: Implement actual Gemini API call
        print("🌐 Using online Gemini analysis")
        
        // Simulate network delay
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        let romText = String(format: "%.1f", maxROM)
        let smoothnessText = String(format: "%.0f", averageSPARC)
        return "Online AI analysis: Your \(exerciseType) session showed \(reps) reps with \(romText)° ROM and smoothness score of \(smoothnessText). Great work!"
    }
    
    private func generateOfflineAnalysis(
        exerciseType: String,
        reps: Int,
        maxROM: Double,
        averageSPARC: Double,
        duration: TimeInterval
    ) -> String {
        print("📱 Using offline AI analysis fallback")
        
        // Simple rule-based analysis
        var score = 0.0
        var feedback: [String] = []
        
        // ROM analysis
        if maxROM >= 120 {
            score += 0.4
            feedback.append("excellent range of motion")
        } else if maxROM >= 90 {
            score += 0.3
            feedback.append("good range of motion")
        } else {
            score += 0.1
            feedback.append("limited range of motion - try to extend further")
        }
        
        // SPARC analysis (higher is smoother)
        if averageSPARC >= 80 {
            score += 0.3
            feedback.append("very smooth movements")
        } else if averageSPARC >= 60 {
            score += 0.2
            feedback.append("fairly smooth technique")
        } else {
            score += 0.1
            feedback.append("work on smoother, more controlled movements")
        }
        
        // Rep count analysis
        if reps >= 10 {
            score += 0.3
            feedback.append("great rep count")
        } else if reps >= 5 {
            score += 0.2
            feedback.append("solid effort")
        } else {
            score += 0.1
            feedback.append("try for more repetitions next time")
        }
        
        // Generate final assessment
        let category = score >= 0.8 ? "excellent" : score >= 0.6 ? "good" : score >= 0.4 ? "fair" : "needs_improvement"
        let template = offlineAnalysisTemplates[category] ?? offlineAnalysisTemplates["fair"]!
        
        return "\(template) Your \(exerciseType) session: \(reps) reps, \(String(format: "%.1f", maxROM))° ROM. \(feedback.joined(separator: ", ").capitalized)."
    }
}
