import SwiftUI
import AVFoundation

struct BalloonPopGameView: View {
    @EnvironmentObject var motionService: SimpleMotionService
    @Environment(\.backendService) var backendService
    @State private var score: Int = 0
    @State private var gameTime: TimeInterval = 0
    @State private var isGameActive = false
    @State private var gameTimer: Timer?
    @State private var showingAnalyzing = false
    @State private var showingResults = false
    @State private var sessionData: ExerciseSessionData?
    @State private var hasInitializedGame = false
    @State private var reps: Int = 0
    @State private var isInPosition = false
    @State private var leftHandPosition: CGPoint = .zero
    @State private var rightHandPosition: CGPoint = .zero
    @State private var activeArm: BodySide = .right
    
    // Game state
    @State private var balloons: [Balloon] = []
    @State private var popEffects: [PopEffect] = []
    @State private var balloonSpawnTimer: Timer?
    @State private var lastSpawnTime: TimeInterval = 0
    @State private var screenSize: CGSize = UIScreen.main.bounds.size
    @State private var repDetector: CameraRepDetector = CameraRepDetector(minimumInterval: 0.5)
    
    private let gameDuration: TimeInterval = 90 // 1 minute 30 seconds
    private let balloonSpawnInterval: TimeInterval = 1.5
    
    var body: some View {
        GeometryReader { geometry in
        ZStack {
            CameraGameBackground()
                
            // Balloons
            ForEach(balloons, id: \.id) { balloon in
                BalloonView(balloon: balloon)
            }
            
            // Hand tracking pin/dart (ONLY ACTIVE ARM) - SINGLE PIN clipped to wrist
            if isGameActive {
                let activePosition = (activeArm == .left) ? leftHandPosition : rightHandPosition
                
                // Only show pin if position is detected (wrist visible)
                if activePosition != .zero {
                    // DART visualization - bright and visible
                    ZStack {
                        // Dart tip (sharp point) - THE POPPING POINT
                        Path { p in
                            let x = activePosition.x
                            let y = activePosition.y
                            p.move(to: CGPoint(x: x, y: y - 15))  // Top point (longer)
                            p.addLine(to: CGPoint(x: x - 10, y: y + 15))  // Bottom left (wider)
                            p.addLine(to: CGPoint(x: x + 10, y: y + 15))  // Bottom right (wider)
                            p.closeSubpath()
                        }
                        .fill(Color.red)  // Red dart tip for better visibility
                        .shadow(color: Color.red.opacity(0.8), radius: 10)
                        
                        // Dart shaft
                        Rectangle()
                            .fill(LinearGradient(
                                gradient: Gradient(colors: [Color.orange, Color.red]),
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                            .frame(width: 6, height: 35)  // Slightly thicker and longer
                            .position(x: activePosition.x, y: activePosition.y - 30)
                        
                        // Dart head/fletching
                        Circle()
                            .fill(Color.yellow)
                            .frame(width: 18, height: 18)
                            .position(x: activePosition.x, y: activePosition.y - 48)
                            .shadow(color: Color.yellow.opacity(0.8), radius: 8)
                    }
                    .zIndex(100)  // Ensure dart is on top
                }
            }
            
            // Pop effects
            ForEach(popEffects, id: \.id) { effect in
                PopEffectView(effect: effect)
            }
            
            // Camera obstruction overlay
            if motionService.isCameraObstructed {
                CameraObstructionOverlay(
                    isObstructed: motionService.isCameraObstructed,
                    reason: motionService.cameraObstructionReason,
                    isBackCamera: false
                )
                .zIndex(1000)
            }
            
            // No UI overlay - just game
        }
        .onAppear {
            // Keep screen on during game
            UIApplication.shared.isIdleTimerDisabled = true
            
            screenSize = geometry.size
            
            guard !hasInitializedGame else {
                FlexaLog.motion.info("🔁 [BalloonPop] View reappeared - skipping automatic setup (already initialized)")
                return
            }
            hasInitializedGame = true
            FlexaLog.game.info("🔍 [BalloonPop] onAppear called - setting up game")
            setupGame()
        }
        .onChange(of: geometry.size) { newSize in
            screenSize = newSize
        }
        }
        .onDisappear {
            // Re-enable idle timer (allow screen to sleep)
            UIApplication.shared.isIdleTimerDisabled = false
            
            motionService.stopSession()
            cleanupGame()
        }
        .onReceive(motionService.$currentReps) { reps = $0 }
    // Navigation is now driven by NavigationCoordinator to avoid conflicting local covers.
    // When ready, call NavigationCoordinator.shared.showAnalyzing(sessionData:)
        .toolbar(.hidden, for: .navigationBar)
    }
    
    private func setupGame() {
    FlexaLog.game.info("🔍 [BalloonPop] setupGame called - starting game session")
    motionService.preferredCameraJoint = .elbow
    motionService.startGameSession(gameType: .balloonPop)
    FlexaLog.game.info("🔍 [BalloonPop] Game session started")
    resetGame()
    FlexaLog.game.info("🔍 [BalloonPop] Game reset")
    startGame()
    FlexaLog.game.info("🔍 [BalloonPop] Game started")
    }
    
    private func startGame() {
    FlexaLog.game.info("🎮 [BalloonPop] Starting game - motionService active: \(motionService.isSessionActive), ARKit running: \(motionService.isARKitRunning)")
        isGameActive = true
        gameTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { timer in
            guard self.isGameActive else {
                timer.invalidate()
                self.gameTimer = nil
                return
            }
            self.updateGame()
        }
        // Spawn one balloon at start, then only spawn one at a time when popped
        spawnBalloon()
        FlexaLog.motion.info("✅ [BalloonPop] Game started successfully - gameTimer: \(gameTimer != nil), initial balloon spawned")
        // Remove the timer - balloons will only spawn when popped
        // balloonSpawnTimer = Timer.scheduledTimer(withTimeInterval: balloonSpawnInterval, repeats: true) { _ in
        //     if balloons.count < 3 { spawnBalloon() }
        // }
    }
    
    private func resetGame() {
    score = 0
    gameTime = 0
    balloons = []
    popEffects = []
    reps = 0
    isInPosition = false
    repDetector.resetElbowExtensionState()
    }
    
    private func stopGame() {
        FlexaLog.motion.info("🎮 [BalloonPop] Stopping game - motionService active: \(motionService.isSessionActive), ARKit running: \(motionService.isARKitRunning)")
        isGameActive = false
        gameTimer?.invalidate()
        gameTimer = nil
        balloonSpawnTimer?.invalidate()
        balloonSpawnTimer = nil
        FlexaLog.motion.info("🛑 [BalloonPop] Game stopped - timers invalidated, ending game session")
        endGame()
    }
    
    private func updateGame() {
        if motionService.isCameraObstructed {
            FlexaLog.game.warning("🚨 [BalloonPop] Camera obstructed - pausing game tick")
            return
        }
        gameTime += 1.0/60.0
        FlexaLog.game.debug("⏱ [BalloonPop] Game tick - time: \(gameTime), score: \(score), reps: \(reps), balloons: \(balloons.count)")
        if gameTime >= gameDuration {
            FlexaLog.game.info("⏰ [BalloonPop] Game duration reached - stopping game")
            stopGame()
            return
        }
        updateHandPositions()
        checkBalloonPops()
        updateBalloons()
        cleanupEffects()
    }
    
    private func updateHandPositions() {
        guard let keypoints = motionService.poseKeypoints else { 
            // NO POSE DATA - hide pin
            leftHandPosition = .zero
            rightHandPosition = .zero
            return 
        }
        
        // AUTO-DETECT which arm is being used (phoneArm from VisionPoseProvider)
        var preferredArm = keypoints.phoneArm
        var wrist = preferredArm == .left ? keypoints.leftWrist : keypoints.rightWrist
        
        if wrist == nil {
            // Fall back to whichever wrist is visible so the dart always tracks something
            let fallbackArm: BodySide = preferredArm == .left ? .right : .left
            wrist = fallbackArm == .left ? keypoints.leftWrist : keypoints.rightWrist
            if wrist != nil {
                FlexaLog.game.debug("🎯 [BalloonPop] Falling back to \(fallbackArm == .left ? "left" : "right") wrist for tracking")
                preferredArm = fallbackArm
            }
        }
        
        guard let trackedWrist = wrist else {
            leftHandPosition = .zero
            rightHandPosition = .zero
            return
        }
        
        activeArm = preferredArm
        
        // Map wrist position to screen (same mapping as constellation game)
        let mapped = CoordinateMapper.mapVisionPointToScreen(
            trackedWrist,
            cameraResolution: motionService.cameraResolution,
            previewSize: screenSize,
            isPortrait: true,
            flipY: false
        )
        
        // Update ONLY the active hand position
        if activeArm == .left {
            // Initialize or smooth
            if leftHandPosition == .zero {
                leftHandPosition = mapped
            } else {
                // High alpha = very responsive, pin sticks to wrist
                let alpha: CGFloat = 0.85
                leftHandPosition = CGPoint(
                    x: leftHandPosition.x * (1 - alpha) + mapped.x * alpha,
                    y: leftHandPosition.y * (1 - alpha) + mapped.y * alpha
                )
            }
            // Hide inactive hand
            rightHandPosition = .zero
        } else {
            // Initialize or smooth
            if rightHandPosition == .zero {
                rightHandPosition = mapped
            } else {
                // High alpha = very responsive, pin sticks to wrist
                let alpha: CGFloat = 0.85
                rightHandPosition = CGPoint(
                    x: rightHandPosition.x * (1 - alpha) + mapped.x * alpha,
                    y: rightHandPosition.y * (1 - alpha) + mapped.y * alpha
                )
            }
            // Hide inactive hand
            leftHandPosition = .zero
        }
        
        // Feed SPARC with active wrist position only
        let wristPos = SIMD3<Float>(Float(mapped.x), Float(mapped.y), 0)
        motionService.sparcService.addCameraMovement(position: wristPos, timestamp: Date().timeIntervalSince1970)
        
        // Calculate elbow ROM for rep detection (use active arm only)
        let currentElbowAngle = calculateCurrentElbowAngle(keypoints: keypoints)
        if currentElbowAngle > 0 {
            detectElbowExtensionRep(currentAngle: currentElbowAngle)
        }
    }
    
    private func calculateCurrentElbowAngle(keypoints: SimplifiedPoseKeypoints) -> Double {
        // ✅ CONFIDENCE FILTERING: Only use landmarks with sufficient confidence
        let confidenceThreshold: Float = 0.2
        
        if activeArm == .left {
            // Check all required landmarks have sufficient confidence
            guard keypoints.leftShoulderConfidence > confidenceThreshold,
                  keypoints.leftElbowConfidence > confidenceThreshold,
                  keypoints.leftWristConfidence > confidenceThreshold else {
                return -1  // Invalid - low confidence
            }
            return keypoints.getLeftElbowAngle() ?? -1
        } else {
            guard keypoints.rightShoulderConfidence > confidenceThreshold,
                  keypoints.rightElbowConfidence > confidenceThreshold,
                  keypoints.rightWristConfidence > confidenceThreshold else {
                return -1  // Invalid - low confidence
            }
            return keypoints.getRightElbowAngle() ?? -1
        }
    }
    
    private func detectElbowExtensionRep(currentAngle: Double) {
        // Use CameraRepDetector for extension cycle detection
        let minimumThreshold = motionService.getMinimumROMThreshold(for: .balloonPop)
        
        let result = repDetector.processElbowExtension(
            elbowAngle: currentAngle,
            minimumROM: minimumThreshold
        )
        
        if result.repDetected {
            // Valid rep detected
            let validatedROM = motionService.validateAndNormalizeROM(result.rom)
            motionService.recordCameraRepCompletion(rom: validatedROM)
            reps = motionService.currentReps
            
            FlexaLog.game.info("🎈 [BalloonPop] Rep completed! Total reps: \(reps), ROM: \(String(format: "%.1f", validatedROM))°, threshold: \(String(format: "%.1f", minimumThreshold))°")
            
            // Haptic feedback
            HapticFeedbackService.shared.successHaptic()
        }
    }
    
    private func calculateJointAngle(a: CGPoint, b: CGPoint, c: CGPoint) -> Double {
        let v1 = CGPoint(x: a.x - b.x, y: a.y - b.y)
        let v2 = CGPoint(x: c.x - b.x, y: c.y - b.y)
        let dot = v1.x * v2.x + v1.y * v2.y
        let m1 = sqrt(v1.x * v1.x + v1.y * v1.y)
        let m2 = sqrt(v2.x * v2.x + v2.y * v2.y)
        guard m1 > 0, m2 > 0 else { return 0 }
        let cosAngle = max(-1.0, min(1.0, dot / (m1 * m2)))
        return acos(cosAngle) * 180.0 / .pi
    }
    
    private func spawnBalloon() {
        // Only spawn if we have no balloons (one at a time)
        guard balloons.count == 0 else { return }
        
        let colors: [Color] = [.red, .blue, .green, .yellow, .purple, .orange, .pink]
        // Three top bands: left, center, right with slight jitter
        let bandWidth = screenSize.width / 3.0
        var availableBands = [0,1,2]
        // Prefer bands not currently occupied
        let occupiedBands = Set(balloons.map { Int($0.position.x / bandWidth) })
        availableBands.removeAll(where: { occupiedBands.contains($0) })
        let bandIndex = (availableBands.isEmpty ? [0,1,2] : availableBands).randomElement()!
        let baseX = CGFloat(bandIndex) * bandWidth + bandWidth/2
        let jitter: CGFloat = bandWidth * 0.2
        let x = max(30, min(screenSize.width-30, baseX + CGFloat.random(in: -jitter...jitter)))
        let y = screenSize.height * 0.12 // near top
        
        let balloon = Balloon(
            id: UUID(),
            position: CGPoint(x: x, y: y),
            color: colors.randomElement()!,
            size: CGFloat.random(in: 50...60)
        )
        balloons.append(balloon)
    }
    
    private func checkBalloonPops() {
        var poppedBalloons: [UUID] = []
        
        for balloon in balloons {
            let activePosition = (activeArm == .left) ? leftHandPosition : rightHandPosition
            let distance = hypot(balloon.position.x - activePosition.x,
                                 balloon.position.y - activePosition.y)
            
            print("🔍 [BalloonPop] Balloon at (\(balloon.position.x), \(balloon.position.y)) - Active wrist distance: \(distance)")
            
            if distance <= balloon.size * 0.75 {
                poppedBalloons.append(balloon.id)
                score += 10
                print("🔍 [BalloonPop] Balloon popped! Score: \(score)")
                
                let effect = PopEffect(
                    id: UUID(),
                    position: balloon.position,
                    color: balloon.color
                )
                popEffects.append(effect)
                
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
            }
        }
        
        balloons.removeAll { poppedBalloons.contains($0.id) }
        
        // Spawn new balloons for each one popped
        for _ in poppedBalloons {
            spawnBalloon()
        }
    }
    
    private func updateBalloons() {
        // Balloons stay still at top of screen - no movement
        // Balloons stay until popped - no automatic removal
        // balloons.removeAll { balloon in
        //     Date().timeIntervalSince1970 - balloon.spawnTime > 5.0
        // }
    }
    
    private func cleanupEffects() {
        popEffects.removeAll { effect in
            Date().timeIntervalSince(effect.createdAt) > 1.0
        }
    }
    
    private func endGame() {
        isGameActive = false
        gameTimer?.invalidate()
        balloonSpawnTimer?.invalidate()
        
        let sessionSnapshot = motionService.getFullSessionData(
            overrideExerciseType: GameType.balloonPop.displayName,
            overrideScore: score
        )
        var sessionData = sessionSnapshot

        if sessionData.romHistory.isEmpty {
            sessionData.romHistory = motionService.romPerRepArray.filter { $0.isFinite }
        }
        if sessionData.sparcHistory.isEmpty {
            sessionData.sparcHistory = motionService.sparcHistoryArray.filter { $0.isFinite }
        }

        print("🎈 [BalloonPop] Final stats - Score: \(sessionData.score), Reps: \(sessionData.reps), MaxROM: \(String(format: "%.1f", sessionData.maxROM))°, SPARC avg: \(String(format: "%.1f", sessionData.sparcScore))")

        motionService.stopSession()
        self.sessionData = sessionData
        let userInfo = motionService.buildSessionNotificationPayload(from: sessionData)
        NotificationCenter.default.post(name: NSNotification.Name("BalloonPopGameEnded"), object: nil, userInfo: userInfo)
        // Use NavigationCoordinator for consistent routing instead of local fullScreenCover
    // Navigation will be handled by the CleanGameHostView via posted notification
    }
    
    private func cleanupGame() {
        gameTimer?.invalidate()
        balloonSpawnTimer?.invalidate()
        motionService.stopSession()
    }
}

// MARK: - Game Components
struct Balloon: Identifiable {
    let id: UUID
    var position: CGPoint
    let color: Color
    let size: CGFloat
    let spawnTime: TimeInterval = Date().timeIntervalSince1970
}

struct PopEffect: Identifiable {
    let id: UUID
    let position: CGPoint
    let color: Color
    let createdAt = Date()
}

struct BalloonView: View {
    let balloon: Balloon
    
    var body: some View {
        ZStack {
            // Balloon string
            Rectangle()
                .fill(Color.gray.opacity(0.8))
                .frame(width: 2, height: 30)
                .position(x: balloon.position.x, y: balloon.position.y + balloon.size/2 + 15)
            
            // Balloon
            Circle()
                .fill(balloon.color)
                .frame(width: balloon.size, height: balloon.size)
                .overlay(
                    Circle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: balloon.size * 0.4, height: balloon.size * 0.4)
                        .offset(x: -balloon.size * 0.15, y: -balloon.size * 0.15)
                )
                .position(balloon.position)
        }
    }
}

struct PopEffectView: View {
    let effect: PopEffect
    @State private var scale: CGFloat = 1
    @State private var opacity: Double = 1
    
    var body: some View {
        Circle()
            .stroke(effect.color, lineWidth: 3)
            .frame(width: 50, height: 50)
            .scaleEffect(scale)
            .opacity(opacity)
            .position(effect.position)
            .onAppear {
                withAnimation(.easeOut(duration: 0.5)) {
                    scale = 3
                    opacity = 0
                }
            }
    }
}