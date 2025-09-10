import Foundation
import Combine

@MainActor class GeminiService: ObservableObject {
    private var apiKey: String {
        return SecureConfig.shared.geminiAPIKey
    }
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent"
    
    @Published var isAnalyzing = false
    @Published var lastAnalysis: ExerciseAnalysis?
    
    func analyzeExerciseSession(_ session: ExerciseSessionData) async throws -> ExerciseAnalysis {
        isAnalyzing = true
        FlexaLog.gemini.info("Analyze session start — id=\(session.id) game=\(session.exerciseType) reps=\(session.reps) maxROM=\(Int(session.maxROM)) dur=\(Int(session.duration))s")
        defer { isAnalyzing = false }
        
        let prompt = createAnalysisPrompt(for: session)
        let analysis = try await generateAnalysis(prompt: prompt, session: session)
        
        self.lastAnalysis = analysis
        
        FlexaLog.gemini.info("Analyze session success — score=\(analysis.overallPerformance) strengths=\(analysis.strengths.count) improvements=\(analysis.areasForImprovement.count)")
        return analysis
    }
    
    func generateRecommendations(for sessions: [ExerciseSessionData], goals: UserGoals) async throws -> [Recommendation] {
        let prompt = createRecommendationPrompt(sessions: sessions, goals: goals)
        FlexaLog.gemini.info("Generate recommendations start — sessions=\(sessions.count) goals: daily=\(goals.dailyReps) weekly=\(goals.weeklyMinutes) targetROM=\(Int(goals.targetROM))")
        let response = try await callGeminiAPI(prompt: prompt)
        
        let recs = parseRecommendations(from: response)
        FlexaLog.gemini.info("Generate recommendations success — count=\(recs.count)")
        return recs
    }
    
    func analyzeFormAndTechnique(romData: [ROMPoint], gameType: String) async throws -> FormAnalysis {
        let prompt = createFormAnalysisPrompt(romData: romData, gameType: gameType)
        FlexaLog.gemini.info("Form analysis start — game=\(gameType) romPoints=\(romData.count)")
        let response = try await callGeminiAPI(prompt: prompt)
        
        let result = parseFormAnalysis(from: response)
        FlexaLog.gemini.info("Form analysis success — quality=\(result.formQuality.rawValue) consistency=\(result.consistencyScore)")
        return result
    }
    
    private func createAnalysisPrompt(for session: ExerciseSessionData) -> String {
        let romSummary = session.romData.isEmpty ? "No ROM data" : """
        ROM Data: Min: \(session.romData.map(\.angle).min() ?? 0)°, Max: \(session.romData.map(\.angle).max() ?? 0)°, 
        Average: \(session.romData.map(\.angle).reduce(0, +) / Double(session.romData.count))°
        """
        
        return """
        Analyze this exercise session:
        Exercise: \(session.exerciseType)
        Reps: \(session.reps)
        Max ROM: \(session.maxROM)°
        Duration: \(session.duration)s
        SPARC: \(session.sparcScore)
        
        Return JSON with:
        - overallPerformance: score 0-100
        - specificFeedback: "Strengths: [2 brief points]. Areas for improvement: [2 brief points]."
        
        Keep specificFeedback under 30 words total.
        Focus on rehabilitation aspects, proper form, and progressive improvement.
        """
    }
    
    private func createRecommendationPrompt(sessions: [ExerciseSessionData], goals: UserGoals) -> String {
        let sessionSummary = sessions.prefix(10).map { session in
            "\(session.exerciseType): \(session.reps) reps, \(Int(session.maxROM))° ROM"
        }.joined(separator: "\n")
        
        return """
        Based on recent exercise history and goals, provide personalized recommendations:
        
        Goals:
        - Daily reps target: \(goals.dailyReps)
        - Weekly minutes target: \(goals.weeklyMinutes)
        - Target ROM: \(goals.targetROM)°
        
        Recent Sessions:
        \(sessionSummary)
        
        Provide recommendations in JSON format with array of objects containing:
        - type (exercise_modification, goal_adjustment, new_game, rest_day)
        - title (string)
        - description (string)
        - priority (high, medium, low)
        - estimated_benefit (string)
        """
    }
    
    private func createFormAnalysisPrompt(romData: [ROMPoint], gameType: String) -> String {
        let angles = romData.map { "\($0.angle)" }.joined(separator: ",")
        
        return """
        Analyze exercise form for \(gameType) based on ROM progression:
        
        ROM Angles: \(angles)
        
        Provide form analysis in JSON format:
        - form_quality (excellent, good, fair, needs_improvement)
        - consistency_score (1-10)
        - movement_pattern_feedback (string)
        - suggested_corrections (array of strings)
        - injury_risk_assessment (low, medium, high)
        """
    }
    
    private func callGeminiAPI(prompt: String) async throws -> String {
        // Validate API key before making request
        guard !apiKey.isEmpty else {
            FlexaLog.security.error("Gemini API key missing — aborting request")
            throw GeminiError.missingAPIKey
        }
        
        guard let url = URL(string: "\(baseURL)?key=\(apiKey)") else {
            FlexaLog.gemini.error("Invalid Gemini API URL")
            throw GeminiError.invalidURL
        }
        
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        FlexaLog.gemini.info("Request ➜ promptLen=\(prompt.count) apiKey=\(FlexaLog.mask(self.apiKey))")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            FlexaLog.gemini.error("Invalid HTTP response from Gemini")
            throw GeminiError.apiError
        }
        FlexaLog.gemini.info("Response ⇦ status=\(httpResponse.statusCode) bytes=\(data.count)")
        guard httpResponse.statusCode == 200 else {
            FlexaLog.gemini.error("Gemini API error — status=\(httpResponse.statusCode)")
            throw GeminiError.apiError
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            FlexaLog.gemini.error("Gemini invalid response — missing text field")
            throw GeminiError.invalidResponse
        }
        
        return text
    }
    
    private func generateAnalysis(prompt: String, session: ExerciseSessionData) async throws -> ExerciseAnalysis {
        let response = try await callGeminiAPI(prompt: prompt)
        
        // Enhanced JSON parsing with fallback handling
        do {
            // Try to extract JSON from response (may be wrapped in markdown)
            let cleanedResponse = extractJSONFromResponse(response)
            
            guard let data = cleanedResponse.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                FlexaLog.gemini.error("Failed to parse analysis JSON from Gemini response")
                return createFallbackAnalysis(session: session)
            }
            
            FlexaLog.gemini.debug("Analysis JSON keys=\(json.keys.sorted())")
            return ExerciseAnalysis(
                overallPerformance: parseIntSafely(json["overall_performance"]) ?? calculateFallbackScore(session: session),
                strengths: parseStringArraySafely(json["strengths"]) ?? generateFallbackStrengths(session: session),
                areasForImprovement: parseStringArraySafely(json["areas_for_improvement"]) ?? generateFallbackImprovements(session: session),
                specificFeedback: json["specific_feedback"] as? String ?? generateFallbackFeedback(session: session),
                nextSessionRecommendations: parseStringArraySafely(json["next_session_recommendations"]) ?? ["Continue regular practice"],
                estimatedRecoveryProgress: parseDoubleSafely(json["estimated_recovery_progress"]) ?? 0.7,
                timestamp: Date()
            )
        } catch {
            FlexaLog.gemini.error("JSON parsing error: \(error.localizedDescription)")
            return createFallbackAnalysis(session: session)
        }
    }
    
    private func parseRecommendations(from response: String) -> [Recommendation] {
        guard let data = response.data(using: .utf8),
              let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            FlexaLog.gemini.error("Failed to parse recommendations JSON; returning empty array")
            return []
        }
        
        return jsonArray.compactMap { dict in
            guard let type = dict["type"] as? String,
                  let title = dict["title"] as? String,
                  let description = dict["description"] as? String,
                  let priority = dict["priority"] as? String else { return nil }
            
            return Recommendation(
                type: RecommendationType(rawValue: type) ?? .exerciseModification,
                title: title,
                description: description,
                priority: RecommendationPriority(rawValue: priority) ?? .medium,
                estimatedBenefit: dict["estimated_benefit"] as? String ?? ""
            )
        }
    }
    
    private func parseFormAnalysis(from response: String) -> FormAnalysis {
        guard let data = response.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            FlexaLog.gemini.error("Failed to parse form analysis JSON; returning defaults")
            return FormAnalysis()
        }
        
        return FormAnalysis(
            formQuality: FormQuality(rawValue: json["form_quality"] as? String ?? "fair") ?? .fair,
            consistencyScore: json["consistency_score"] as? Int ?? 5,
            movementPatternFeedback: json["movement_pattern_feedback"] as? String ?? "",
            suggestedCorrections: json["suggested_corrections"] as? [String] ?? [],
            injuryRiskAssessment: RiskLevel(rawValue: json["injury_risk_assessment"] as? String ?? "medium") ?? .medium
        )
    }
}

enum GeminiError: Error {
    case invalidURL
    case apiError
    case invalidResponse
    case missingAPIKey
}

struct ExerciseAnalysis {
    let overallPerformance: Int
    let strengths: [String]
    let areasForImprovement: [String]
    let specificFeedback: String
    let nextSessionRecommendations: [String]
    let estimatedRecoveryProgress: Double
    let timestamp: Date
}

struct Recommendation: Identifiable {
    let id = UUID()
    let type: RecommendationType
    let title: String
    let description: String
    let priority: RecommendationPriority
    let estimatedBenefit: String
}

enum RecommendationType: String, CaseIterable {
    case exerciseModification = "exercise_modification"
    case goalAdjustment = "goal_adjustment"
    case newGame = "new_game"
    case restDay = "rest_day"
}

enum RecommendationPriority: String, CaseIterable {
    case high, medium, low
}

struct FormAnalysis {
    let formQuality: FormQuality
    let consistencyScore: Int
    let movementPatternFeedback: String
    let suggestedCorrections: [String]
    let injuryRiskAssessment: RiskLevel
    
    init(formQuality: FormQuality = .fair, consistencyScore: Int = 5, movementPatternFeedback: String = "", suggestedCorrections: [String] = [], injuryRiskAssessment: RiskLevel = .medium) {
        self.formQuality = formQuality
        self.consistencyScore = consistencyScore
        self.movementPatternFeedback = movementPatternFeedback
        self.suggestedCorrections = suggestedCorrections
        self.injuryRiskAssessment = injuryRiskAssessment
    }
}

enum FormQuality: String, CaseIterable {
    case excellent, good, fair, needsImprovement = "needs_improvement"
}

enum RiskLevel: String, CaseIterable {
    case low, medium, high
}

// MARK: - Enhanced JSON Parsing Extensions
extension GeminiService {
    private func extractJSONFromResponse(_ response: String) -> String {
        // Remove markdown code block syntax if present
        let patterns = [
            "```json\\s*([\\s\\S]*?)\\s*```",
            "```([\\s\\S]*?)```",
            "\\{[\\s\\S]*\\}"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: response, range: NSRange(response.startIndex..., in: response)) {
                let captureRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
                if let range = Range(captureRange, in: response) {
                    return String(response[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func parseIntSafely(_ value: Any?) -> Int? {
        if let intVal = value as? Int {
            return intVal
        } else if let stringVal = value as? String,
                  let intVal = Int(stringVal) {
            return intVal
        } else if let doubleVal = value as? Double {
            return Int(doubleVal)
        }
        return nil
    }
    
    private func parseDoubleSafely(_ value: Any?) -> Double? {
        if let doubleVal = value as? Double {
            return doubleVal
        } else if let stringVal = value as? String,
                  let doubleVal = Double(stringVal) {
            return doubleVal
        } else if let intVal = value as? Int {
            return Double(intVal)
        }
        return nil
    }
    
    private func parseStringArraySafely(_ value: Any?) -> [String]? {
        if let arrayVal = value as? [String] {
            return arrayVal
        } else if let anyArrayVal = value as? [Any] {
            return anyArrayVal.compactMap { $0 as? String }
        }
        return nil
    }
    
    private func createFallbackAnalysis(session: ExerciseSessionData) -> ExerciseAnalysis {
        return ExerciseAnalysis(
            overallPerformance: calculateFallbackScore(session: session),
            strengths: generateFallbackStrengths(session: session),
            areasForImprovement: generateFallbackImprovements(session: session),
            specificFeedback: generateFallbackFeedback(session: session),
            nextSessionRecommendations: ["Continue regular practice", "Focus on consistency"],
            estimatedRecoveryProgress: 0.7,
            timestamp: Date()
        )
    }
    
    private func calculateFallbackScore(session: ExerciseSessionData) -> Int {
        let baseScore = 60
        let repsBonus = min(session.reps * 2, 20)
        let romBonus = min(Int(session.maxROM / 3), 15)
        return min(baseScore + repsBonus + romBonus, 100)
    }
    
    private func generateFallbackStrengths(session: ExerciseSessionData) -> [String] {
        var strengths: [String] = []
        
        if session.reps >= 10 {
            strengths.append("Good repetition count")
        }
        if session.maxROM >= 30 {
            strengths.append("Achieving good range of motion")
        }
        if session.duration >= 60 {
            strengths.append("Sustained exercise duration")
        }
        
        return strengths.isEmpty ? ["Consistent participation"] : strengths
    }
    
    private func generateFallbackImprovements(session: ExerciseSessionData) -> [String] {
        var improvements: [String] = []
        
        if session.reps < 5 {
            improvements.append("Increase repetition count")
        }
        if session.maxROM < 20 {
            improvements.append("Work on expanding range of motion")
        }
        if session.duration < 30 {
            improvements.append("Extend exercise duration")
        }
        
        return improvements.isEmpty ? ["Continue building consistency"] : improvements
    }
    
    private func generateFallbackFeedback(session: ExerciseSessionData) -> String {
        let score = calculateFallbackScore(session: session)
        
        switch score {
        case 80...: return "Excellent performance! You're showing great progress."
        case 60...79: return "Good work! Keep building on this momentum."
        case 40...59: return "Nice effort! Focus on consistency for better results."
        default: return "Every session counts. Keep practicing and you'll see improvement."
        }
    }
}
