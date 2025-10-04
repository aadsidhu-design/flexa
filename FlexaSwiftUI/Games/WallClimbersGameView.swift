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
    @State private var smoothedWristY: Double = 0.5
    @State private var climbingPhase: ClimbingPhase = .waitingToStart
    @State private var showingAnalyzing = false
    @State private var showingResults = false
    @State private var sessionData: ExerciseSessionData?
    @State private var reps: Int = 0
    @State private var currentRepStartY: Double = 0
    @State private var currentRepMaxY: Double = 0
    @State private var leftHandPosition: CGPoint = .zero
    @State private var rightHandPosition: CGPoint = .zero
    @State private var screenSize: CGSize = UIScreen.main.bounds.size
    
    // Game constants
    private let maxAltitude: Double = 1000
    private let climbThreshold: Double = 0.05  // More sensitive
    
    enum ClimbingPhase {
        case waitingToStart
        case goingUp
        case goingDown
    }
    
    var body: some View {
        GeometryReader { geometry in
        ZStack {
            CameraGameBackground()
                
            // Hand tracking circles with climbing indicators
            if isGameActive {
                // Left hand circle
                ZStack {
                    Circle()
                        .stroke(Color.red, lineWidth: 4)
                        .frame(width: 60, height: 60)
                        .position(leftHandPosition)
                        .opacity(0.8)
                    
                    // Climbing indicator
                    if climbingPhase == .goingUp {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(.green)
                            .font(.title2)
                            .position(leftHandPosition)
                    }
                }
                
                // Right hand circle
                ZStack {
                    Circle()
                        .stroke(Color.blue, lineWidth: 4)
                        .frame(width: 60, height: 60)
                        .position(rightHandPosition)
                        .opacity(0.8)
                    
                    // Climbing indicator
                    if climbingPhase == .goingUp {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(.green)
                            .font(.title2)
                            .position(rightHandPosition)
                    }
                }
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
            
            // Minimal UI - ONLY altitude meter (no timer, cleaner display)
            VStack {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Text("\(Int(altitude))m")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        Text("Reps: \(reps)")
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding()
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(15)
                    Spacer()
                }
                .padding(.top, 60)
                
                Spacer()
                
                // Vertical altitude meter aligned to the right edge for better visibility
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
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            FlexaLog.game.info("🔍 [WallClimbers] onAppear called - setting up game")
            setupGame()
        }
        .onDisappear {
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
        climbingPhase = .waitingToStart
        currentRepStartY = 0
        currentRepMaxY = 0
        reps = 0
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
        
        // Update hand positions from VisionPoseProvider (480x640 coordinates -> screen)
        if let leftWrist = keypoints.leftWrist {
            let mapped = CoordinateMapper.mapVisionPointToScreen(leftWrist, previewSize: screenSize)
            print("[WallClimbers][DEBUG] leftWrist raw=\(leftWrist) mapped=\(mapped) preview=\(screenSize)")
            if leftHandPosition == .zero { leftHandPosition = mapped }
            let alpha: CGFloat = 0.25
            leftHandPosition = CGPoint(x: leftHandPosition.x * (1 - alpha) + mapped.x * alpha,
                                       y: leftHandPosition.y * (1 - alpha) + mapped.y * alpha)

            motionService.sparcService.addVisionMovement(timestamp: Date().timeIntervalSince1970, position: mapped)
        }
        
        if let rightWrist = keypoints.rightWrist {
            let mapped = CoordinateMapper.mapVisionPointToScreen(rightWrist, previewSize: screenSize)
            print("[WallClimbers][DEBUG] rightWrist raw=\(rightWrist) mapped=\(mapped) preview=\(screenSize)")
            if rightHandPosition == .zero { rightHandPosition = mapped }
            let alpha: CGFloat = 0.25
            rightHandPosition = CGPoint(x: rightHandPosition.x * (1 - alpha) + mapped.x * alpha,
                                        y: rightHandPosition.y * (1 - alpha) + mapped.y * alpha)

            motionService.sparcService.addVisionMovement(timestamp: Date().timeIntervalSince1970, position: mapped)
        }
    }
    
    private func updateClimbing() {
        guard let keypoints = motionService.poseKeypoints else { 
                return 
        }
        
        let activeSide = keypoints.phoneArm
        let activeWrist = (activeSide == .left) ? keypoints.leftWrist : keypoints.rightWrist
        let inactiveWrist = (activeSide == .left) ? keypoints.rightWrist : keypoints.leftWrist
        
        // Normalize Y coordinates to 0-1 range (640 height)
        func normY(_ p: CGPoint?) -> Double? { 
            guard let p = p else { return nil }
            return Double(max(0, min(1, p.y / 640.0)))
        }
        
        var currentWristY: Double = lastWristY
        if let a = normY(activeWrist), let b = normY(inactiveWrist) {
            currentWristY = a * 0.7 + b * 0.3
        } else if let a = normY(activeWrist) {
            currentWristY = a
        } else if let b = normY(inactiveWrist) {
            currentWristY = b
        }
        
        // Smooth noise
        let alpha = 0.2
        let smoothY = alpha * currentWristY + (1 - alpha) * lastWristY
        let deltaY = lastWristY - smoothY
        
        switch climbingPhase {
        case .waitingToStart:
            if deltaY > climbThreshold {
                climbingPhase = .goingUp
                currentRepStartY = smoothY
                currentRepMaxY = smoothY
            }
            
        case .goingUp:
            if smoothY < currentRepMaxY {
                currentRepMaxY = smoothY
            }
            
            if deltaY < -climbThreshold {
                climbingPhase = .goingDown
                
                let climbDistance = (currentRepStartY - currentRepMaxY) * 400  // Scale to pixels
                if climbDistance > 5 {
                    altitude = min(maxAltitude, altitude + climbDistance)
                    score += Int(climbDistance)
                    reps += 1
                    
                    // Calculate armpit ROM for this rep using standardized validation
                    let rawArmpitROM = keypoints.getArmpitROM(side: activeSide)
                    let validatedROM = motionService.validateAndNormalizeROM(rawArmpitROM)
                    let minimumThreshold = motionService.getMinimumROMThreshold(for: .wallClimbers)
                    
                    if validatedROM >= minimumThreshold {
                        motionService.recordVisionRepCompletion(rom: validatedROM)
                        reps = motionService.currentReps
                        // Add SPARC data based on wrist movement (Vision-based)
                        if let wrist = activeWrist {
                            motionService.sparcService.addVisionMovement(
                                timestamp: Date().timeIntervalSince1970,
                                position: wrist
                            )
                        }
                        
                        print("🧗 [WallClimbers] Climb completed! Reps: \(reps), ROM: \(String(format: "%.1f", validatedROM))° (threshold: \(String(format: "%.1f", minimumThreshold))°), Altitude: \(Int(altitude))m")
                    }
                }
            }
            
        case .goingDown:
            if deltaY > climbThreshold {
                climbingPhase = .goingUp
                currentRepStartY = smoothY
                currentRepMaxY = smoothY
            } else if abs(deltaY) < 0.01 {
                climbingPhase = .waitingToStart
            }
        }
        
        lastWristY = smoothY
    }
    
    private func endGame() {
        isGameActive = false
        gameTimer?.invalidate()
        
        let altitudeScore = Int(altitude)
        let snapshot = motionService.getFullSessionData(
            overrideScore: altitudeScore,
            overrideExerciseType: GameType.wallClimbers.displayName
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
