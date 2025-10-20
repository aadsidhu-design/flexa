import SwiftUI
import AVFoundation

struct WallClimbersGameView: View {
    @EnvironmentObject var motionService: SimpleMotionService
    @Environment(\.backendService) var backendService
    @State private var score: Int = 0
    @State private var altitude: Double = 0
    @State private var gameTime: TimeInterval = 0
    @State private var isGameActive = false
    @State private var gameTimer: Timer?
    @State private var lastWristY: Double = 0.5
    @State private var climbingPhase: CameraRepDetector.ClimbingPhase = .waitingToStart
    @State private var showingAnalyzing = false
    @State private var showingResults = false
    @State private var sessionData: ExerciseSessionData?
    @State private var hasInitializedGame = false
    @State private var reps: Int = 0
    @State private var screenSize: CGSize = UIScreen.main.bounds.size
    @State private var repDetector: CameraRepDetector = CameraRepDetector(minimumInterval: 0.5)
    
    // Game constants
    private let maxAltitude: Double = 1000
    private let climbThreshold: Double = 0.08  // Less sensitive for cleaner rep detection
    
    var body: some View {
        GeometryReader { geometry in
        ZStack {
            CameraGameBackground()
                
            // Gameplay overlays intentionally removed for minimalist HUD — only altitude meter remains
            
            // Camera obstruction overlay
            if motionService.isCameraObstructed {
                CameraObstructionOverlay(
                    isObstructed: motionService.isCameraObstructed,
                    reason: motionService.cameraObstructionReason,
                    isBackCamera: false
                )
                .zIndex(1000)
            }
            
            // Minimal UI — only altitude meter on the right edge, stretching vertically
            HStack {
                Spacer()
                VerticalAltitudeMeter(altitude: altitude, maxAltitude: maxAltitude)
                    .frame(width: 50, height: geometry.size.height * 0.75)  // Stretch from bottom-ish to top-ish
                    .padding(.trailing, 15)
                    .padding(.vertical, geometry.size.height * 0.125)  // Equal padding top and bottom for centering
            }
        }
        .onAppear {
            screenSize = geometry.size
        }
        .onChange(of: geometry.size) { newSize in
            screenSize = newSize
        }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            // Keep screen on during game
            UIApplication.shared.isIdleTimerDisabled = true
            
            guard !hasInitializedGame else {
                FlexaLog.motion.info("🔁 [WallClimbers] View reappeared - skipping automatic setup (already initialized)")
                return
            }
            hasInitializedGame = true
            FlexaLog.game.info("🔍 [WallClimbers] onAppear called - setting up game")
            setupGame()
        }
        .onDisappear {
            // Re-enable idle timer (allow screen to sleep)
            UIApplication.shared.isIdleTimerDisabled = false
            
            motionService.stopSession()
            cleanupGame()
        }
        .onReceive(motionService.$currentReps) { reps = $0 }
        .fullScreenCover(isPresented: $showingAnalyzing) {
            if let data = sessionData {
                AnalyzingView(sessionData: data)
                .environmentObject(NavigationCoordinator.shared)
                .onDisappear {
                    showingResults = true
                }
            }
        }
        .fullScreenCover(isPresented: $showingResults) {
            if let data = sessionData {
                ResultsView(sessionData: data)
                    .environmentObject(NavigationCoordinator.shared)
            }
        }
    }
    
    private func setupGame() {
        FlexaLog.game.info("🔍 [WallClimbers] setupGame called - starting game session")
        motionService.preferredCameraJoint = .armpit
        motionService.startGameSession(gameType: .wallClimbers)
        FlexaLog.game.info("🔍 [WallClimbers] Game session started")
        resetGame()
        FlexaLog.game.info("🔍 [WallClimbers] Game reset")
        startGame()
        FlexaLog.game.info("🔍 [WallClimbers] Game started")
    }
    
    private func resetGame() {
        score = 0
        altitude = 0
        gameTime = 0
        lastWristY = 0
        reps = 0
        repDetector.resetWallClimbersState()
    }
    
    private func startGame() {
    FlexaLog.game.info("🎮 [WallClimbers] Starting game - motionService active: \(motionService.isSessionActive), ARKit running: \(motionService.isARKitRunning)")
        isGameActive = true
        gameTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { timer in
            guard self.isGameActive else {
                timer.invalidate()
                self.gameTimer = nil
                return
            }
            self.updateGame()
        }
        FlexaLog.motion.info("✅ [WallClimbers] Game started successfully - gameTimer: \(gameTimer != nil)")
    }
    
    private func stopGame() {
        FlexaLog.motion.info("🎮 [WallClimbers] Stopping game - motionService active: \(motionService.isSessionActive), ARKit running: \(motionService.isARKitRunning)")
        isGameActive = false
        gameTimer?.invalidate()
        gameTimer = nil
        FlexaLog.motion.info("🛑 [WallClimbers] Game stopped - timer invalidated, ending game session")
        endGame()
    }
    
    private func updateGame() {
        if motionService.isCameraObstructed {
            FlexaLog.game.warning("🚨 [WallClimbers] Camera obstructed - pausing game tick")
            return
        }
        gameTime += 1.0/60.0
        FlexaLog.game.debug("⏱ [WallClimbers] Game tick - time: \(gameTime), altitude: \(altitude), reps: \(reps)")
        if altitude >= maxAltitude {
            FlexaLog.game.info("⏰ [WallClimbers] Max altitude reached - stopping game")
            stopGame()
            return
        }
        updateHandPositions()
        updateClimbing()
    }
    
    private func updateHandPositions() {
        guard let keypoints = motionService.poseKeypoints else { 
            return 
        }
        
        let currentTime = Date().timeIntervalSince1970
        let confidenceThreshold: Float = 0.2

        // Feed SPARC analyzer with the active wrist to capture smoothness without UI artifacts
        let activeSide = keypoints.phoneArm
        let activeWristConfidence = (activeSide == .left) ? keypoints.leftWristConfidence : keypoints.rightWristConfidence
        
        if let activeWrist = (activeSide == .left) ? keypoints.leftWrist : keypoints.rightWrist,
           activeWristConfidence > confidenceThreshold {
            let mapped = CoordinateMapper.mapVisionPointToScreen(activeWrist, cameraResolution: motionService.cameraResolution, previewSize: screenSize, isPortrait: true, flipY: false)
            let wristPos = SIMD3<Float>(Float(mapped.x), Float(mapped.y), 0)
            motionService.sparcService.addCameraMovement(position: wristPos, timestamp: currentTime)
        } else {
            // Fallback to whichever wrist is currently visible to keep data flowing
            if let left = keypoints.leftWrist, keypoints.leftWristConfidence > confidenceThreshold {
                let mapped = CoordinateMapper.mapVisionPointToScreen(left, cameraResolution: motionService.cameraResolution, previewSize: screenSize, isPortrait: true, flipY: false)
                let leftPos = SIMD3<Float>(Float(mapped.x), Float(mapped.y), 0)
                motionService.sparcService.addCameraMovement(position: leftPos, timestamp: currentTime)
            } else if let right = keypoints.rightWrist, keypoints.rightWristConfidence > confidenceThreshold {
                let mapped = CoordinateMapper.mapVisionPointToScreen(right, cameraResolution: motionService.cameraResolution, previewSize: screenSize, isPortrait: true, flipY: false)
                let rightPos = SIMD3<Float>(Float(mapped.x), Float(mapped.y), 0)
                motionService.sparcService.addCameraMovement(position: rightPos, timestamp: currentTime)
            }
        }
    }
    
    private func updateClimbing() {
        guard let keypoints = motionService.poseKeypoints else {
            return
        }

        let confidenceThreshold: Float = 0.2
        let activeSide = keypoints.phoneArm
        var trackingSide = activeSide
        var wristPoint: CGPoint? = nil
        
        // Try preferred side first with confidence check
        if activeSide == .left {
            if let left = keypoints.leftWrist, keypoints.leftWristConfidence > confidenceThreshold {
                wristPoint = left
            } else if let right = keypoints.rightWrist, keypoints.rightWristConfidence > confidenceThreshold {
                wristPoint = right
                trackingSide = .right
                FlexaLog.game.debug("🧗 [WallClimbers] Falling back to right wrist for altitude tracking")
            }
        } else {
            if let right = keypoints.rightWrist, keypoints.rightWristConfidence > confidenceThreshold {
                wristPoint = right
            } else if let left = keypoints.leftWrist, keypoints.leftWristConfidence > confidenceThreshold {
                wristPoint = left
                trackingSide = .left
                FlexaLog.game.debug("🧗 [WallClimbers] Falling back to left wrist for altitude tracking")
            }
        }

        guard let wrist = wristPoint else { return }

        let mappedWrist = CoordinateMapper.mapVisionPointToScreen(
            wrist,
            cameraResolution: motionService.cameraResolution,
            previewSize: screenSize,
            isPortrait: true,
            flipY: false
        )
        let currentWristY = CGFloat(mappedWrist.y)

        let alpha: CGFloat = 0.25
        let smoothY = alpha * currentWristY + (1 - alpha) * CGFloat(lastWristY)

        var currentROM = motionService.currentROM
        if currentROM <= 0 {
            let rawArmpitROM = keypoints.getArmpitROM(side: trackingSide)
            currentROM = motionService.validateAndNormalizeROM(rawArmpitROM)
        }

        let result = repDetector.processWallClimbersMotion(
            wristY: smoothY,
            rom: currentROM,
            threshold: climbThreshold,
            screenHeight: screenSize.height
        )

        if result.repDetected {
            let minimumThreshold = motionService.getMinimumROMThreshold(for: .wallClimbers)

            if result.peakROM >= minimumThreshold {
                motionService.recordCameraRepCompletion(rom: result.peakROM)
                reps = motionService.currentReps

                let baseGain = maxAltitude / 20.0
                let romBoost = min(1.5, max(0.5, result.peakROM / max(minimumThreshold, 1)))
                let altitudeGain = baseGain * romBoost
                altitude = min(maxAltitude, altitude + altitudeGain)
                score += Int(altitudeGain / (maxAltitude / 100.0))

                FlexaLog.game.info("🧗 [WallClimbers] ✅ Rep #\(reps) completed! ROM: \(String(format: "%.1f", result.peakROM))°, Distance: \(String(format: "%.0f", result.distanceTraveled))px, Altitude: \(Int(altitude))m")

                HapticFeedbackService.shared.successHaptic()
            } else {
                FlexaLog.game.debug("🧗 [WallClimbers] ⚠️ Rep ROM too low: \(String(format: "%.1f", result.peakROM))° < \(String(format: "%.1f", minimumThreshold))°")
            }
        }

        lastWristY = Double(smoothY)
    }
    
    private func endGame() {
        isGameActive = false
        gameTimer?.invalidate()
        
        let altitudeScore = Int(altitude)
        let snapshot = motionService.getFullSessionData(
            overrideExerciseType: GameType.wallClimbers.displayName,
            overrideScore: altitudeScore
        )
        var sessionData = snapshot
        if sessionData.romHistory.isEmpty {
            sessionData.romHistory = motionService.romPerRepArray.filter { $0.isFinite }
        }
        if sessionData.sparcHistory.isEmpty {
            sessionData.sparcHistory = motionService.sparcHistoryArray.filter { $0.isFinite }
        }

        print("🧗 [WallClimbers] Final stats - Score: \(sessionData.score), Reps: \(sessionData.reps), MaxROM: \(String(format: "%.1f", sessionData.maxROM))°, SPARC avg: \(String(format: "%.1f", sessionData.sparcScore))")

        motionService.stopSession()
        self.sessionData = sessionData
        let userInfo = motionService.buildSessionNotificationPayload(from: sessionData)
        NotificationCenter.default.post(name: NSNotification.Name("MountainGameEnded"), object: nil, userInfo: userInfo)
    // Navigation triggered via CleanGameHostView observer for the posted notification
    }
    
    private func cleanupGame() {
        gameTimer?.invalidate()
        motionService.stopSession()
    }
}

struct VerticalAltitudeMeter: View {
    let altitude: Double
    let maxAltitude: Double
    
    var body: some View {
        let progress = min(altitude / maxAltitude, 1.0)
        
        GeometryReader { geometry in
            // Meter bar - stretches full height with no text
            ZStack(alignment: .bottom) {
                // Background with gradient border
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.5), lineWidth: 2)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.4))
                    )
                
                // Progress with smooth gradient
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                .green,
                                .yellow,
                                .orange,
                                .red
                            ]),
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(height: max(4, progress * (geometry.size.height - 4)))
                    .animation(.easeInOut(duration: 0.3), value: progress)
                    .padding(2)
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.6))
                    .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 2)
            )
        }
    }
}

#Preview {
    WallClimbersGameView()
        .environmentObject(SimpleMotionService.shared)
}
