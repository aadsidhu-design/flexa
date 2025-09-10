import SwiftUI
import AVFoundation

struct BalloonPopGameView: View {
    @EnvironmentObject var motionService: SimpleMotionService
    @Environment(\.firebaseService) var firebaseService
    @State private var score: Int = 0
    @State private var gameTime: TimeInterval = 0
    @State private var isGameActive = false
    @State private var gameTimer: Timer?
    @State private var showingAnalyzing = false
    @State private var showingResults = false
    @State private var sessionData: ExerciseSessionData?
    @State private var aiAnalysis: ExerciseAnalysis?
    @State private var reps: Int = 0
    @State private var isInPosition = false
    @State private var leftPinPosition: CGPoint = .zero
    @State private var rightPinPosition: CGPoint = .zero
    
    // Game state
    @State private var balloons: [Balloon] = []
    @State private var popEffects: [PopEffect] = []
    @State private var balloonSpawnTimer: Timer?
    @State private var lastSpawnTime: TimeInterval = 0
    @State private var lastElbowAngle: Double = 90
    
    private let gameDuration: TimeInterval = 45
    private let screenHeight = UIScreen.main.bounds.height
    private let screenWidth = UIScreen.main.bounds.width
    private let balloonSpawnInterval: TimeInterval = 1.5
    
    var body: some View {
        ZStack {
            // Live camera with skeleton overlay
            LiveCameraWithSkeletonView()
                .ignoresSafeArea()
                .environmentObject(motionService)
            
            // Balloons
            ForEach(balloons, id: \.id) { balloon in
                BalloonView(balloon: balloon)
            }
            
            // Pin indicators at wrists
            if isGameActive {
                // Left pin
                Image(systemName: "pin.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.red)
                    .rotationEffect(.degrees(-45))
                    .position(leftPinPosition)
                
                // Right pin
                Image(systemName: "pin.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.red)
                    .rotationEffect(.degrees(45))
                    .position(rightPinPosition)
            }
            
            // Pop effects
            ForEach(popEffects, id: \.id) { effect in
                PopEffectView(effect: effect)
            }
            
            // Camera obstruction overlay for camera game (front camera)
            if motionService.isCameraObstructed {
                CameraObstructionOverlay(
                    isObstructed: motionService.isCameraObstructed,
                    reason: motionService.cameraObstructionReason,
                    isBackCamera: false
                )
                .zIndex(1000)
            }
            
            // Score and Position Indicator (Top)
            VStack {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Text("Score: \(score)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        Text("Pops: \(reps)")
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(15)
                    Spacer()
                }
                .padding(.top, 60)
                
                // Position indicator
                if !isInPosition && !isGameActive {
                    Text("📐 Move back until your head is in the box")
                        .font(.headline)
                        .foregroundColor(.yellow)
                        .padding()
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(10)
                        .padding(.top, 20)
                }
                
                Spacer()
            }
            
            // Game Timer (Bottom Right)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    BalloonGameTimer(timeRemaining: gameDuration - gameTime)
                        .padding(.trailing, 20)
                        .padding(.bottom, 50)
                }
            }
            
            // Position guide box
            if !isInPosition && !isGameActive {
                Rectangle()
                    .stroke(Color.yellow, lineWidth: 3)
                    .frame(width: 200, height: 250)
                    .position(x: screenWidth/2, y: screenHeight * 0.4)
            }
        }
        .navigationTitle("Balloon Pop")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            setupGame()
        }
        .onDisappear {
            print("🚨 [Game] Balloon Pop view disappeared - stopping session")
            motionService.stopSession()
            cleanupGame()
        }
        .fullScreenCover(isPresented: $showingAnalyzing) {
            if let data = sessionData {
                AnalyzingView(sessionData: data)
                    .environmentObject(NavigationCoordinator())
                    .environmentObject(GeminiService())
                    .environmentObject(ThemeManager())
                    .environmentObject(firebaseService ?? FirebaseService())
                    .environmentObject(motionService)
            }
        }
        .fullScreenCover(isPresented: $showingResults) {
            if let data = sessionData {
                UnifiedResultsView(sessionData: data, aiAnalysis: aiAnalysis, onRetry: {
                    showingResults = false
                    setupGame()
                }, onDone: {
                    showingResults = false
                }, preSurveyData: nil)
            }
        }
    }
    
    private func setupGame() {
        motionService.startSession(gameType: .balloonPop)
        // Camera-based game uses automatic pose detection
        resetGame()
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
    
    private func checkUserPosition() {
        guard let keypoints = motionService.poseKeypoints else {
            isInPosition = false
            return
        }
        
        // Check if head is in the target box area
        if let nose = keypoints.nose {
            let targetY = screenHeight * 0.4
            let distance = abs(nose.y * screenHeight - targetY)
            isInPosition = distance < 125 // Within box height
            
            if isInPosition && !isGameActive {
                // Auto-start when in position
                startGame()
            }
        }
    }
    
    private func startGame() {
        isGameActive = true
        gameTimer = Timer.scheduledTimer(withTimeInterval: 1.0/45.0, repeats: true) { _ in
            updateGame()
        }
        balloonSpawnTimer = Timer.scheduledTimer(withTimeInterval: balloonSpawnInterval, repeats: true) { _ in
            spawnBalloon()
        }
    }
    
    private func stopGame() {
        isGameActive = false
        gameTimer?.invalidate()
        gameTimer = nil
        balloonSpawnTimer?.invalidate()
        balloonSpawnTimer = nil
        endGame()
    }
    
    private func updateGame() {
        // Pause if camera is obstructed
        if motionService.isCameraObstructed {
            return // Game paused
        }
        
        gameTime += 0.1
        
        // Check for game end
        if gameTime >= gameDuration {
            stopGame()
            return
        }
        
        // Update pin positions and check collisions
        updatePinPositions()
        checkBalloonPops()
        updateBalloons()
        cleanupEffects()
    }
    
    private func updatePinPositions() {
        guard let keypoints = motionService.poseKeypoints else { return }
        
        // Update pin positions at wrists
        if let leftWrist = keypoints.leftWrist {
            leftPinPosition = CGPoint(
                x: (1.0 - leftWrist.y) * screenWidth,  // Rotated coordinates
                y: leftWrist.x * screenHeight
            )
        }
        
        if let rightWrist = keypoints.rightWrist {
            rightPinPosition = CGPoint(
                x: (1.0 - rightWrist.y) * screenWidth,  // Rotated coordinates
                y: rightWrist.x * screenHeight
            )
        }
        
        // Use Vision ROM from motion service (no custom calculation)
        let currentVisionROM = motionService.currentROM
        
        // Detect elbow extension rep using Vision ROM
        if currentVisionROM > 45 && lastElbowAngle < 30 {  // Vision ROM thresholds
            reps += 1
        }
        
        lastElbowAngle = currentVisionROM
    }
    
    // Calculate elbow angle function removed - using Vision ROM from motion service
    
    private func spawnBalloon() {
        let balloon = Balloon(
            id: UUID(),
            position: CGPoint(
                x: CGFloat.random(in: 50...screenWidth - 50),
                y: screenHeight * 0.2 // Spawn above head level
            ),
            color: [Color.red, .blue, .green, .yellow, .purple].randomElement()!,
            size: CGFloat.random(in: 40...60)
        )
        balloons.append(balloon)
    }
    
    private func checkBalloonPops() {
        var poppedBalloons: [UUID] = []
        
        for balloon in balloons {
            // Check collision with left pin
            let leftDist = sqrt(pow(balloon.position.x - leftPinPosition.x, 2) + 
                               pow(balloon.position.y - leftPinPosition.y, 2))
            // Check collision with right pin
            let rightDist = sqrt(pow(balloon.position.x - rightPinPosition.x, 2) + 
                                pow(balloon.position.y - rightPinPosition.y, 2))
            
            if leftDist < balloon.size || rightDist < balloon.size {
                poppedBalloons.append(balloon.id)
                score += 10
                
                // Create pop effect
                let effect = PopEffect(
                    id: UUID(),
                    position: balloon.position,
                    color: balloon.color
                )
                popEffects.append(effect)
                
                // Haptic feedback
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
            }
        }
        
        // Remove popped balloons
        balloons.removeAll { poppedBalloons.contains($0.id) }
    }
    
    private func updateBalloons() {
        // Slowly float balloons upward
        for i in balloons.indices {
            balloons[i].position.y -= 0.5
        }
        
        // Remove balloons that float off screen
        balloons.removeAll { $0.position.y < -50 }
    }
    
    private func cleanupEffects() {
        // Remove old pop effects after animation
        popEffects.removeAll { effect in
            Date().timeIntervalSince(effect.createdAt) > 1.0
        }
    }
    
    private func toggleGame() {
        if isGameActive {
            stopGame()
        } else {
            checkUserPosition()
        }
    }
    
    private func endGame() {
        isGameActive = false
        
        // Stop motion services properly
        motionService.stopSession()
        
        // Create session data using motion service ROM data (Vision-based)
        let sessionData = ExerciseSessionData(
            exerciseType: "Balloon Pop",
            score: score,
            reps: reps,
            maxROM: motionService.maxROM,  // Use Vision ROM from motion service
            duration: gameTime,
            romHistory: motionService.romPerRep,  // Use motion service ROM per rep
            sparcHistory: motionService.sparcHistory  // Use Vision SPARC
        )
        
        self.sessionData = sessionData
        showingAnalyzing = true
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

struct BalloonGameTimer: View {
    let timeRemaining: TimeInterval
    
    var body: some View {
        VStack {
            Text("\(Int(timeRemaining))s")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
        .padding()
        .background(Color.black.opacity(0.7))
        .cornerRadius(15)
    }
}
