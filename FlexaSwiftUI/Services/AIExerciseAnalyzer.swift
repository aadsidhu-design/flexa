import Foundation

/// Service that uses Gemini AI to analyze user exercise descriptions
/// and generate structured exercise configurations for rep detection
@MainActor class AIExerciseAnalyzer: ObservableObject {
    static let shared = AIExerciseAnalyzer()
    
    @Published var isAnalyzing: Bool = false
    @Published var analysisError: String?
    
    private var apiKey: String {
        return SecureConfig.shared.geminiAPIKey
    }
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent"
    
    private init() {}
    
    /// Analyze user's exercise description and return structured configuration
    func analyzeExercise(description: String) async throws -> AIExerciseAnalysis {
        FlexaLog.gemini.info("🤖 [AI] Analyzing exercise description: '\(description, privacy: .public)'")
        
        isAnalyzing = true
        analysisError = nil
        
        defer {
            isAnalyzing = false
        }
        
        let prompt = buildAnalysisPrompt(description: description)
        
        do {
            let response = try await callGeminiAPI(prompt: prompt)
            FlexaLog.gemini.info("🤖 [AI] Received response from Gemini")
            
            // Parse JSON response
            let analysis = try parseGeminiResponse(response)
            FlexaLog.gemini.info("✅ [AI] Successfully parsed exercise: '\(analysis.exerciseName)' (confidence: \(String(format: "%.0f", analysis.confidence * 100))%)")
            
            return analysis
        } catch {
            FlexaLog.gemini.error("❌ [AI] Analysis failed: \(error.localizedDescription)")
            analysisError = error.localizedDescription
            throw error
        }
    }
    
    // MARK: - API Call
    
    private func callGeminiAPI(prompt: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw NSError(domain: "AIExerciseAnalyzer", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Gemini API key not configured"])
        }
        
        var urlComponents = URLComponents(string: baseURL)!
        urlComponents.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = urlComponents.url else {
            throw NSError(domain: "AIExerciseAnalyzer", code: -2,
                         userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "contents": [
                ["parts": [["text": prompt]]]
            ],
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 1024
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NSError(domain: "AIExerciseAnalyzer", code: -3,
                         userInfo: [NSLocalizedDescriptionKey: "API request failed"])
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw NSError(domain: "AIExerciseAnalyzer", code: -4,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to parse API response"])
        }
        
        return text
    }
    
    // MARK: - Prompt Engineering
    
    private func buildAnalysisPrompt(description: String) -> String {
        return """
        You are an expert physical therapist and biomechanics specialist with deep knowledge of shoulder rehabilitation exercises and motion tracking systems.
        
        The user has described an exercise they want to perform for shoulder/arm rehabilitation:
        "\(description)"
        
        Analyze this description using context-aware reasoning and provide a structured JSON response with the following fields:
        
        {
          "exerciseName": "Short descriptive name (3-5 words)",
          "trackingMode": "handheld" or "camera",
          "jointToTrack": "armpit" or "elbow" (only if trackingMode is "camera", otherwise null),
          "movementType": "pendulum", "circular", "vertical", "horizontal", "straightening", or "mixed",
          "directionality": "bidirectional", "unidirectional", or "cyclical",
          "minimumROMThreshold": number (degrees, typically 30-70),
          "minimumDistanceThreshold": number or null (cm, only for handheld mode, typically 20-50),
          "repCooldown": number (seconds between reps, typically 0.8-2.5),
          "confidence": number (0.0-1.0, your confidence in this analysis),
          "reasoning": "Detailed explanation of your parameter choices and exercise interpretation"
        }
        
        ## INTELLIGENT ANALYSIS GUIDELINES
        
        ### 1. Tracking Mode Detection (Context-Aware)
        **Use "handheld" when:**
        - User mentions: "phone", "device", "hold", "swing phone", "move device", "holding", "grip"
        - Implied device interaction: "circular motion", "pendulum swing", "rotate my arm" (without camera context)
        - Direct device manipulation exercises
        
        **Use "camera" when:**
        - User mentions: "camera", "on screen", "in front of", "see myself", "video", "mirror"
        - Body-focused movements: "raise arms", "overhead reach", "wall climbers", "arm elevation"
        - Bilateral exercises or full-body movements
        - No mention of holding/gripping device
        
        **Edge cases to handle intelligently:**
        - Ambiguous: "swing my arm" → Default to handheld (simpler setup)
        - Clear bilateral: "raise both arms" → Must be camera
        - Device-centric verbs: "tilt", "rotate phone", "shake" → Handheld
        
        ### 2. Joint Selection (Camera Mode - Critical for Accuracy)
        **Use "armpit" for:**
        - Shoulder elevation: "raise arm", "lift arm overhead", "arm raise", "shoulder press"
        - Abduction: "side raise", "lateral raise", "T-pose", "arms out to side"
        - Overhead movements: "reach overhead", "touch ceiling", "raise up high"
        - Full arm movements from shoulder
        
        **Use "elbow" for:**
        - Elbow flexion: "bend elbow", "bicep curl", "bring hand to shoulder"
        - Forearm movements: "hammer curl", "forearm rotation"
        - Isolated elbow joint exercises
        
        ### 3. Movement Type Classification (Precise Categorization)
        **"pendulum"**: Forward-backward swings, sagittal plane oscillation
        - Keywords: "pendulum", "swing forward/back", "front to back", "forward and back"
        
        **"circular"**: Rotational patterns, clock-face movements
        - Keywords: "circle", "rotate", "clock", "around", "spin", "rotation"
        
        **"vertical"**: Straight up-down movements, elevation in frontal plane
        - Keywords: "raise", "lift", "up and down", "overhead", "elevation", "vertical"
        
        **"horizontal"**: Side-to-side, abduction-adduction, lateral plane
        - Keywords: "side to side", "lateral", "abduction", "wings", "T-pose"
        
        **"straightening"**: Extension movements, straightening joints
        - Keywords: "straighten", "extend", "reach out", "stretch arm out"
        
        **"mixed"**: Complex multi-planar movements
        - Keywords: "combination", "multiple directions", "varied", "complex"
        
        ### 4. Directionality Logic (Smart Rep Counting)
        **"bidirectional"**: Full cycle = 1 rep (most common for rehabilitation)
        - Use for: Pendulum, vertical raises, horizontal abduction
        - Rationale: Concentric + eccentric phase = complete rep
        
        **"unidirectional"**: Only one direction counts
        - Use for: Reaching movements, "touch target" exercises
        - Rationale: Focus on single direction (e.g., only lifting phase)
        
        **"cyclical"**: Continuous cycles (specialized)
        - Use for: Circular rotations, continuous spinning
        - Rationale: No clear start/end, count complete rotations
        
        ### 5. Smart Threshold Selection (Context-Dependent)
        
        **minimumROMThreshold** (degrees - for camera mode):
        - Post-surgery/acute pain: 20-30° (very gentle)
        - Early rehabilitation: 35-45° (moderate, building strength)
        - Active rehabilitation: 50-65° (standard therapeutic range)
        - Performance/sports rehab: 70-90° (challenging, near-full ROM)
        
        **Contextual adjustments:**
        - If "gentle", "careful", "post-surgery" mentioned → Lower threshold (25-35°)
        - If "full range", "maximum", "challenging" mentioned → Higher threshold (60-80°)
        - If "small movements" mentioned → 25-35°
        - Default moderate rehabilitation: 40-50°
        
        **minimumDistanceThreshold** (cm - for handheld mode):
        - Small amplitude exercises: 20-30 cm (controlled, precise)
        - Standard therapeutic range: 35-45 cm (moderate movement)
        - Large amplitude exercises: 50-65 cm (full engagement)
        
        ### 6. Rep Cooldown Timing (Movement-Speed Aware)
        - Fast, dynamic exercises: 0.8-1.2s (e.g., "quick reps", "pumps")
        - Standard controlled movements: 1.5-2.0s (most rehabilitation exercises)
        - Slow, deliberate movements: 2.2-2.8s (e.g., "slow and controlled", "hold at top")
        - Very slow/isometric emphasis: 3.0-3.5s
        
        **Consider user language:**
        - "Fast", "quick", "rapid" → 0.8-1.2s
        - "Slow", "controlled", "deliberate" → 2.2-2.8s
        - No speed indicator → Default 1.5-2.0s
        
        ### 7. Confidence Scoring (Honest Self-Assessment)
        - 0.9-1.0: Crystal clear description, all parameters obvious
        - 0.7-0.89: Clear intent, minor ambiguity on 1-2 parameters
        - 0.5-0.69: Somewhat ambiguous, made reasonable assumptions
        - 0.3-0.49: Vague description, significant guesswork required
        - Below 0.3: Too ambiguous to analyze reliably (will be rejected)
        
        ### 8. Reasoning Quality (Detailed Justification)
        Provide comprehensive reasoning that explains:
        - Why you chose handheld vs camera (what keywords/context indicated this)
        - Why specific joint for camera mode (biomechanical rationale)
        - Why movement type classification (what pattern you detected)
        - Why threshold values (severity/intensity implied by description)
        - Any assumptions made and why
        - Alternative interpretations considered but rejected
        
        CRITICAL: Respond ONLY with valid JSON. Do not include any explanatory text before or after the JSON object.
        """
    }
    
    // MARK: - Response Parsing
    
    private func parseGeminiResponse(_ response: String) throws -> AIExerciseAnalysis {
        // Clean up response - remove markdown code blocks if present
        var jsonString = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove ```json and ``` markers
        if jsonString.hasPrefix("```json") {
            jsonString = String(jsonString.dropFirst(7))
        } else if jsonString.hasPrefix("```") {
            jsonString = String(jsonString.dropFirst(3))
        }
        
        if jsonString.hasSuffix("```") {
            jsonString = String(jsonString.dropLast(3))
        }
        
        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        if !jsonString.hasPrefix("{") {
            if let extracted = extractFirstJSONObject(from: jsonString) {
                jsonString = extracted
            }
        }

        guard jsonString.hasPrefix("{"), jsonString.hasSuffix("}") else {
            FlexaLog.gemini.error("❌ [AI] Unable to isolate JSON object from response: \(jsonString.prefix(200))…")
            throw NSError(domain: "AIExerciseAnalyzer", code: -6,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to parse AI response. Please try again."])
        }

        guard let data = jsonString.data(using: .utf8) else {
            throw NSError(domain: "AIExerciseAnalyzer", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to convert response to data"])
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        do {
            let analysis = try decoder.decode(AIExerciseAnalysis.self, from: data)
            
            // Validate analysis
            guard analysis.confidence > 0.3 else {
                throw NSError(domain: "AIExerciseAnalyzer", code: -2,
                             userInfo: [NSLocalizedDescriptionKey: "AI confidence too low (\(Int(analysis.confidence * 100))%). Please provide more detail."])
            }
            
            // Validate handheld exercises have distance threshold
            if analysis.trackingMode == .handheld && analysis.minimumDistanceThreshold == nil {
                throw NSError(domain: "AIExerciseAnalyzer", code: -3,
                             userInfo: [NSLocalizedDescriptionKey: "Handheld exercises require distance threshold"])
            }
            
            // Validate camera exercises have joint
            if analysis.trackingMode == .camera && analysis.jointToTrack == nil {
                throw NSError(domain: "AIExerciseAnalyzer", code: -4,
                             userInfo: [NSLocalizedDescriptionKey: "Camera exercises require joint specification"])
            }
            
            return analysis
        } catch let decodingError as DecodingError {
            FlexaLog.gemini.error("❌ [AI] JSON decode error: \(decodingError)")
            throw NSError(domain: "AIExerciseAnalyzer", code: -5,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to parse AI response. Please try again."])
        }
    }

    private func extractFirstJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var braceDepth = 0
        var currentIndex = start
        while currentIndex < text.endIndex {
            let character = text[currentIndex]
            if character == "{" {
                braceDepth += 1
            } else if character == "}" {
                braceDepth -= 1
                if braceDepth == 0 {
                    let jsonSubstring = text[start...currentIndex]
                    return String(jsonSubstring)
                }
            }
            currentIndex = text.index(after: currentIndex)
        }
        return nil
    }
}
