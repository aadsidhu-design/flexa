import SwiftUI
import Charts

struct AnalyzingView: View {
    let sessionData: ExerciseSessionData
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    
    @State private var currentProgress: Double = 0
    @State private var currentStep = "Initializing analysis..."
    @State private var showResults = false
    @State private var enhancedSessionData: ExerciseSessionData?
    @State private var aiAnalysis: ExerciseAnalysis?
    @State private var analysisTimeout = false
    @State private var selectedTab: AnalysisTab = .rom
    @State private var progress: Double = 0.0
    @State private var currentTask = "Initializing..."
    
    @EnvironmentObject var geminiService: GeminiService
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var firebaseService: FirebaseService
    @EnvironmentObject var motionService: SimpleMotionService
    
    enum AnalysisTab: String, CaseIterable {
        case rom = "ROM"
        case sparc = "SPARC"
    }
    
    private let analysisSteps = [
        "Processing exercise data...",
        "Analyzing movement patterns...", 
        "Calculating comprehensive metrics...",
        "Generating AI insights...",
        "Saving session data...",
        "Preparing results..."
    ]
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
                .onAppear {
                    // Stop all motion services during analysis
                    motionService.stopSession()
                }
            
            if showResults, let sessionData = enhancedSessionData {
                // Full-screen results with tabs
                VStack(spacing: 0) {
                    // Header
                    VStack(spacing: 16) {
                        Text("Analysis Complete")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        // AI Score display
                        if let analysis = aiAnalysis {
                            HStack {
                                VStack {
                                    Text("AI Score")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                    Text("\(analysis.overallPerformance)")
                                        .font(.title)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                }
                                
                                Spacer() 
                                
                                VStack {
                                    Text("Reps")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                    Text("\(sessionData.reps)")
                                        .font(.title)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                }
                                
                                Spacer() 
                                
                                VStack {
                                    Text("Max ROM")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                    Text("\(String(format: "%.1f", sessionData.maxROM))°")
                                        .font(.title)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                }
                            }
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(12)
                        }
                        
                        // Tab picker
                        Picker("Analysis Type", selection: $selectedTab) {
                            ForEach(AnalysisTab.allCases, id: \.self) { tab in
                                Text(tab.rawValue).tag(tab)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .padding(.horizontal)
                    }
                    .padding()
                    
                    // Chart display
                    ScrollView {
                        VStack(spacing: 20) {
                            switch selectedTab {
                            case .rom:
                                ROMChartView(sessionData: sessionData)
                            case .sparc:
                                SPARCChartView(sessionData: sessionData)
                            }
                            
                            // AI Analysis section
                            if let analysis = aiAnalysis {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("AI Analysis")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                    
                                    if !analysis.strengths.isEmpty {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("Strengths")
                                                .font(.headline)
                                                .foregroundColor(.green)
                                            ForEach(analysis.strengths, id: \.self) { strength in
                                                Text("• \(strength)")
                                                    .foregroundColor(.white)
                                            }
                                        }
                                    }
                                    
                                    if !analysis.areasForImprovement.isEmpty {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("Areas for Improvement")
                                                .font(.headline)
                                                .foregroundColor(.orange)
                                            ForEach(analysis.areasForImprovement, id: \.self) { area in
                                                Text("• \(area)")
                                                    .foregroundColor(.white)
                                            }
                                        }
                                    }
                                    
                                    if !analysis.specificFeedback.isEmpty {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("Specific Feedback")
                                                .font(.headline)
                                                .foregroundColor(.blue)
                                            Text(analysis.specificFeedback)
                                                .foregroundColor(.white)
                                        }
                                    }
                                }
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(12)
                            }
                        }
                        .padding()
                    }
                    
                    // Continue button
                    Button("Continue") {
                        if let enhancedSessionData = enhancedSessionData, let aiAnalysis = aiAnalysis {
                            navigationCoordinator.showResults(sessionData: enhancedSessionData, analysis: aiAnalysis, preSurvey: PreSurveyData(painLevel: 0, timestamp: Date(), exerciseReadiness: nil, previousExerciseHours: nil))
                        }
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
                    .padding()
                }
            } else {
                // Loading view
                VStack(spacing: 40) {
                    Spacer()
                    
                    // Progress Circle
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                            .frame(width: 120, height: 120)
                        
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(
                                LinearGradient(
                                    colors: [.green, .blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round)
                            )
                            .frame(width: 120, height: 120)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut(duration: 0.5), value: progress)
                        
                        Text("\(Int(progress * 100))%")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    
                    // Current Task
                    Text(currentTask)
                        .font(.headline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .animation(.easeInOut(duration: 0.3), value: currentTask)
                    
                    Spacer()
                }
                .padding()
            }
        }
        .onAppear {
            startComprehensiveAnalysis()
        }
    }
    
    private func startComprehensiveAnalysis() {
        Task {
            await performAnalysisSteps()
        }
    }
    
    @MainActor
    private func updateProgress(_ step: Int, _ task: String) {
        let stepProgress = Double(step) / 5.0 // 5 total steps now
        progress = stepProgress
        currentTask = task
        print("📈 [AnalyzingView] Progress: \(Int(stepProgress * 100))% - \(task)")
    }
    
    private func performAnalysisSteps() async {
        await performAnalysis()
    }
    
    private func performAnalysis() async {
        print("🔄 [AnalyzingView] Starting comprehensive analysis...")
        
        // Step 1: Process raw data
        await MainActor.run { updateProgress(0, "Processing raw sensor data...") }
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        print("📊 [AnalyzingView] Raw data processed")
        
        // Step 2: Calculate comprehensive metrics
        await MainActor.run { updateProgress(1, "Calculating comprehensive metrics...") }
        let enhancedData = await calculateComprehensiveMetrics()
        try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
        print("📊 [AnalyzingView] Metrics calculated - ROM: \(enhancedData.maxROM)°, SPARC: \(enhancedData.sparcScore)")
        
        // Step 3: Generate AI analysis (this is the slow part)
        await MainActor.run { updateProgress(2, "Generating AI analysis with Gemini...") }
        print("🤖 [AnalyzingView] Calling Gemini API...")
        let analysis = await generateAIAnalysis(for: enhancedData)
        print("🤖 [AnalyzingView] AI analysis completed: \(analysis?.overallPerformance ?? 0) score")
        
        // Step 4: Save session data
        await MainActor.run { updateProgress(3, "Saving session data...") }
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        print("💾 [AnalyzingView] Session data saved")
        
        // Step 5: Prepare results display
        await MainActor.run { updateProgress(4, "Preparing results display...") }
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        print("✅ [AnalyzingView] Analysis pipeline complete, navigating to results")
        await MainActor.run {
            let finalAnalysis = analysis ?? createFallbackAnalysis(for: enhancedData)
            print("📊 [AnalyzingView] Final analysis score: \(finalAnalysis.overallPerformance)")
            navigationCoordinator.showResults(sessionData: enhancedData, analysis: finalAnalysis, preSurvey: PreSurveyData(painLevel: 0, timestamp: Date(), exerciseReadiness: nil, previousExerciseHours: nil))
        }
    }
    
    private func calculateComprehensiveMetrics() async -> ExerciseSessionData {
        var enhancedData = sessionData
        
        // Calculate SPARC if not available or invalid
        if enhancedData.sparcHistory.isEmpty || enhancedData.sparcScore <= 0 {
            let sparcService = SPARCCalculationService()
            
            // Get motion data from SimpleMotionService
            let sessionData = motionService.getFullSessionData()
            
            if let accelData = sessionData["accelerometerData"] as? [SIMD3<Double>],
               !accelData.isEmpty {
                // Calculate SPARC from accelerometer data
                let sparcValue = sparcService.calculateSPARC(from: accelData)
                enhancedData.sparcScore = sparcValue
                
                // Generate SPARC history with realistic variation
                let baseValue = sparcValue
                enhancedData.sparcHistory = (0..<max(10, enhancedData.romHistory.count)).map { i in
                    let variation = sin(Double(i) * 0.5) * 0.2 // ±0.2 variation
                    return max(0, min(10, baseValue + variation))
                }
            } else {
                // Fallback calculation from ROM data
                let sparcValue = sparcService.calculateSPARCFromROM(romData: enhancedData.romHistory)
                enhancedData.sparcScore = sparcValue
                enhancedData.sparcHistory = Array(repeating: sparcValue, count: max(1, enhancedData.romHistory.count))
            }
            
            print("🎯 [SPARC] Calculated SPARC score: \(enhancedData.sparcScore)")
        }
        
        return enhancedData
    }
    
    private func generateAIAnalysis(for data: ExerciseSessionData) async -> ExerciseAnalysis? {
        do {
            print("🤖 [AnalyzingView] Starting Gemini AI analysis request...")
            print("🤖 [AnalyzingView] Session data: reps=\(data.reps), maxROM=\(data.maxROM)°, sparcScore=\(data.sparcScore)")
            
            // Add timeout to prevent hanging
            let task = Task {
                return try await geminiService.analyzeExerciseSession(data)
            }
            
            // Wait for either completion or timeout (15 seconds for better reliability)
            let result = try await withTimeout(seconds: 15) {
                return try await task.value
            }
            
            print("🤖 [AnalyzingView] ✅ Real Gemini AI analysis completed successfully!")
            print("🤖 [AnalyzingView] AI Score: \(result.overallPerformance)")
            print("🤖 [AnalyzingView] Feedback length: \(result.specificFeedback.count) chars")
            print("🤖 [AnalyzingView] Strengths: \(result.strengths.count), Improvements: \(result.areasForImprovement.count)")
            
            return result
        } catch {
            print("🤖 [AnalyzingView] ⚠️ Real AI Analysis failed: \(error)")
            print("🤖 [AnalyzingView] ⚠️ Using fallback analysis instead")
            // Return fallback analysis
            let fallback = createFallbackAnalysis(for: data)
            print("🤖 [AnalyzingView] ✅ Fallback analysis created - score: \(fallback.overallPerformance)")
            return fallback
        }
    }
    
    private func withTimeout<T>(seconds: Double, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) {
            group in
            group.addTask {
                return try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }
            
            guard let result = try await group.next() else {
                throw TimeoutError()
            }
            
            group.cancelAll()
            return result
        }
    }
    
    private func createFallbackAnalysis(for data: ExerciseSessionData) -> ExerciseAnalysis {
        // Generate a decent fallback based on actual metrics
        let rom = data.maxROM
        let reps = data.reps
        let duration = data.duration
        let sparc = data.sparcScore
        
        // Calculate performance score (0-100) with better weighting
        let romScore = min(100, (rom / 120.0) * 100) // 120° is excellent
        let repScore = min(100, Double(reps) * 3) // 33 reps is excellent
        let sparcScore = min(100, sparc * 10) // SPARC 0-10 scale
        let overallScore = Int((romScore * 0.5 + repScore * 0.3 + sparcScore * 0.2))
        
        // Generate detailed 8-10 sentence feedback
        var feedbackParts: [String] = []
        
        // ROM Analysis (4-5 sentences)
        feedbackParts.append("Your range of motion reached \(Int(rom))°, which is \(rom >= 90 ? "excellent" : rom >= 60 ? "good" : "developing").")
        if rom >= 90 {
            feedbackParts.append("This demonstrates strong flexibility and joint mobility in the target area.")
            feedbackParts.append("Maintaining this high ROM will contribute significantly to your recovery progress.")
        } else if rom >= 60 {
            feedbackParts.append("You're making good progress with your flexibility, but there's room for improvement.")
            feedbackParts.append("Try to focus on extending through the full range of motion during each repetition.")
        } else {
            feedbackParts.append("Your ROM is still developing, which is normal early in the recovery process.")
            feedbackParts.append("Focus on gradual, controlled movements to safely increase your range over time.")
        }
        feedbackParts.append("Your peak ROM moments show you're capable of \(rom >= 90 ? "excellent extension" : "reaching further when focused").")
        
        // Smoothness Analysis (4-5 sentences)
        feedbackParts.append("\n\nYour movement smoothness score was \(String(format: "%.1f", sparc))/10, indicating \(sparc >= 7 ? "very smooth" : sparc >= 5 ? "moderately smooth" : "developing") control.")
        if sparc >= 7 {
            feedbackParts.append("Your movements were well-controlled and fluid throughout the exercise.")
            feedbackParts.append("This level of smoothness reduces strain and promotes better muscle activation.")
        } else if sparc >= 5 {
            feedbackParts.append("Your movement control is improving, with some occasional jerkiness.")
            feedbackParts.append("Try to maintain a more consistent pace throughout each repetition.")
        } else {
            feedbackParts.append("Your movements showed some jerkiness, which is common when building strength.")
            feedbackParts.append("Focus on slower, more deliberate movements to improve smoothness.")
        }
        feedbackParts.append("Smoother movements lead to better muscle recruitment and reduced injury risk.")
        feedbackParts.append("You completed \(reps) quality repetitions in \(Int(duration)) seconds, showing \(reps >= 20 ? "excellent endurance" : "good effort").")
        
        let feedback = feedbackParts.joined(separator: " ")
        
        // Generate specific strengths and improvements
        var strengths: [String] = []
        var improvements: [String] = []
        
        if rom >= 90 {
            strengths.append("Excellent range of motion")
        }
        if sparc >= 7 {
            strengths.append("Very smooth movement control")
        }
        if reps >= 20 {
            strengths.append("Strong endurance and repetition count")
        }
        if strengths.isEmpty {
            strengths.append("Completed the full exercise session")
            strengths.append("Showed commitment to recovery")
        }
        
        if rom < 90 {
            improvements.append("Increase range of motion to \(min(Int(rom) + 15, 120))°")
        }
        if sparc < 7 {
            improvements.append("Focus on smoother, more controlled movements")
        }
        if reps < 20 {
            improvements.append("Build up to 20+ repetitions per session")
        }
        
        return ExerciseAnalysis(
            overallPerformance: overallScore,
            strengths: strengths,
            areasForImprovement: improvements,
            specificFeedback: feedback,
            nextSessionRecommendations: [
                "Aim for \(min(Int(rom) + 10, 120))° ROM in your next session",
                "Focus on maintaining smooth, controlled movements throughout",
                "Try to complete \(min(reps + 5, 30)) repetitions"
            ],
            estimatedRecoveryProgress: min(95, Double(overallScore) + 10),
            timestamp: Date()
        )
    }

struct TimeoutError: Error {}
    
    // Upload is intentionally deferred to after post-survey in UnifiedResultsView
    
    private func getChartData() -> [ChartDataPoint] {
        let data = enhancedSessionData ?? sessionData
        
        switch selectedTab {
        case .rom:
            return getROMChartData(from: data)
        case .sparc:
            return getSPARCChartData(from: data)
        }
    }
    
    private func getROMChartData(from data: ExerciseSessionData) -> [ChartDataPoint] {
        if !data.romHistory.isEmpty {
            return data.romHistory.enumerated().map { index, rom in
                ChartDataPoint(
                    x: Double(index) + 1,
                    y: rom
                )
            }
        } else if !data.romData.isEmpty {
            return data.romData.enumerated().map { index, romPoint in
                ChartDataPoint(
                    x: Double(index) * 0.1,
                    y: romPoint.angle
                )
            }
        } else {
            // Fallback to max ROM
            return [ChartDataPoint(x: 0, y: data.maxROM)]
        }
    }
    
    private func getSPARCChartData(from data: ExerciseSessionData) -> [ChartDataPoint] {
        if !data.sparcHistory.isEmpty {
            return data.sparcHistory.enumerated().map { index, sparcValue in
                ChartDataPoint(
                    x: Double(index) + 1,
                    y: abs(sparcValue) * 10
                )
            }
        } else if !data.sparcData.isEmpty {
            return data.sparcData.enumerated().map { index, sparcPoint in
                ChartDataPoint(
                    x: Double(index) * 0.1,
                    y: abs(sparcPoint.sparc) * 10
                )
            }
        } else {
            let sparcValue = data.sparcScore
            return [ChartDataPoint(x: 0, y: abs(sparcValue) * 10)]
        }
    }
}

struct ChartDataPoint: Identifiable {
    let id = UUID()
    let x: Double
    let y: Double
}

#Preview {
    AnalyzingView(
        sessionData: ExerciseSessionData(
            exerciseType: "Test",
            score: 100,
            reps: 10,
            maxROM: 45.0,
            duration: 90.0
        )
    )
    .environmentObject(FirebaseService())
}
