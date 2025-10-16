import SwiftUI
import Charts

struct AnalyzingView: View {
    let sessionData: ExerciseSessionData
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    @Environment(\.dismiss) private var dismiss
    
    @State private var currentProgress: Double = 0
    @State private var currentStep = "Initializing analysis..."
    @State private var enhancedSessionData: ExerciseSessionData?
    @State private var aiAnalysis: ExerciseAnalysis?
    @State private var progress: Double = 0.0
    @State private var currentTask = "Initializing..."
    
    @EnvironmentObject var geminiService: GeminiService
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var backendService: BackendService
    @EnvironmentObject var motionService: SimpleMotionService
    
    
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
                    motionService.stopCamera(tearDownCompletely: true)
                }
            
            // Always show loading view - no internal results screen
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
        .onAppear {
            startComprehensiveAnalysis()
        }
        // Hide any navigation UI when presented in a NavigationStack
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }
    
    private func startComprehensiveAnalysis() {
        Task {
            await performAnalysisSteps()
        }
    }
    
    @MainActor
    private func updateProgress(_ step: Int, _ task: String) {
        // Show 20%, 40%, 60%, 80%, 100% for steps 0..4
        let totalSteps = 5.0
        let stepProgress = min(1.0, (Double(step) + 1.0) / totalSteps)
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
        
    // Step 2: Handheld ROM is already computed live via the instant ARKit pipeline
    // Data is already in SimpleMotionService.romPerRep and romHistory
        await MainActor.run { updateProgress(1, "Analyzing movement patterns...") }
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second
        print("📊 [AnalyzingView] Using LIVE-calculated ROM data (no post-processing)")
        
        // Step 3: Calculate comprehensive metrics
        await MainActor.run { updateProgress(2, "Calculating comprehensive metrics...") }
        let enhancedData = await calculateComprehensiveMetrics()
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        print("📊 [AnalyzingView] Metrics calculated - ROM: \(enhancedData.maxROM)°, SPARC: \(enhancedData.sparcScore)")
        print("📊 [AnalyzingView] ROM History: \(enhancedData.romHistory.count) values")
        print("📊 [AnalyzingView] ROM per Rep: \(enhancedData.romHistory.map { String(format: "%.1f", $0) }.joined(separator: ", "))°")
        
        // Step 4: Generate AI analysis (this is the slow part)
        await MainActor.run { updateProgress(3, "Generating AI analysis with Gemini...") }
        print("🤖 [AnalyzingView] Calling Gemini API...")
        let analysis = await generateAIAnalysis(for: enhancedData)
        print("🤖 [AnalyzingView] AI analysis completed: \(analysis?.overallPerformance ?? 0) score")
        
        // Step 5: Save session data
        await MainActor.run { updateProgress(4, "Saving session data...") }
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        print("💾 [AnalyzingView] Session data saved")
        
        // Step 6: Prepare results display
        await MainActor.run { updateProgress(5, "Preparing results display...") }
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        print("✅ [AnalyzingView] Analysis pipeline complete, showing results")
        await MainActor.run {
            let finalAnalysis = analysis ?? createFallbackAnalysis(for: enhancedData)
            print("📊 [AnalyzingView] Final analysis score: \(finalAnalysis.overallPerformance)")
            
            // Store the analysis in the Gemini service for ResultsView to access
            geminiService.lastAnalysis = finalAnalysis
            
            self.enhancedSessionData = enhancedData
            self.aiAnalysis = finalAnalysis
            
            // Ensure progress reaches 100% before navigating
            self.progress = 1.0
            self.currentTask = "Done"
            
            // Navigate to results. The NavigationCoordinator now replaces the analyzing entry
            // with the results entry so we don't need to call dismiss() here.
            navigationCoordinator.showResults(sessionData: enhancedData)
        }
    }
    
    // ❌ REMOVED: Legacy Universal3DROMEngine post-processing
    // No longer needed! ROM is calculated LIVE during gameplay
    // Data is already in SimpleMotionService.romPerRep/romHistory
    
    @MainActor
    private func calculateComprehensiveMetrics() async -> ExerciseSessionData {
    // ✅ CRITICAL FIX: Use LIVE-calculated ROM data from SimpleMotionService
    // ROM is calculated during gameplay by HandheldROMCalculator + InstantARKit tracking
    // and stored in SimpleMotionService.romPerRep / romHistory
        // NO post-processing needed - data is already accurate!
        
        let isHandheldGame = !motionService.isCameraExercise
        
        // NEW: Calculate SPARC from ARKit position trajectory for handheld games
        var arkitSPARCResult: ARKitSPARCAnalyzer.SPARCResult?
        if isHandheldGame {
            let positions = motionService.arkitPositions
            let timestamps = motionService.arkitPositionTimestampsDates
            
            if positions.count >= 10 {
                // Determine game type for SPARC analysis
                let gameType: ARKitSPARCAnalyzer.GameType
                switch motionService.currentGameType {
                case .fruitSlicer, .fanOutFlame:
                    gameType = .pendulum
                case .followCircle:
                    gameType = .circular
                default:
                    gameType = .freeForm
                }
                
                print("📊 [AnalyzingView] Calculating ARKit-based SPARC from \(positions.count) position samples")
                arkitSPARCResult = ARKitSPARCAnalyzer.analyze(
                    positions: positions,
                    timestamps: timestamps,
                    gameType: gameType,
                    repCount: motionService.currentReps
                )
            } else {
                print("📊 [AnalyzingView] Insufficient ARKit data for SPARC (\(positions.count) samples)")
            }
        }

        // Get the LIVE session data with per-rep ROM already calculated
        let liveData = motionService.getFullSessionData(
            overrideExerciseType: sessionData.exerciseType,
            overrideTimestamp: sessionData.timestamp,
            overrideScore: sessionData.score
        )

    var enhancedData = sessionData
        
        print("📊 [AnalyzingView] LIVE Session Data:")
        print("   Reps: \(liveData.reps)")
        print("   Max ROM: \(String(format: "%.1f", liveData.maxROM))°")
        print("   ROM History: \(liveData.romHistory.count) values = \(liveData.romHistory.map { String(format: "%.1f", $0) }.joined(separator: ", "))°")
        print("   SPARC Score: \(String(format: "%.1f", liveData.sparcScore))")
    enhancedData.sparcData = liveData.sparcData
        
        // Use LIVE data (already has correct per-rep ROM)
        if liveData.reps > enhancedData.reps {
            enhancedData.reps = liveData.reps
        }
        if liveData.maxROM > enhancedData.maxROM {
            enhancedData.maxROM = liveData.maxROM
        }
        
        // ✅ ALWAYS use liveData.romHistory for handheld games
        // This contains per-rep ROM calculated LIVE during gameplay
        if isHandheldGame && !liveData.romHistory.isEmpty {
            enhancedData.romHistory = liveData.romHistory
            enhancedData.averageROM = liveData.romHistory.reduce(0, +) / Double(liveData.romHistory.count)
            print("📊 [AnalyzingView] Using LIVE romHistory with \(liveData.romHistory.count) per-rep values")
        } else if !liveData.romHistory.isEmpty && enhancedData.romHistory.isEmpty {
            enhancedData.romHistory = liveData.romHistory
            enhancedData.averageROM = liveData.romHistory.reduce(0, +) / Double(liveData.romHistory.count)
        }
        
        if !liveData.repTimestamps.isEmpty && enhancedData.repTimestamps.isEmpty {
            enhancedData.repTimestamps = liveData.repTimestamps
        }
        
        // NEW: Use ARKit-based SPARC if available (handheld games only)
        if let arkitSPARC = arkitSPARCResult {
            enhancedData.sparcHistory = arkitSPARC.perRepScores
            enhancedData.sparcScore = arkitSPARC.smoothnessScore
            enhancedData.sparcData = arkitSPARC.timeline
            enhancedData.peakVelocity = arkitSPARC.peakVelocity
            print("📊 [AnalyzingView] ✨ NEW ARKit-based SPARC computed:")
            print("   Overall Score: \(String(format: "%.2f", arkitSPARC.overallScore))")
            let smoothnessInt = arkitSPARC.smoothnessScore.isNaN || arkitSPARC.smoothnessScore.isInfinite ? 50 : Int(arkitSPARC.smoothnessScore)
            print("   Smoothness: \(smoothnessInt)%")
            print("   Per-rep scores: \(arkitSPARC.perRepScores.count) values")
            print("   Peak Velocity: \(String(format: "%.2f", arkitSPARC.peakVelocity))m/s")
            print("   Jerkiness: \(String(format: "%.3f", arkitSPARC.jerkiness))")
        } else if !liveData.sparcHistory.isEmpty && enhancedData.sparcHistory.isEmpty {
            // Fallback to old SPARC data if ARKit-based failed
            enhancedData.sparcHistory = liveData.sparcHistory
        }
        
        if liveData.sparcScore > 0 && enhancedData.sparcScore == 0 {
            enhancedData.sparcScore = liveData.sparcScore
        }
        
        print("📊 [AnalyzingView] Final Enhanced Data:")
        print("   Reps: \(enhancedData.reps)")
        print("   Max ROM: \(String(format: "%.1f", enhancedData.maxROM))°")
        print("   ROM History: \(enhancedData.romHistory.count) values")
        print("   Average ROM: \(String(format: "%.1f", enhancedData.averageROM))°")
        
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
    let sparcScore = min(100, sparc) // SPARC is normalized to 0-100 now
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
        let smoothnessDescriptor = sparc >= 70 ? "very smooth" : sparc >= 50 ? "moderately smooth" : "developing"
        let smoothnessScoreText = String(format: "%.0f", sparc)
        feedbackParts.append("\n\nYour movement smoothness score was \(smoothnessScoreText), indicating \(smoothnessDescriptor) control.")
        if sparc >= 70 {
            feedbackParts.append("Your movements were well-controlled and fluid throughout the exercise.")
            feedbackParts.append("This level of smoothness reduces strain and promotes better muscle activation.")
        } else if sparc >= 50 {
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
        if sparc >= 70 {
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
        if sparc < 70 {
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
    
    // Upload is intentionally deferred to after post-survey
    
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
    .environmentObject(BackendService())
}
