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
    @State private var lastElbowAngle: Double = 90
    @State private var screenSize: CGSize = UIScreen.main.bounds.size
    
    private let gameDuration: TimeInterval = 60 // 1 minute
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
                    // SINGLE PIN visualization - cyan color for visibility
                    ZStack {
                        // Pin tip (sharp point) - THE POPPING POINT directly at wrist position
                        Path { p in
                            let x = activePosition.x
                            let y = activePosition.y
                            p.move(to: CGPoint(x: x, y: y - 10))  // Top point
                            p.addLine(to: CGPoint(x: x - 8, y: y + 10))  // Bottom left
                            p.addLine(to: CGPoint(x: x + 8, y: y + 10))  // Bottom right
                            p.closeSubpath()
                        }
                        .fill(Color.cyan)
                        .shadow(color: Color.cyan.opacity(0.6), radius: 8)
                        
                        // Pin shaft (above the tip)
                        Rectangle()
                            .fill(LinearGradient(
                                gradient: Gradient(colors: [Color.cyan.opacity(0.7), Color.cyan]),
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                            .frame(width: 5, height: 25)
                            .position(x: activePosition.x, y: activePosition.y - 22)
                        
                        // Pin head (small circle at top)
                        Circle()
                            .fill(Color.cyan)
                            .frame(width: 14, height: 14)
                            .position(x: activePosition.x, y: activePosition.y - 35)
                            .shadow(color: Color.cyan.opacity(0.6), radius: 6)
                    }
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
            screenSize = geometry.size
            FlexaLog.game.info("🔍 [BalloonPop] onAppear called - setting up game")
            setupGame()
        }
        }
        .onDisappear {
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
    lastElbowAngle = 90
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
            // NO POSE DATA - hide pins
            leftHandPosition = .zero
            rightHandPosition = .zero
            return 
        }
        
        // Update hand positions from VisionPoseProvider with DIRECT mapping (minimal smoothing)
        if let leftWrist = keypoints.leftWrist {
            let mapped = CoordinateMapper.mapVisionPointToScreen(leftWrist, previewSize: screenSize)
            
            // DETAILED COORDINATE LOGGING
            print("📍 [BalloonPop-COORDS] LEFT RAW Vision: x=\(String(format: "%.4f", leftWrist.x)), y=\(String(format: "%.4f", leftWrist.y))")
            print("📍 [BalloonPop-COORDS] LEFT MAPPED Screen: x=\(String(format: "%.1f", mapped.x)), y=\(String(format: "%.1f", mapped.y)) (preview: \(screenSize.width)×\(screenSize.height))")
            
            // If position is zero (initial), seed it to mapped to avoid large jump
            if leftHandPosition == .zero { 
                leftHandPosition = mapped
                print("📍 [BalloonPop-COORDS] LEFT initial position set to: \(mapped)")
            } else {
                // VERY LIGHT smoothing for maximum responsiveness - pin sticks to wrist
                let alpha: CGFloat = 0.75 // Higher alpha = more responsive, sticks better
                leftHandPosition = CGPoint(
                    x: leftHandPosition.x * (1 - alpha) + mapped.x * alpha,
                    y: leftHandPosition.y * (1 - alpha) + mapped.y * alpha
                )
            }
            
            print("📍 [BalloonPop-COORDS] LEFT final pin position: x=\(String(format: "%.1f", leftHandPosition.x)), y=\(String(format: "%.1f", leftHandPosition.y))")

            // Feed SPARC with mapped preview coordinates for consistent smoothness analysis
            motionService.sparcService.addVisionMovement(timestamp: Date().timeIntervalSince1970, position: mapped)
        } else {
            leftHandPosition = .zero
        }
        
        if let rightWrist = keypoints.rightWrist {
            let mapped = CoordinateMapper.mapVisionPointToScreen(rightWrist, previewSize: screenSize)
            
            // DETAILED COORDINATE LOGGING
            print("📍 [BalloonPop-COORDS] RIGHT RAW Vision: x=\(String(format: "%.4f", rightWrist.x)), y=\(String(format: "%.4f", rightWrist.y))")
            print("📍 [BalloonPop-COORDS] RIGHT MAPPED Screen: x=\(String(format: "%.1f", mapped.x)), y=\(String(format: "%.1f", mapped.y))")
            
            if rightHandPosition == .zero { 
                rightHandPosition = mapped
                print("📍 [BalloonPop-COORDS] RIGHT initial position set to: \(mapped)")
            } else {
                let alpha: CGFloat = 0.75
                rightHandPosition = CGPoint(
                    x: rightHandPosition.x * (1 - alpha) + mapped.x * alpha,
                    y: rightHandPosition.y * (1 - alpha) + mapped.y * alpha
                )
            }
            
            print("📍 [BalloonPop-COORDS] RIGHT final pin position: x=\(String(format: "%.1f", rightHandPosition.x)), y=\(String(format: "%.1f", rightHandPosition.y))")

            motionService.sparcService.addVisionMovement(timestamp: Date().timeIntervalSince1970, position: mapped)
        } else {
            rightHandPosition = .zero
        }
        
        // Determine active arm
        activeArm = keypoints.phoneArm
        
        print("📍 [BalloonPop-COORDS] Active arm: \(activeArm == .left ? "LEFT" : "RIGHT")")
        
        // Calculate elbow ROM for rep detection
        let currentElbowAngle = calculateCurrentElbowAngle(keypoints: keypoints)
        if currentElbowAngle > 0 {
            detectElbowExtensionRep(currentAngle: currentElbowAngle)
        }
    }
    
    private func calculateCurrentElbowAngle(keypoints: SimplifiedPoseKeypoints) -> Double {
        // Use the active arm for elbow angle calculation
        if activeArm == .left {
            return keypoints.getLeftElbowAngle() ?? 0
        } else {
            return keypoints.getRightElbowAngle() ?? 0
        }
    }
    
    private func detectElbowExtensionRep(currentAngle: Double) {
        // Detect elbow extension reps (overhead extensions)
        // Extension: angle increases (arm straightens)
        // Flexion: angle decreases (arm bends)
        
        // Use standardized ROM thresholds for consistent elbow angle detection
        let minimumThreshold = motionService.getMinimumROMThreshold(for: .balloonPop)
        let extensionThreshold: Double = 180 - minimumThreshold // Near full extension
        let flexionThreshold: Double = 90   // Bent elbow (physiological minimum)
        
        if !isInPosition && currentAngle > extensionThreshold {
            // Started extension
            isInPosition = true
        } else if isInPosition && currentAngle < flexionThreshold {
            // Completed one rep (extension -> flexion)
            // Update ROM using validated Vision pathway
            isInPosition = false
            
            // Calculate ROM for this rep using standardized validation
            let repROM = motionService.validateAndNormalizeROM(abs(lastElbowAngle - currentAngle))
            if repROM >= minimumThreshold {
                motionService.recordVisionRepCompletion(rom: repROM)
                reps = motionService.currentReps
                print("🎈 [BalloonPop] Rep completed! Total reps: \(reps), ROM: \(String(format: "%.1f", repROM))° (threshold: \(String(format: "%.1f", minimumThreshold))°)")
            }
        }
        
        lastElbowAngle = currentAngle
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
            let leftDist = sqrt(pow(balloon.position.x - leftHandPosition.x, 2) + 
                               pow(balloon.position.y - leftHandPosition.y, 2))
            let rightDist = sqrt(pow(balloon.position.x - rightHandPosition.x, 2) + 
                                pow(balloon.position.y - rightHandPosition.y, 2))
            
            let activeDist = (activeArm == .left) ? leftDist : rightDist
            let inactiveDist = (activeArm == .left) ? rightDist : leftDist
            
            print("🔍 [BalloonPop] Balloon at (\(balloon.position.x), \(balloon.position.y)) - Left dist: \(leftDist), Right dist: \(rightDist), Active dist: \(activeDist)")
            
            if activeDist < balloon.size * 0.6 || inactiveDist < balloon.size * 0.5 {
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
            overrideScore: score,
            overrideExerciseType: GameType.balloonPop.displayName
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
        NavigationCoordinator.shared.showAnalyzing(sessionData: sessionData)
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