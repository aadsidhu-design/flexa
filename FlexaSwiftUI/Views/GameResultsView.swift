import SwiftUI
import Vision

struct GameResultsView: View {
    let gameType: GameType
    let score: Int
    let reps: Int
    let maxROM: Double
    let onDismiss: () -> Void
    
    @EnvironmentObject var firebaseService: FirebaseService
    @EnvironmentObject var goalsService: GoalsAndStreaksService
    @EnvironmentObject var geminiService: GeminiService
    @StateObject private var movementAnalyzer = MovementPatternAnalyzer()
    
    @State private var showingShareSheet = false
    @State private var analysis: ExerciseAnalysis?
    @State private var isAnalyzing = true
    @State private var showFeedbackThanks = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Header with celebration
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        gradient: Gradient(colors: [gameType.color.opacity(0.3), gameType.color.opacity(0.1)]),
                                        center: .center,
                                        startRadius: 20,
                                        endRadius: 80
                                    )
                                )
                                .frame(width: 120, height: 120)
                            
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.green)
                        }
                        
                        VStack(spacing: 8) {
                            Text("Workout Complete!")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text(gameType.displayName)
                                .font(.title2)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.top, 40)
                    
                    // Key Metrics
                    HStack(spacing: 20) {
                        MetricCard(title: "Reps", value: "\(reps)", color: .green)
                        MetricCard(title: "ROM", value: "\(Int(maxROM))°", color: .blue)
                        MetricCard(title: "Score", value: "\(score)", color: .yellow)
                    }
                    .padding(.horizontal)
                    
                    // Movement Pattern Analysis (Built-in)
                    MovementAnalysisCard(analyzer: movementAnalyzer)
                    
                    // AI Analysis Section (Optional)
                    if isAnalyzing {
                        VStack(spacing: 12) {
                            SwiftUI.ProgressView()
                                .tint(.purple)
                            Text("Analyzing your performance...")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        .frame(height: 100)
                    } else if let analysis = analysis {
                        AIResultsCard(analysis: analysis)
                    }
                    
                    // Progress Update
                    ProgressUpdateCard()
                    
                    // Feedback Thanks Message
                    if showFeedbackThanks {
                        VStack(spacing: 8) {
                            Image(systemName: "heart.fill")
                                .font(.title2)
                                .foregroundColor(.green)
                            Text("Thanks for your feedback!")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            Text("Your input helps us improve your experience.")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.green.opacity(0.1))
                        )
                        .padding(.horizontal)
                    }
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        Button("Continue Training") {
                            onDismiss()
                        }
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.green)
                        .cornerRadius(12)
                        
                        HStack(spacing: 12) {
                            Button("Share Results") {
                                showingShareSheet = true
                            }
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(8)
                            
                            Button("View Trends") {
                                // Navigate to progress view
                                onDismiss()
                            }
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer(minLength: 50)
                }
            }
        }
        .onAppear {
            saveSessionAndAnalyze()
            // Simulate movement analysis with sample data
            simulateMovementAnalysis()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PostSurveySubmitted"))) { _ in
            showFeedbackThanks = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                showFeedbackThanks = false
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(activityItems: [shareText])
        }
    }
    
    private func saveSessionAndAnalyze() {
        let sessionData = ExerciseSessionData(
            gameType: gameType.rawValue,
            score: score,
            reps: reps,
            maxROM: maxROM,
            duration: 300 // Default duration, should be passed from game
        )
        
        // Record session in goals service
        goalsService.recordExerciseSession(sessionData)
        
        // Only use AI analysis if user wants it (for now, skip to save API calls)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.isAnalyzing = false
        }
    }
    
    private func simulateMovementAnalysis() {
        // Simulate movement pattern analysis based on performance
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Create mock pose observation for analysis
            if let mockObservation = createMockPoseObservation() {
                movementAnalyzer.analyzePose(mockObservation, exerciseType: gameType.rawValue)
            }
        }
    }
    
    private func createMockPoseObservation() -> VNHumanBodyPoseObservation? {
        // This would normally come from actual pose detection during exercise
        // For now, create analysis based on performance metrics
        return nil // Simplified for now
    }
    
    private var shareText: String {
        "Just completed \(gameType.displayName) in Flexa! 🎯 Score: \(score) | Reps: \(reps) | Max ROM: \(Int(maxROM))° #FlexaRehab #PhysioTherapy"
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.1))
        )
    }
}

struct AIResultsCard: View {
    let analysis: ExerciseAnalysis
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.title2)
                    .foregroundColor(.purple)
                
                Text("AI Analysis")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("\(analysis.overallPerformance)/10")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
            }
            
            Text(analysis.specificFeedback)
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.leading)
            
            if !analysis.nextSessionRecommendations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Next Session")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    ForEach(analysis.nextSessionRecommendations.prefix(2), id: \.self) { recommendation in
                        HStack {
                            Image(systemName: "lightbulb.fill")
                                .foregroundColor(.yellow)
                                .font(.caption)
                            Text(recommendation)
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.1))
        )
        .padding(.horizontal)
    }
}

struct ProgressUpdateCard: View {
    @EnvironmentObject var goalsService: GoalsAndStreaksService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Progress Update")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Streak")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text("\(goalsService.streakData.currentStreak) days")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Today's Goal")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text("\(goalsService.todayProgress.repsCompleted)/\(goalsService.currentGoals.dailyReps)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }
            }
            
            Text(goalsService.getStreakMotivation())
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.1))
        )
        .padding(.horizontal)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    GameResultsView(
        gameType: .fruitSlicer,
        score: 1250,
        reps: 25,
        maxROM: 87.5,
        onDismiss: {}
    )
}
