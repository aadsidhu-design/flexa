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
            
            // Minimal UI — only altitude meter on the right edge
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VerticalAltitudeMeter(altitude: altitude, maxAltitude: maxAltitude)
                        .frame(width: 60, height: geometry.size.height * 0.3)
                        .padding(.trailing, 20)
                        .padding(.bottom, 50)
                }
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

        // Feed SPARC analyzer with the active wrist to capture smoothness without UI artifacts
        let activeSide = keypoints.phoneArm
        if let activeWrist = (activeSide == .left) ? keypoints.leftWrist : keypoints.rightWrist {
            let mapped = CoordinateMapper.mapVisionPointToScreen(activeWrist, cameraResolution: motionService.cameraResolution, previewSize: screenSize, isPortrait: true, flipY: false)
            let wristPos = SIMD3<Float>(Float(mapped.x), Float(mapped.y), 0)
            motionService.sparcService.addCameraMovement(position: wristPos, timestamp: currentTime)
        } else {
            // Fallback to whichever wrist is currently visible to keep data flowing
            if let left = keypoints.leftWrist {
                let mapped = CoordinateMapper.mapVisionPointToScreen(left, cameraResolution: motionService.cameraResolution, previewSize: screenSize, isPortrait: true, flipY: false)
                let leftPos = SIMD3<Float>(Float(mapped.x), Float(mapped.y), 0)
                motionService.sparcService.addCameraMovement(position: leftPos, timestamp: currentTime)
            } else if let right = keypoints.rightWrist {
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
        
        let activeSide = keypoints.phoneArm
        let activeWrist = (activeSide == .left) ? keypoints.leftWrist : keypoints.rightWrist
        
        // Use screen-space Y position (pixels) for more accurate distance tracking
        guard let wrist = activeWrist else { return }
    let mappedWrist = CoordinateMapper.mapVisionPointToScreen(wrist, cameraResolution: motionService.cameraResolution, previewSize: screenSize, isPortrait: true, flipY: false)
        let currentWristY = CGFloat(mappedWrist.y)
        
        // Smooth the position
        let alpha: CGFloat = 0.25
        let smoothY = alpha * currentWristY + (1 - alpha) * CGFloat(lastWristY)
        
        // Get current ROM
        var currentROM = motionService.currentROM
        if currentROM <= 0 {
            let rawArmpitROM = keypoints.getArmpitROM(side: activeSide)
            currentROM = motionService.validateAndNormalizeROM(rawArmpitROM)
        }
        
        // Process motion through CameraRepDetector
        let result = repDetector.processWallClimbersMotion(
            wristY: smoothY,
            rom: currentROM,
            threshold: climbThreshold,
            screenHeight: screenSize.height
        )
        
        // Check if rep was detected
        if result.repDetected {
            let minimumThreshold = motionService.getMinimumROMThreshold(for: .wallClimbers)
            
            if result.peakROM >= minimumThreshold {
                motionService.recordCameraRepCompletion(rom: result.peakROM)
                reps = motionService.currentReps
                
                // Update game metrics
                altitude = min(maxAltitude, altitude + Double(result.distanceTraveled) * 2.5)  // Scale distance to meters
                score += Int(result.distanceTraveled)
                
                FlexaLog.game.info("🧗 [WallClimbers] ✅ Rep #\(reps) completed! ROM: \(String(format: "%.1f", result.peakROM))°, Distance: \(String(format: "%.0f", result.distanceTraveled))px, Altitude: \(Int(altitude))m")
                
                // Haptic feedback
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
        NavigationCoordinator.shared.showAnalyzing(sessionData: sessionData)
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
        
        VStack(spacing: 8) {
            // Current altitude display
            Text("\(Int(altitude))m")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.blue.opacity(0.8))
                )
            
            // Meter bar - taller and more prominent
            ZStack(alignment: .bottom) {
                // Background with gradient border
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.5), lineWidth: 2)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.4))
                    )
                    .frame(width: 40, height: 250)
                
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
                    .frame(width: 36, height: max(4, progress * 246))
                    .animation(.easeInOut(duration: 0.3), value: progress)
            }
            
            // Goal display
            Text("Goal: \(Int(maxAltitude))m")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white.opacity(0.9))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.6))
                )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.7))
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        )
    }
}

#Preview {
    WallClimbersGameView()
        .environmentObject(SimpleMotionService.shared)
}
