import SwiftUI
import simd

struct MakeYourOwnGameView: View {
    @Binding var score: Int
    @Binding var reps: Int
    @Binding var rom: Double
    @Binding var isActive: Bool
    var isHosted: Bool = false

    @EnvironmentObject private var motionService: SimpleMotionService
    @EnvironmentObject private var backendService: BackendService
    @StateObject private var exerciseManager = CustomExerciseManager.shared
    @StateObject private var customRepDetector = CustomRepDetector()

    @State private var isGameActive = false
    @State private var elapsedTime: TimeInterval = 0
    @State private var gameTimer: Timer?
    @State private var cameraSampleTimer: Timer?
    @State private var activeMode: ExerciseMode? = nil
    @State private var activeExercise: CustomExercise?

    private let targetDuration: TimeInterval = 120

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                if isGameActive, let activeMode {
                    ActiveSessionView(
                        mode: activeMode,
                        elapsedTime: elapsedTime,
                        totalDuration: targetDuration,
                        endAction: endExercise,
                        screenSize: geometry.size
                    )
                    .environmentObject(motionService)
                } else {
                    InstructionStageView(
                        durationText: formattedDuration(targetDuration),
                        overview: customInstructionsSummary(),
                        cameraSetup: cameraSetupText(),
                        handheldSetup: handheldSetupText(),
                        analysis: exerciseManager.latestAnalysis?.analysis,
                        startCamera: { startExercise(with: .camera) },
                        startHandheld: { startExercise(with: .handheld) }
                    )
                }
            }
            .onAppear {
                resetBindings()
            }
            .onDisappear {
                cleanup()
            }
            .onReceive(customRepDetector.$currentReps) { newReps in
                self.reps = newReps
                self.score = newReps * 10
            }
            .onReceive(customRepDetector.$currentROM) { romValue in
                self.rom = max(self.rom, romValue)
            }
            .onReceive(motionService.$maxROM) { self.rom = max(self.rom, $0) }
            // Dismiss keyboard when tapping anywhere
            .dismissKeyboardOnTap()
        }
    }

    private func startExercise(with mode: ExerciseMode) {
        guard !isGameActive else { return }
        let exerciseConfig = buildExercise(for: mode)
        activeExercise = exerciseConfig
        activeMode = mode
        isGameActive = true
        isActive = true
        elapsedTime = 0
        score = 0
        reps = 0
        rom = 0

        customRepDetector.startSession(exercise: exerciseConfig)
        startSession(for: mode, exercise: exerciseConfig)
        startTimer()
    }

    private func startSession(for mode: ExerciseMode, exercise: CustomExercise) {
        cameraSampleTimer?.invalidate()
        motionService.arkitTracker.onTransformUpdate = nil

        switch mode {
        case .camera:
            motionService.startGameSession(gameType: .camera, jointToTrack: exercise.jointToTrack?.toCameraJointPreference())
            startCameraSampling()
        case .handheld:
            motionService.startGameSession(gameType: .makeYourOwn)
            motionService.arkitTracker.onTransformUpdate = { [weak customRepDetector] transform, timestamp in
                let position = simd_float3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
                customRepDetector?.processHandheldPosition(position, timestamp: timestamp)
            }
        }
    }

    private func startCameraSampling() {
        cameraSampleTimer?.invalidate()
        cameraSampleTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            guard self.isGameActive else { return }
            guard let keypoints = self.motionService.poseKeypoints else { return }
            let timestamp = Date().timeIntervalSince1970
            self.customRepDetector.processCameraKeypoints(keypoints, timestamp: timestamp)
        }
        if let timer = cameraSampleTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func buildExercise(for mode: ExerciseMode) -> CustomExercise {
        if let record = exerciseManager.latestAnalysis {
            let analysis = record.analysis
            let trackingMode: CustomExercise.TrackingMode = mode == .camera ? .camera : .handheld
            let romThreshold = max(analysis.minimumROMThreshold, 15)
            let distanceThreshold = analysis.minimumDistanceThreshold ?? 25

            var repParameters = CustomExercise.RepParameters(
                movementType: analysis.movementType,
                minimumROMThreshold: romThreshold,
                minimumDistanceThreshold: trackingMode == .handheld ? distanceThreshold : analysis.minimumDistanceThreshold,
                directionality: analysis.directionality,
                repCooldown: max(analysis.repCooldown, 0.35)
            )

            if trackingMode == .handheld && repParameters.minimumDistanceThreshold == nil {
                repParameters.minimumDistanceThreshold = distanceThreshold
            }

            let description = exerciseManager.latestGuidanceSummary ?? analysis.reasoning

            return CustomExercise(
                name: analysis.exerciseName,
                userDescription: description,
                trackingMode: trackingMode,
                jointToTrack: trackingMode == .camera ? (analysis.jointToTrack ?? .armpit) : nil,
                repParameters: repParameters
            )
        }

        let trackingMode: CustomExercise.TrackingMode = mode == .camera ? .camera : .handheld
        let fallbackParameters = CustomExercise.RepParameters(
            movementType: trackingMode == .camera ? .vertical : .pendulum,
            minimumROMThreshold: trackingMode == .camera ? 35 : 30,
            minimumDistanceThreshold: trackingMode == .handheld ? 25 : nil,
            directionality: .bidirectional,
            repCooldown: 1.0
        )

        return CustomExercise(
            name: "Make Your Own",
            userDescription: "Follow your tailored movement pattern.",
            trackingMode: trackingMode,
            jointToTrack: trackingMode == .camera ? .armpit : nil,
            repParameters: fallbackParameters
        )
    }

    private func startTimer() {
        gameTimer?.invalidate()
        gameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { timer in
            guard self.isGameActive else {
                timer.invalidate()
                return
            }
            self.elapsedTime += 1.0 / 60.0
            if self.elapsedTime >= self.targetDuration {
                self.endExercise()
            }
        }
    }

    private func endExercise() {
        guard isGameActive else { return }
        isGameActive = false
        isActive = false
        gameTimer?.invalidate()
        gameTimer = nil
        cameraSampleTimer?.invalidate()
        cameraSampleTimer = nil
        motionService.arkitTracker.onTransformUpdate = nil

        customRepDetector.stopSession()
        motionService.stopSession()
        let summary = customRepDetector.sessionSummary()

        score = summary.reps * 10
        reps = summary.reps
        rom = max(rom, summary.maxROM)

        var data = motionService.getFullSessionData(
            overrideExerciseType: activeExercise?.name ?? "Make Your Own",
            overrideScore: summary.reps * 10
        )
        data.reps = summary.reps
        if summary.maxROM > 0 {
            data.maxROM = max(data.maxROM, summary.maxROM)
        }
        if !summary.romHistory.isEmpty {
            data.romHistory = summary.romHistory
            let average = summary.romHistory.reduce(0, +) / Double(summary.romHistory.count)
            data.averageROM = average
        }

        activeExercise = nil
        NavigationCoordinator.shared.showAnalyzing(sessionData: data)
    }

    private func cleanup() {
        gameTimer?.invalidate()
        gameTimer = nil
        cameraSampleTimer?.invalidate()
        cameraSampleTimer = nil
        motionService.arkitTracker.onTransformUpdate = nil
        customRepDetector.stopSession()
        motionService.stopSession()
        isGameActive = false
        isActive = false
        activeExercise = nil
    }

    private func resetBindings() {
        score = 0
        reps = 0
        rom = 0
        customRepDetector.reset()
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 {
            return "\(minutes)m \(String(format: "%02d", seconds))s"
        } else {
            return "\(seconds)s"
        }
    }

    private func customInstructionsSummary() -> String {
        exerciseManager.latestGuidanceSummary ?? GameType.makeYourOwn.aiDescription
    }

    private func cameraSetupText() -> String {
        var base = "Prop your phone vertically so the front camera can clearly see your upper body. Step back far enough that your shoulders, elbows, and hands stay in frame."
        if let analysis = latestAnalysis, analysis.trackingMode == .camera {
            if let joint = analysis.jointToTrack {
                let focus = joint == .elbow ? "Focus on fully extending through the elbow." : "Let the camera see the lift through your shoulder." 
                base += " \(focus)"
            }
        }
        return base
    }

    private func handheldSetupText() -> String {
        var base = "Hold the phone securely in your hand with the screen facing you. Keep your grip relaxed so your wrist can move smoothly."
        if let analysis = latestAnalysis, analysis.trackingMode == .handheld {
            let movement = analysis.movementType.rawValue.replacingOccurrences(of: "_", with: " ")
            base += " The AI suggested focusing on \(movement) motion—move from the shoulder and keep a steady rhythm."
        }
        return base
    }

    private var latestAnalysis: AIExerciseAnalysis? {
        exerciseManager.latestAnalysis?.analysis
    }
}

private struct InstructionStageView: View {
    let durationText: String
    let overview: String
    let cameraSetup: String
    let handheldSetup: String
    let analysis: AIExerciseAnalysis?
    let startCamera: () -> Void
    let startHandheld: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 12) {
                Text("AI Tailored Exercise")
                    .font(.title)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text("Follow the guidance below. Choose camera or handheld, then the timer handles the rest.")
                    .font(.subheadline)
                    .foregroundColor(Color.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
            .padding(.top, 32)

            VStack(alignment: .leading, spacing: 18) {
                InstructionBadge(title: "Exercise overview", icon: "sparkles") {
                    Text(overview)
                        .font(.body)
                        .foregroundColor(.white)
                }

                if let analysis {
                    InstructionBadge(title: "AI recommendation", icon: "brain.head.profile") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Tracking: \(analysis.trackingMode == .camera ? "Camera" : "Handheld")")
                                .font(.callout)
                                .foregroundColor(.white)
                            if let joint = analysis.jointToTrack, analysis.trackingMode == .camera {
                                Text("Focus joint: \(joint.rawValue.capitalized)")
                                    .font(.callout)
                                    .foregroundColor(.white)
                            }
                            Text("Movement: \(analysis.movementType.rawValue.capitalized)")
                                .font(.callout)
                                .foregroundColor(.white)
                        }
                    }
                }

                InstructionBadge(title: "Setup", icon: "gearshape") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(cameraSetup)
                            .font(.callout)
                            .foregroundColor(.white)
                        Divider().background(Color.white.opacity(0.1))
                        Text(handheldSetup)
                            .font(.callout)
                            .foregroundColor(.white)
                        Divider().background(Color.white.opacity(0.1))
                        Text("Duration: \(durationText)")
                            .font(.footnote)
                            .foregroundColor(Color.white.opacity(0.7))
                    }
                }

                InstructionBadge(title: "When you're ready", icon: "play.circle.fill") {
                    Text("Take a steady breath, move into your starting position, then choose how you'd like to track your motion.")
                        .font(.callout)
                        .foregroundColor(.white)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 20)

            VStack(spacing: 16) {
                ModeButton(
                    title: "Start with Camera",
                    subtitle: "Live preview + timer",
                    systemImage: "camera.fill",
                    isRecommended: analysis?.trackingMode == .camera,
                    action: startCamera
                )
                ModeButton(
                    title: "Start with Handheld",
                    subtitle: "Phone motion + timer",
                    systemImage: "iphone.gen2",
                    isRecommended: analysis?.trackingMode == .handheld,
                    action: startHandheld
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }
}

private struct ModeButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isRecommended: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(LinearGradient(colors: [Color.green.opacity(0.9), Color.blue.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                    .foregroundColor(.black)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.black)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.black.opacity(0.7))
                }
                Spacer()
                Image(systemName: "arrow.forward.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.black.opacity(0.8))
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(buttonFill)
                    .shadow(color: shadowColor, radius: 14, x: 0, y: 6)
            )
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var buttonFill: LinearGradient {
        if isRecommended {
            return LinearGradient(colors: [Color.green.opacity(0.95), Color.blue.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            return LinearGradient(colors: [Color.white, Color.white.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var shadowColor: Color {
        isRecommended ? Color.green.opacity(0.35) : Color.black.opacity(0.2)
    }
}

private struct InstructionBadge<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

private struct ActiveSessionView: View {
    let mode: ExerciseMode
    let elapsedTime: TimeInterval
    let totalDuration: TimeInterval
    let endAction: () -> Void
    let screenSize: CGSize

    @EnvironmentObject private var motionService: SimpleMotionService
    @State private var supportTimer: Timer? = nil

    private var timeRemainingText: String {
        let remaining = max(0, totalDuration - elapsedTime)
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        ZStack {
            switch mode {
            case .camera:
                LiveCameraView()
                    .environmentObject(motionService)
                    .ignoresSafeArea()
                    .onAppear(perform: startSupportUpdates)
                    .onDisappear(perform: stopSupportUpdates)
            case .handheld:
                Color.black.ignoresSafeArea()
            }

            VStack(spacing: 20) {
                Text(timeRemainingText)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.65))
                    .cornerRadius(20)
                    .padding(.top, 60)

                InstructionBadge(title: "Reminder", icon: "lightbulb.fill") {
                    Text(mode.inSessionPrompt)
                        .font(.body)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 24)

                Spacer()

                Button(action: endAction) {
                    Text("End session early")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(18)
                }
                .padding(.bottom, 40)
            }
        }
    }

    private func startSupportUpdates() {
        guard mode == .camera else { return }
        supportTimer?.invalidate()
        supportTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            guard let keypoints = motionService.poseKeypoints else { return }
            let timestamp = Date().timeIntervalSince1970
            let activeSide = keypoints.phoneArm
            _ = (activeSide == .left) ? keypoints.leftWrist : keypoints.rightWrist
        if let wrist = motionService.poseKeypoints?.leftWrist {
            let mapped = CoordinateMapper.mapVisionPointToScreen(wrist, cameraResolution: motionService.cameraResolution, previewSize: screenSize, isPortrait: true, flipY: false)
            let wristPos = SIMD3<Float>(Float(mapped.x), Float(mapped.y), 0)
                motionService.sparcService.addCameraMovement(position: wristPos, timestamp: timestamp)
            }
        }
    }

    private func stopSupportUpdates() {
        supportTimer?.invalidate()
        supportTimer = nil
    }
}

private enum ExerciseMode {
    case camera
    case handheld

    var inSessionPrompt: String {
        switch self {
        case .camera:
            return "Keep your shoulders relaxed and let the camera see the arc of your movement. Focus on smooth, controlled reps."
        case .handheld:
            return "Hold the phone at a comfortable grip and move from the shoulder. Keep each swing steady and avoid rushing the timer."
        }
    }
}

#Preview {
    MakeYourOwnGameView(
        score: .constant(0),
        reps: .constant(0),
        rom: .constant(0),
        isActive: .constant(false)
    )
    .environmentObject(SimpleMotionService.shared)
    .environmentObject(BackendService())
}
