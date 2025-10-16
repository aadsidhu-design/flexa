import SwiftUI
import Charts

struct ResultsView: View {
    let sessionData: ExerciseSessionData
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    @EnvironmentObject var backendService: BackendService
    @EnvironmentObject var geminiService: GeminiService
    @EnvironmentObject var motionService: SimpleMotionService
    @State private var showingPostSurvey = false
    @State private var selectedTab = 0
    @State private var postSurveyData = PostSurveyData(
        painLevel: 0,
        funRating: 0,
        difficultyRating: 0,
        enjoymentRating: 0,
        perceivedExertion: nil,
        willingnessToRepeat: nil,
        timestamp: Date()
    )
    @State private var postSurveySkipped = false
    
    @State private var aiScoreLocal: Int? = nil
    @State private var aiFeedbackLocal: String = ""
    @State private var isAILoading: Bool = true
    
    var body: some View {
        VStack(spacing: 0) {
            // AI Score at top
            VStack(spacing: 20) {
                VStack(spacing: 16) {
                    Text("\(displayedAIScore)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("AI Score")
                        .font(.headline)
                        .foregroundColor(.gray)
                }
                
                // Performance Metrics
                HStack(spacing: 16) {
                    MetricPill(label: "Reps", value: String(sessionData.reps), icon: "repeat")
                    MetricPill(label: "Avg ROM", value: String(format: "%.0f°", sessionData.averageROM), icon: "arrow.up.and.down")
                    MetricPill(label: "Smoothness", value: String(format: "%.0f", sessionData.sparcScore), icon: "waveform.path")
                }
                .padding(.horizontal, 20)
            }
            .padding(.top, 40)
            .padding(.bottom, 20)
            
            // Scrollable content: AI Feedback + Tabs + Graphs
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // AI Feedback (expandable)
                    Text(displayedAIFeedback)
                        .font(.body)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)

                    // Two tabs: Range of Motion and Smoothness
                    HStack(spacing: 0) {
                        TabButton(title: "Range of Motion", isSelected: selectedTab == 0) {
                            selectedTab = 0
                        }
                        TabButton(title: "Smoothness", isSelected: selectedTab == 1) {
                            selectedTab = 1
                        }
                    }
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                    .frame(height: 40)
                    .padding(.horizontal, 20)

                    // One graph
                    VStack {
                        if selectedTab == 0 {
                            // Range of Motion Graph
                            if !sessionData.romHistory.isEmpty {
                                // Clamp to the actual rep count to avoid over-long X-axis
                                let repCount = max(1, sessionData.reps)
                                let romSeries = Array(sessionData.romHistory.prefix(repCount))
                                let maxY = max(sessionData.maxROM, romSeries.max() ?? 0)
                                let xCount = romSeries.count
                                Chart {
                                    ForEach(Array(romSeries.enumerated()), id: \.offset) { index, rom in
                                        LineMark(
                                            x: .value("Rep", index + 1),
                                            y: .value("Angle", rom)
                                        )
                                        .foregroundStyle(.blue)
                                        .lineStyle(StrokeStyle(lineWidth: 3))
                                    }
                                }
                                .frame(height: 300)
                                .chartYScale(domain: 0...(maxY * 1.2))
                                .chartXScale(domain: 1...xCount)
                                .chartPlotStyle { plot in
                                    plot.background(Color.black)
                                }
                                .chartXAxis {
                                    AxisMarks(position: .bottom, values: .automatic(desiredCount: min(8, max(2, xCount / 12)))) { _ in
                                        AxisGridLine().foregroundStyle(Color.gray.opacity(0.2))
                                        AxisTick().foregroundStyle(Color.gray.opacity(0.6))
                                        AxisValueLabel().foregroundStyle(Color.white)
                                    }
                                }
                                .chartYAxis { AxisMarks(position: .leading) { value in
                                    AxisGridLine().foregroundStyle(Color.gray.opacity(0.2))
                                    AxisTick().foregroundStyle(Color.gray.opacity(0.6))
                                    AxisValueLabel {
                                        if let v = value.as(Double.self) {
                                            Text("\(String(format: "%.0f", v))°")
                                                .font(.caption)
                                                .foregroundColor(.white)
                                        }
                                    }
                                }}
                                .chartXAxisLabel("Reps", position: .bottom)
                                .chartYAxisLabel("Angle (degrees)", position: .leading)
                            } else {
                                Text("No ROM data available")
                                    .foregroundColor(.gray)
                                    .frame(height: 300)
                            }
                        } else {
                            // Smoothness Trend Chart
                            if !sessionData.sparcHistory.isEmpty {
                                SmoothnessTrendChartView(
                                    sparcHistory: sessionData.sparcHistory,
                                    title: "📊 Smoothness Trend"
                                )
                                .padding(.horizontal, 20)
                            } else {
                                Text("No smoothness data available")
                                    .foregroundColor(.gray)
                                    .frame(height: 300)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
                }
                .padding(.bottom, 10)
            }
            .frame(maxHeight: .infinity)
            
            // Done and Retry buttons at bottom
            HStack(spacing: 20) {
                Button(action: {
                    showingPostSurvey = true
                    postSurveySkipped = false
                }) {
                    Text("Done")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(width: 120, height: 50)
                        .background(Color.green)
                        .cornerRadius(12)
                }
                .tapTarget(60)
                
                Button(action: {
                    showingPostSurvey = true
                    postSurveySkipped = false
                }) {
                    Text("Retry")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(width: 120, height: 50)
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .tapTarget(60)
            }
            .padding(.bottom, 40)
        }
        .background(Color.black)
        .navigationBarHidden(true)
        .onAppear {
            motionService.stopSession()
            motionService.stopCamera(tearDownCompletely: true)
        }
        .sheet(isPresented: $showingPostSurvey) {
            PostSurveyRetryView(
                isPresented: $showingPostSurvey,
                postSurveyData: $postSurveyData,
                sessionData: sessionData,
                onComplete: { action in
                    switch action {
                    case .submitted:
                        postSurveySkipped = false
                        completeAndUploadSession()
                    case .skipped:
                        postSurveySkipped = true
                        completeAndUploadSession()
                    case .retry:
                        break
                    }
                }
            )
        }
        .task {
            if let existing = geminiService.lastAnalysis {
                aiScoreLocal = existing.overallPerformance
                aiFeedbackLocal = existing.specificFeedback
                isAILoading = false
                print("📊 [ResultsView] Using existing AI analysis: score=\(aiScoreLocal ?? 0)")
            } else {
                do {
                    let analysis = try await geminiService.analyzeExerciseSession(sessionData)
                    aiScoreLocal = analysis.overallPerformance
                    aiFeedbackLocal = analysis.specificFeedback
                    isAILoading = false
                    print("📊 [ResultsView] Generated new AI analysis: score=\(aiScoreLocal ?? 0)")
                } catch {
                    isAILoading = false
                    print("❌ [ResultsView] AI analysis failed: \(error)")
                }
            }
        }
    }
    
    // MARK: - Helpers & Actions

    // Simple linear regression (least squares) returning slope m and intercept b for y = m*x + b
    private func linearFit(x: [Double], y: [Double]) -> (Double, Double)? {
        guard x.count == y.count, x.count >= 2 else { return nil }
        let n = Double(x.count)
        let sumX = x.reduce(0, +)
        let sumY = y.reduce(0, +)
        let sumXY = zip(x, y).reduce(0) { $0 + $1.0 * $1.1 }
        let sumX2 = x.reduce(0) { $0 + $1 * $1 }

        let denom = (n * sumX2 - sumX * sumX)
        if abs(denom) < 1e-9 { return nil }
        let m = (n * sumXY - sumX * sumY) / denom
        let b = (sumY - m * sumX) / n
        if m.isFinite && b.isFinite { return (m, b) }
        return nil
    }

    private var displayedAIScore: Int {
        if isAILoading { return 0 }
        return aiScoreLocal ?? 0
    }
    
    private var displayedAIFeedback: String {
        if isAILoading { return "Analyzing your performance with AI..." }
        if !aiFeedbackLocal.isEmpty { return aiFeedbackLocal }
        return "AI analysis is currently unavailable. Please check your connection and try again."
    }

    private func completeAndUploadSession() {
        print("📊 [ResultsView] Completing session — saving locally, then navigating home…")
        // Prepare enriched session snapshot
        let postSurveyPayload: PostSurveyData? = {
            guard !postSurveySkipped else { return nil }
            return PostSurveyData(
                painLevel: postSurveyData.painLevel,
                funRating: postSurveyData.funRating,
                difficultyRating: postSurveyData.difficultyRating,
                enjoymentRating: postSurveyData.enjoymentRating,
                perceivedExertion: postSurveyData.perceivedExertion,
                willingnessToRepeat: postSurveyData.willingnessToRepeat,
                timestamp: Date()
            )
        }()

        let enriched = ExerciseSessionData(
            id: sessionData.id,
            exerciseType: sessionData.exerciseType,
            score: sessionData.score,
            reps: sessionData.reps,
            maxROM: sessionData.maxROM,
            averageROM: sessionData.averageROM,
            duration: sessionData.duration,
            timestamp: sessionData.timestamp,
            romHistory: sessionData.romHistory,
            repTimestamps: sessionData.repTimestamps,
            sparcHistory: sessionData.sparcHistory,
            romData: sessionData.romData,
            sparcData: sessionData.sparcData,
            aiScore: aiScoreLocal ?? sessionData.aiScore,
            painPre: sessionData.painPre,
            painPost: postSurveyPayload?.painLevel,
            sparcScore: sessionData.sparcScore,
            formScore: sessionData.formScore,
            consistency: sessionData.consistency,
            peakVelocity: sessionData.peakVelocity,
            motionSmoothnessScore: sessionData.motionSmoothnessScore,
            accelAvgMagnitude: sessionData.accelAvgMagnitude,
            accelPeakMagnitude: sessionData.accelPeakMagnitude,
            gyroAvgMagnitude: sessionData.gyroAvgMagnitude,
            gyroPeakMagnitude: sessionData.gyroPeakMagnitude,
            aiFeedback: aiFeedbackLocal.isEmpty ? nil : aiFeedbackLocal,
            goalsAfter: LocalDataManager.shared.getCachedGoals()
        )

        // Persist locally first so Home can refresh immediately from cache
        let sessionFile = SessionFile(
            exerciseType: enriched.exerciseType,
            timestamp: enriched.timestamp,
            romPerRep: enriched.romHistory,
            sparcHistory: enriched.sparcHistory,
            romHistory: enriched.romData.map { $0.angle },
            maxROM: enriched.maxROM,
            reps: enriched.reps,
            sparcDataPoints: enriched.sparcData
        )
        LocalDataManager.shared.saveSessionFile(sessionFile)

        // Use real time-based SPARC points for upload (mapped from SPARCPoint)
        let sparcDataPoints: [SPARCDataPoint] = enriched.sparcData.map { point in
            SPARCDataPoint(timestamp: point.timestamp, sparcValue: point.sparc, movementPhase: "steady", jointAngles: [:], confidence: 0.5, dataSource: .imu)
        }

        let performanceData = ExercisePerformanceData(
            score: enriched.score,
            reps: enriched.reps,
            duration: enriched.duration,
            romData: enriched.romData.map { $0.angle },
            romPerRep: enriched.romHistory,
            repTimestamps: enriched.repTimestamps,
            sparcDataPoints: sparcDataPoints,
            movementQualityScores: enriched.sparcHistory,
            aiScore: enriched.aiScore ?? 0,
            aiFeedback: enriched.aiFeedback ?? "",
            sparcScore: enriched.sparcScore,
            gameSpecificData: "",
            accelAvg: nil,
            accelPeak: nil,
            gyroAvg: nil,
            gyroPeak: nil
        )

        let comprehensiveSession = ComprehensiveSessionData(
            userID: "local_user",
            sessionNumber: LocalDataManager.shared.nextSessionNumber(),
            exerciseName: enriched.exerciseType,
            duration: enriched.duration,
            performanceData: performanceData,
            preSurvey: PreSurveyData(
                painLevel: enriched.painPre ?? 0,
                timestamp: enriched.timestamp,
                exerciseReadiness: nil,
                previousExerciseHours: nil
            ),
            postSurvey: postSurveyPayload,
            goalsBefore: LocalDataManager.shared.getCachedGoals(),
            goalsAfter: LocalDataManager.shared.getCachedGoals()
        )
        LocalDataManager.shared.saveComprehensiveSession(comprehensiveSession)
        print("✅ [ResultsView] Session saved to local storage (immediate)")

        // Notify listeners (HomeView) immediately so UI refreshes from local cache
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .sessionUploadCompleted, object: nil, userInfo: ["session": comprehensiveSession])
        }

        // Navigate home immediately; HomeView.onAppear will read updated LocalDataManager
        DispatchQueue.main.async { navigationCoordinator.goHome() }

        // Upload to backend service (posts SessionUploadCompleted on main).
        // Use Task{} so publishes occur on main actor when needed.
        Task { [service = backendService, enriched, sessionFile, comprehensiveSession] in
            await service.saveSession(enriched, sessionFile: sessionFile, comprehensive: comprehensiveSession)
            print("✅ [ResultsView] Session uploaded to backend (background)")
        }
    }
}

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .white : .gray)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .padding(.vertical, 10)
        .background(isSelected ? Color.white.opacity(0.1) : Color.clear)
    }
}

struct MetricPill: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.blue)
            
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .default))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(Color.white.opacity(0.08))
        .cornerRadius(12)
    }
}

#Preview {
    ResultsView(sessionData: ExerciseSessionData(
        exerciseType: "Pendulum Swing",
        score: 85,
        reps: 12,
        maxROM: 65.5,
        duration: 90.0,
        romHistory: [45.2, 52.1, 58.3, 65.5, 62.1, 59.8, 63.2, 67.1, 64.5, 61.2, 66.8, 65.5],
        sparcHistory: [75, 82, 78, 85, 88, 76, 83, 89, 81, 87, 84, 86],
        aiScore: 87,
        sparcScore: 82
    ))
    .environmentObject(NavigationCoordinator.shared)
    .background(Color.black)
}
