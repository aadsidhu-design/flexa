import SwiftUI
import simd

struct CustomExerciseGameView: View {
    @EnvironmentObject private var motionService: SimpleMotionService
    @EnvironmentObject private var navigationCoordinator: NavigationCoordinator
    @StateObject private var customRepDetector = CustomRepDetector()

    let exercise: CustomExercise

    @State private var hasInitializedGame = false
    @State private var isGameActive = false
    @State private var gameTime: TimeInterval = 0
    @State private var gameTimer: Timer?
    @State private var sessionData: ExerciseSessionData?
    @State private var latestReps: Int = 0
    @State private var maxObservedROM: Double = 0
    @State private var cameraSampleTimer: Timer?

    private let gameDuration: TimeInterval = 120

    var body: some View {
        ZStack {
            backgroundView

            VStack(spacing: 24) {
                timerView

                InstructionBadge(title: "Reminder", icon: "lightbulb.fill") {
                    Text(exercise.displayReminder)
                        .font(.body)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 24)

                Spacer()
            }
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: prepareGame)
        .onDisappear(perform: cleanupGame)
        .onReceive(customRepDetector.$currentReps) { reps in
            latestReps = reps
        }
        .onReceive(customRepDetector.$currentROM) { romValue in
            maxObservedROM = max(maxObservedROM, romValue)
        }
        .onReceive(motionService.$currentROM) { romValue in
            guard exercise.trackingMode == .camera else { return }
            maxObservedROM = max(maxObservedROM, romValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            endGame()
        }
    }

    private var backgroundView: some View {
        Group {
            if exercise.trackingMode == .camera {
                CameraGameBackground()
            } else {
                Color.black
            }
        }
    }

    private var timerView: some View {
        Text(timeString(from: max(0, gameDuration - gameTime)))
            .font(.system(size: 48, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .monospacedDigit()
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.6))
            .cornerRadius(20)
            .padding(.top, 60)
    }

    private func prepareGame() {
        guard !hasInitializedGame else { return }
        hasInitializedGame = true
        UIApplication.shared.isIdleTimerDisabled = true

        customRepDetector.startSession(exercise: exercise)

        if exercise.trackingMode == .handheld {
            startHandheldMode()
        } else {
            startCameraMode()
        }

        startTimer()
        isGameActive = true
    }

    private func startHandheldMode() {
        motionService.startGameSession(gameType: .makeYourOwn)

        motionService.arkitTracker.onTransformUpdate = { [weak customRepDetector] transform, timestamp in
            let position = simd_float3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            customRepDetector?.processHandheldPosition(position, timestamp: timestamp)
        }
    }

    private func startCameraMode() {
        motionService.startGameSession(gameType: .camera, jointToTrack: exercise.jointToTrack?.toCameraJointPreference())

        cameraSampleTimer?.invalidate()
        cameraSampleTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            guard isGameActive else { return }
            guard let keypoints = motionService.poseKeypoints else { return }
            let timestamp = Date().timeIntervalSince1970
            customRepDetector.processCameraKeypoints(keypoints, timestamp: timestamp)
        }
    }

    private func startTimer() {
        gameTimer?.invalidate()
        gameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { timer in
            guard isGameActive else {
                timer.invalidate()
                return
            }

            gameTime += 1.0 / 60.0

            if gameTime >= gameDuration {
                endGame()
            }
        }
    }

    private func endGame() {
        guard isGameActive else { return }
        isGameActive = false
        UIApplication.shared.isIdleTimerDisabled = false
        gameTimer?.invalidate()
        gameTimer = nil
        cameraSampleTimer?.invalidate()
        cameraSampleTimer = nil

        customRepDetector.stopSession()
        motionService.stopSession()

        let sessionData = buildSessionData()
        self.sessionData = sessionData

    // Record completion in CustomExerciseManager to update counters and averages
    CustomExerciseManager.shared.recordCompletion(for: exercise.id, rom: sessionData.maxROM, sparc: sessionData.sparcScore)

        navigationCoordinator.showAnalyzing(sessionData: sessionData)
    }

    private func cleanupGame() {
        gameTimer?.invalidate()
        gameTimer = nil
        cameraSampleTimer?.invalidate()
        cameraSampleTimer = nil
        customRepDetector.stopSession()
        motionService.stopSession()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func buildSessionData() -> ExerciseSessionData {
        let summary = customRepDetector.sessionSummary()
        let finalReps = summary.reps
        let romHistory = summary.romHistory.isEmpty ? motionService.romPerRepArray : summary.romHistory
        let finalROM: Double
        if summary.maxROM > 0 {
            finalROM = summary.maxROM
        } else if exercise.trackingMode == .handheld {
            finalROM = maxObservedROM
        } else {
            finalROM = motionService.maxROM
        }

        let finalSPARC = motionService.sparcService.getCurrentSPARC()
        
        // 🔧 FIX: Collect SPARC data with timestamps for smoothness graphing
        let sparcDataPoints = motionService.sparcService.getSPARCDataPoints()
        let sparcDataWithTimestamps: [SPARCPoint] = sparcDataPoints.map { dataPoint in
            SPARCPoint(
                sparc: dataPoint.sparcValue,
                timestamp: dataPoint.timestamp
            )
        }
        
        FlexaLog.motion.info("📊 [CustomExercise] Session complete: \(finalReps) reps, ROM \(String(format: "%.1f", finalROM))°, SPARC \(String(format: "%.1f", finalSPARC)), \(sparcDataWithTimestamps.count) smoothness data points")

        return ExerciseSessionData(
            id: UUID().uuidString,
            exerciseType: exercise.name,
            score: finalReps * 10,
            reps: finalReps,
            maxROM: finalROM,
            duration: gameTime,
            romHistory: romHistory,
            sparcHistory: motionService.sparcHistoryArray,
            sparcData: sparcDataWithTimestamps, // ✅ Now smoothness graph will work!
            painPre: motionService.prePainLevel,
            painPost: motionService.postPainLevel,
            sparcScore: finalSPARC
        )
    }

    private func timeString(from seconds: TimeInterval) -> String {
        let clamped = max(0, seconds)
        let mins = Int(clamped) / 60
        let secs = Int(clamped) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

private struct InstructionBadge<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(LinearGradient(colors: [Color.green.opacity(0.9), Color.blue.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .font(.system(size: 20, weight: .semibold))
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }
            content
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

private extension CustomExercise {
    var displayReminder: String {
        let trimmed = userDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }

        switch trackingMode {
        case .handheld:
            return "Move through the motion you described during setup. Keep each swing smooth and let the timer guide your pace."
        case .camera:
            return "Stay centered in the camera view and focus on steady, pain-free range. Let your arm trace the arc you planned."
        }
    }
}

#Preview {
    let sampleExercise = CustomExercise(
        name: "Shoulder Clocks",
        userDescription: "Reach up, out, and down like tracing a clock face.",
        trackingMode: .camera,
        jointToTrack: .armpit,
        repParameters: CustomExercise.RepParameters(
            movementType: .mixed,
            minimumROMThreshold: 45,
            minimumDistanceThreshold: nil,
            directionality: .bidirectional,
            repCooldown: 2.0
        )
    )

    return CustomExerciseGameView(exercise: sampleExercise)
        .environmentObject(SimpleMotionService.shared)
        .environmentObject(NavigationCoordinator.shared)
}
