import Foundation
import Combine
 import CryptoKit
class RecommendationsEngine: ObservableObject {
    @Published var recommendations: [Recommendation] = []
    @Published var isGenerating = false
    @Published var lastUpdatedAt: Date?
    
    private var geminiService: GeminiService?
    private let firebaseService = FirebaseService()
    // Caching to avoid redundant API calls
    private var lastSignature: String?
    private var lastGeneratedAt: Date?
    private let cooldown: TimeInterval = 60
    
    func generatePersonalizedRecommendations(force: Bool = false) async {
        // Prevent duplicate concurrent generations unless forced
        let currentlyGenerating = await MainActor.run { self.isGenerating }
        if currentlyGenerating && !force { return }
        await MainActor.run {
            self.isGenerating = true
            if self.geminiService == nil { self.geminiService = GeminiService() }
        }
        
        do {
            // Use local data only to avoid Firebase read hangs on UI
            let sessions = LocalDataManager.shared.getStoredSessions()
            let goals = LocalDataManager.shared.getStoredGoals() ?? UserGoals()
            
            // Skip if nothing changed recently
            let signature = computeSignature(sessions: sessions, goals: goals)
            let now = Date()
            if !force,
               let lastSig = lastSignature,
               let lastAt = lastGeneratedAt,
               lastSig == signature,
               now.timeIntervalSince(lastAt) < cooldown {
                await MainActor.run { self.isGenerating = false }
                return
            }
            
            // Try AI recommendations but don't fail the whole flow if AI errors
            var aiRecommendations: [Recommendation] = []
            do {
                aiRecommendations = try await geminiService!.generateRecommendations(for: sessions, goals: goals)
            } catch {
                print("Gemini recommendation generation failed, falling back to rule-based only: \(error)")
            }
            
            // Rule-based recommendations
            let ruleBasedRecommendations = generateRuleBasedRecommendations(sessions: sessions, goals: goals)
            
            // Combine, dedupe and prioritize
            let allRecommendations = aiRecommendations + ruleBasedRecommendations
            let uniqueRecommendations = deduplicateByTitle(allRecommendations)
            let prioritizedRecommendations = prioritizeRecommendations(uniqueRecommendations)
            
            await MainActor.run {
                self.recommendations = Array(prioritizedRecommendations.prefix(8))
                self.isGenerating = false
                self.lastSignature = signature
                self.lastGeneratedAt = now
                self.lastUpdatedAt = now
            }
            
        } catch {
            print("Error generating recommendations: \(error)")
            await MainActor.run {
                // Provide a minimal fallback item so the UI isn't empty
                self.recommendations = [
                    Recommendation(
                        type: .goalAdjustment,
                        title: "Set Your Goals",
                        description: "Open the goals screen to personalize your plan and unlock better recommendations.",
                        priority: .medium,
                        estimatedBenefit: "Better personalization"
                    )
                ]
                self.isGenerating = false
                self.lastUpdatedAt = Date()
            }
        }
    }
    
    private func generateRuleBasedRecommendations(sessions: [ExerciseSessionData], goals: UserGoals) -> [Recommendation] {
        var recommendations: [Recommendation] = []
        
        // Analyze recent performance
        let recentSessions = sessions.prefix(7)
        let avgROM = recentSessions.map(\.maxROM).reduce(0, +) / Double(max(recentSessions.count, 1))
        let avgReps: Double = Double(recentSessions.map(\.reps).reduce(0, +)) / Double(max(recentSessions.count, 1))
        
        // Enhanced analytics for comprehensive sessions
        let comprehensiveMetrics = analyzeComprehensiveMetrics(sessions: Array(recentSessions))
        
        // ROM-based recommendations with advanced analytics
        if avgROM < goals.targetROM * 0.7 {
            let priority: RecommendationPriority = comprehensiveMetrics.consistencyScore < 50 ? .high : .medium
            recommendations.append(Recommendation(
                type: .exerciseModification,
                title: "Focus on Range of Motion",
                description: "Your recent ROM is below target. Try slower, more controlled movements and gentle stretching before exercises.",
                priority: priority,
                estimatedBenefit: "Improve flexibility by 15-20%"
            ))
        }
        
        // Fatigue-based recommendations
        if comprehensiveMetrics.avgFatigueIndex > 60 {
            recommendations.append(Recommendation(
                type: .restDay,
                title: "Manage Exercise Fatigue",
                description: "Your fatigue index indicates declining performance during sessions. Consider shorter sessions or rest days.",
                priority: .high,
                estimatedBenefit: "Prevent overexertion and injury"
            ))
        }
        
        // Efficiency recommendations
        if comprehensiveMetrics.avgEfficiency < 40 {
            recommendations.append(Recommendation(
                type: .exerciseModification,
                title: "Improve Exercise Efficiency",
                description: "Focus on quality over quantity. Take breaks between reps and maintain proper form.",
                priority: .medium,
                estimatedBenefit: "Better results with less effort"
            ))
        }
        
        // Pain management recommendations
        if comprehensiveMetrics.avgPainIncrease > 1 {
            recommendations.append(Recommendation(
                type: .restDay,
                title: "Address Pain Levels",
                description: "Your pain levels are increasing during sessions. Consider gentler exercises or consult a healthcare provider.",
                priority: .high,
                estimatedBenefit: "Prevent injury and improve comfort"
            ))
        }
        
        // Consistency recommendations
        if recentSessions.count < 3 {
            recommendations.append(Recommendation(
                type: .goalAdjustment,
                title: "Build Exercise Consistency",
                description: "Try shorter, more frequent sessions to build a sustainable routine. Even 5-10 minutes daily helps.",
                priority: .high,
                estimatedBenefit: "Establish lasting habits"
            ))
        }
        
        // Game variety recommendations
        let gameTypes = Set(recentSessions.map(\.exerciseType))
        if gameTypes.count < 3 {
            recommendations.append(Recommendation(
                type: .newGame,
                title: "Try Different Exercises",
                description: "Varying your exercises targets different muscle groups and prevents plateaus.",
                priority: .medium,
                estimatedBenefit: "Comprehensive muscle development"
            ))
        }
        
        // Performance-based recommendations
        if avgReps < Double(goals.dailyReps) * 0.6 {
            recommendations.append(Recommendation(
                type: .exerciseModification,
                title: "Gradual Rep Increase",
                description: "Slowly increase repetitions by 2-3 per session to build endurance safely.",
                priority: .medium,
                estimatedBenefit: "Build strength progressively"
            ))
        }
        
        // Recovery recommendations
        let lastSession = sessions.first?.timestamp ?? Date.distantPast
        let daysSinceLastSession = Calendar.current.dateComponents([.day], from: lastSession, to: Date()).day ?? 0
        
        if daysSinceLastSession > 2 {
            recommendations.append(Recommendation(
                type: .restDay,
                title: "Gentle Return to Exercise",
                description: "Start with light exercises and shorter sessions after a break to prevent injury.",
                priority: .high,
                estimatedBenefit: "Safe exercise resumption"
            ))
        }
        
        return recommendations
    }
    
    private func analyzeComprehensiveMetrics(sessions: [ExerciseSessionData]) -> ComprehensiveAnalytics {
        var totalEfficiency: Double = 0
        var totalConsistency: Double = 0
        var totalFatigue: Double = 0
        var totalPainChange: Double = 0
        var validSessions = 0
        
        // Note: This analyzes basic ExerciseSessionData. In a real implementation,
        // we'd fetch ComprehensiveSessionData directly for more detailed analytics
        for session in sessions {
            // Estimate efficiency based on available data
            let estimatedEfficiency = calculateEstimatedEfficiency(session: session)
            totalEfficiency += estimatedEfficiency
            
            // Estimate consistency from ROM variance (simplified)
            let estimatedConsistency = 80.0 // Placeholder - would calculate from ROM data
            totalConsistency += estimatedConsistency
            
            // Estimate fatigue (simplified)
            let estimatedFatigue = session.duration > 300 ? 40.0 : 20.0 // Higher fatigue for longer sessions
            totalFatigue += estimatedFatigue
            
            // Calculate pain change if available
            if let painPre = session.painPre, let painPost = session.painPost {
                totalPainChange += Double(painPost - painPre)
            }
            
            validSessions += 1
        }
        
        return ComprehensiveAnalytics(
            avgEfficiency: validSessions > 0 ? totalEfficiency / Double(validSessions) : 0,
            consistencyScore: validSessions > 0 ? totalConsistency / Double(validSessions) : 0,
            avgFatigueIndex: validSessions > 0 ? totalFatigue / Double(validSessions) : 0,
            avgPainIncrease: validSessions > 0 ? totalPainChange / Double(validSessions) : 0
        )
    }
    
    private func calculateEstimatedEfficiency(session: ExerciseSessionData) -> Double {
        // Simplified efficiency calculation based on available data
        let timeEfficiency = Double(session.reps) / (session.duration / 60.0) // reps per minute
        let romEfficiency = session.maxROM / 90.0 // normalized ROM
        return (timeEfficiency / 10.0 + romEfficiency) * 50 // Scale to 0-100
    }
    
    private func computeSignature(sessions: [ExerciseSessionData], goals: UserGoals) -> String {
        let sessionPart = sessions.prefix(10).map { s in
            "\(s.id)|\(s.exerciseType)|\(s.reps)|\(Int(s.maxROM))|\(Int(s.duration))|\(Int(s.timestamp.timeIntervalSince1970))"
        }.joined(separator: ";")
        let goalsPart = "|\(goals.dailyReps)|\(goals.weeklyMinutes)|\(Int(goals.targetROM))|\(goals.preferredGames.joined(separator: ","))"
        let base = sessionPart + goalsPart
        let digest = SHA256.hash(data: Data(base.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    private func deduplicateByTitle(_ recommendations: [Recommendation]) -> [Recommendation] {
        var seen = Set<String>()
        var unique: [Recommendation] = []
        for rec in recommendations {
            if seen.insert(rec.title).inserted { unique.append(rec) }
        }
        return unique
    }
    
    private func prioritizeRecommendations(_ recommendations: [Recommendation]) -> [Recommendation] {
        return recommendations.sorted { first, second in
            // High priority first
            if first.priority != second.priority {
                return first.priority == .high && second.priority != .high
            }
            
            // Then by type importance
            let typeOrder: [RecommendationType] = [.exerciseModification, .goalAdjustment, .newGame, .restDay]
            let firstIndex = typeOrder.firstIndex(of: first.type) ?? typeOrder.count
            let secondIndex = typeOrder.firstIndex(of: second.type) ?? typeOrder.count
            
            return firstIndex < secondIndex
        }
    }
    
    func getRecommendationIcon(for type: RecommendationType) -> String {
        switch type {
        case .exerciseModification: return "figure.strengthtraining.traditional"
        case .goalAdjustment: return "target"
        case .newGame: return "gamecontroller"
        case .restDay: return "bed.double"
        }
    }
    
    func getRecommendationColor(for priority: RecommendationPriority) -> String {
        switch priority {
        case .high: return "red"
        case .medium: return "orange"
        case .low: return "blue"
        }
    }
}

struct ComprehensiveAnalytics {
    let avgEfficiency: Double
    let consistencyScore: Double
    let avgFatigueIndex: Double
    let avgPainIncrease: Double
}
