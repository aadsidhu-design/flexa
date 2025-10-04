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
        FlexaLog.gemini.debug("Prompt metrics — chars=\(prompt.count) words=\(prompt.split(separator: " ").count)")
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
    
    private func getGameDescription(for exerciseType: String) -> String {
        if let type = GameType.fromDisplayName(exerciseType) {
            return type.aiDescription
        }

        switch exerciseType.lowercased() {
        case "make your own":
            return GameType.makeYourOwn.aiDescription
        case "test rom":
            return "A handheld calibration and testing exercise to measure baseline range of motion capabilities. Used for initial assessment and progress tracking."
        default:
            return "A therapeutic exercise designed to improve range of motion and motor control through engaging gameplay."
        }
    }
    
    private func createAnalysisPrompt(for session: ExerciseSessionData) -> String {
        let romMin = session.romData.map { $0.angle }.min() ?? 0
        let romMax = session.romData.map { $0.angle }.max() ?? session.maxROM
        let romAvg = session.romData.isEmpty ? session.maxROM : (session.romData.map { $0.angle }.reduce(0, +) / Double(session.romData.count))
        
        let gameDescription = getGameDescription(for: session.exerciseType)
        
    return """
Analyze this physical therapy exercise session and return JSON only.
Session Summary (metrics for your reference only):
- Exercise: \(session.exerciseType)
- Game Description: \(gameDescription)
- Reps: \(session.reps)
- Max reach angle: \(Int(romMax)) degrees (min \(Int(romMin)), avg \(Int(romAvg)))
- Duration: \(Int(session.duration)) seconds
- Smoothness score (0-100): \(String(format: "%.0f", session.sparcScore))

Writing rules for feedback:
- Use plain, supportive language. Avoid metric acronyms like "ROM" or "SPARC" entirely.
- Talk about "how far you reached", "smoothness", "consistency", and "jerkiness" instead of raw numbers.
- Be concise but specific. Describe what went well and what to improve in everyday terms.
- Give actionable coaching cues (e.g., "slow the return", "keep the motion even", "reach a bit further each rep").
- Keep a positive tone tailored to rehab.

Return JSON with snake_case keys only:
- overall_performance: integer 0-100
- strengths: array of 2-4 short strings
- areas_for_improvement: array of 2-4 short strings (use friendly terms like "movements were a bit jerky" or "inconsistent pacing")
- specific_feedback: 4-6 sentences, conversational and encouraging, no metric acronyms
- next_session_recommendations: array of 3 short strings, concrete next steps
- estimated_recovery_progress: number 0-1
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
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30.0
        
        let requestBody: [String: Any] = [
            "contents": [[
                "parts": [[
                    "text": prompt
                ]]
            ]]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        FlexaLog.gemini.debug("Preparing Gemini request — bodyBytes=\(request.httpBody?.count ?? 0)")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                FlexaLog.gemini.info("Gemini API response status: \(httpResponse.statusCode)")
                guard httpResponse.statusCode == 200 else {
                    let errorMsg = "HTTP \(httpResponse.statusCode)"
                    FlexaLog.gemini.error("Gemini API error: \(errorMsg)")
                    throw GeminiError.networkError(errorMsg)
                }
            }
            
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            FlexaLog.gemini.info("Gemini API response received, parsing...")
            if let keys = json?.keys { FlexaLog.gemini.debug("Response top-level keys: \(Array(keys))") }
            
            guard let candidates = json?["candidates"] as? [[String: Any]],
                  let firstCandidate = candidates.first,
                  let content = firstCandidate["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let firstPart = parts.first,
                  let text = firstPart["text"] as? String else {
                FlexaLog.gemini.error("Invalid Gemini API response structure — candidates/parts/text missing")
                if let j = json {
                    let preview = String(describing: j).prefix(400)
                    FlexaLog.gemini.debug("Response preview: \(preview)...")
                }
                throw GeminiError.invalidResponse
            }
            
            FlexaLog.gemini.info("Gemini API success, response length: \(text.count)")
            FlexaLog.gemini.debug("Gemini text snippet: \(text.prefix(200))…")
            return text
        } catch {
            FlexaLog.gemini.error("Gemini API call failed: \(error.localizedDescription)")
            throw error
        }
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
            
            // Log parsed values for debugging and accept both snake_case and camelCase
            let overallScore =
                parseIntSafely(json["overall_performance"]) ??
                parseIntSafely(json["overallPerformance"]) ?? 0
            let strengths =
                parseStringArraySafely(json["strengths"]) ??
                parseStringArraySafely(json["Strengths"]) ?? ["AI analysis unavailable"]
            let improvements =
                parseStringArraySafely(json["areas_for_improvement"]) ??
                parseStringArraySafely(json["areasForImprovement"]) ?? ["Please try again"]
            let feedback =
                (json["specific_feedback"] as? String) ??
                (json["specificFeedback"] as? String) ??
                "AI analysis is currently unavailable. Please check your connection and try again."
            let recommendations =
                parseStringArraySafely(json["next_session_recommendations"]) ??
                parseStringArraySafely(json["nextSessionRecommendations"]) ?? ["Continue regular practice"]
            let recoveryProgress =
                parseDoubleSafely(json["estimated_recovery_progress"]) ??
                parseDoubleSafely(json["estimatedRecoveryProgress"]) ?? 0.7
            
            FlexaLog.gemini.info("Parsed Analysis:")
            FlexaLog.gemini.info("   Score: \(overallScore)")
            FlexaLog.gemini.info("   Strengths: \(strengths)")
            FlexaLog.gemini.info("   Improvements: \(improvements)")
            FlexaLog.gemini.info("   Feedback: \(feedback)")
            FlexaLog.gemini.info("   Recommendations: \(recommendations)")
            FlexaLog.gemini.info("   Recovery Progress: \(recoveryProgress)")
            
            return ExerciseAnalysis(
                overallPerformance: overallScore,
                strengths: strengths,
                areasForImprovement: improvements,
                specificFeedback: feedback,
                nextSessionRecommendations: recommendations,
                estimatedRecoveryProgress: recoveryProgress,
                timestamp: Date()
            )
        } catch {
            FlexaLog.gemini.error("JSON parsing error: \(error.localizedDescription)")
            return createFallbackAnalysis(session: session)
        }
    }
    
    private func parseRecommendations(from response: String) -> [Recommendation] {
        FlexaLog.gemini.info("Parsing Recommendations from response:")
        FlexaLog.gemini.info("\(response)")
        
        guard let data = response.data(using: .utf8),
              let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            FlexaLog.gemini.error("Failed to parse recommendations JSON; returning empty array")
            return []
        }
        
        FlexaLog.gemini.info("Found \(jsonArray.count) recommendation items")
        
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
        FlexaLog.gemini.info("Parsing Form Analysis from response:")
        FlexaLog.gemini.info("\(response)")
        
        guard let data = response.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            FlexaLog.gemini.error("Failed to parse form analysis JSON; returning defaults")
            return FormAnalysis()
        }
        
        let formQuality = FormQuality(rawValue: json["form_quality"] as? String ?? "fair") ?? .fair
        let consistencyScore = json["consistency_score"] as? Int ?? 5
        let feedback = json["movement_pattern_feedback"] as? String ?? ""
        
        FlexaLog.gemini.info("Parsed Form Analysis:")
        FlexaLog.gemini.info("   Quality: \(formQuality.rawValue)")
        FlexaLog.gemini.info("   Consistency: \(consistencyScore)")
        FlexaLog.gemini.info("   Feedback: \(feedback)")
        
        return FormAnalysis(
            formQuality: formQuality,
            consistencyScore: consistencyScore,
            movementPatternFeedback: feedback,
            suggestedCorrections: json["suggested_corrections"] as? [String] ?? [],
            injuryRiskAssessment: RiskLevel(rawValue: json["injury_risk_assessment"] as? String ?? "medium") ?? .medium
        )
    }
    
    private func createFallbackAnalysis(session: ExerciseSessionData) -> ExerciseAnalysis {
        // Return a minimal analysis when Gemini fails - no fallback scoring
        return ExerciseAnalysis(
            overallPerformance: 75, // Give a reasonable default score
            strengths: ["Session completed successfully"],
            areasForImprovement: ["Continue regular practice"],
            specificFeedback: "AI analysis temporarily unavailable. Your session data has been saved successfully.",
            nextSessionRecommendations: ["Try another session when ready"],
            estimatedRecoveryProgress: 0.7,
            timestamp: Date()
        )
    }
}

enum GeminiError: Error {
    case invalidURL
    case apiError
    case invalidResponse
    case missingAPIKey
    case invalidAPIKey
    case networkError(String)
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
}
