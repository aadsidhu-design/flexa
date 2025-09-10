import SwiftUI
import AVFoundation

struct WallClimbersGameView: View {
    @EnvironmentObject var motionService: SimpleMotionService
    @Environment(\.firebaseService) var firebaseService
    @State private var score: Int = 0
    @State private var altitude: Double = 0
    @State private var gameTime: TimeInterval = 0
    @State private var isGameActive = false
    @State private var gameTimer: Timer?
    @State private var lastWristY: Double = 0.5 // Normalized position
    @State private var climbingPhase: ClimbingPhase = .waitingToStart
    @State private var romHistory: [Double] = []
    @State private var sparcHistory: [Double] = []
    @State private var showingAnalyzing = false
    @State private var showingResults = false
    @State private var sessionData: ExerciseSessionData?
    @State private var aiAnalysis: ExerciseAnalysis?
    @State private var reps: Int = 0
    @State private var maxROM: Double = 0
    @State private var currentRepStartY: Double = 0
    @State private var currentRepMaxY: Double = 0
    
    // Game constants
    private let maxAltitude: Double = 1000
    private let gameDuration: TimeInterval = 90
    private let climbThreshold: Double = 0.1 // Minimum upward movement to count
    
    enum ClimbingPhase {
        case waitingToStart
        case goingUp
        case goingDown
    }
    
    var body: some View {
        ZStack {
            // Live camera with skeleton overlay
            LiveCameraWithSkeletonView()
                .ignoresSafeArea()
                .environmentObject(motionService)
            
            // Score and Reps Display (Top Center)
            VStack {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Text("Altitude: \(Int(altitude))m")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        Text("Climbs: \(reps)")
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(15)
                    Spacer()
                }
                .padding(.top, 60)
                Spacer()
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
            
            // Altitude Meter (Right Side)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    AltitudeMeter(altitude: altitude, maxAltitude: maxAltitude)
                        .padding(.trailing, 20)
                }
                Spacer()
            }
            
            // Game Timer (Bottom Left)
            VStack {
                Spacer()
                HStack {
                    GameTimer(timeRemaining: gameDuration - gameTime)
                        .padding(.leading, 20)
                        .padding(.bottom, 50)
                    Spacer()
                }
            }
            
            // Instructions overlay
            if !isGameActive {
                VStack {
                    Spacer()
                    Text("🧗 Starting in 1s...")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(15)
                    Text("Climb the wall with your hands!")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(15)
                        .padding(.bottom, 100)
                }
            }
        }
        .navigationTitle("Wall Climbers")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            setupGame()
        }
        .onDisappear {
            print("🚨 [Game] Wall Climbers view disappeared - stopping session")
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
        motionService.startSession(gameType: .wallClimbers)
        // Camera-based game uses automatic pose detection
        resetGame()
        
        // Auto-start after 1 second delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            startGame()
        }
    }
    
    private func resetGame() {
        score = 0
        altitude = 0
        gameTime = 0
        romHistory = []
        lastWristY = 0
        climbingPhase = .waitingToStart
        currentRepStartY = 0
        currentRepMaxY = 0
        reps = 0
        maxROM = 0
    }
    
    private func startGame() {
        isGameActive = true
        gameTimer = Timer.scheduledTimer(withTimeInterval: 1.0/45.0, repeats: true) { _ in
            updateGame()
        }
    }
    
    private func stopGame() {
        isGameActive = false
        gameTimer?.invalidate()
        gameTimer = nil
        endGame()
    }
    
    private func updateGame() {
        // Pause if camera is obstructed
        if motionService.isCameraObstructed {
            return // Game paused
        }
        
        gameTime += 0.1
        
        // Check for game end
        if gameTime >= gameDuration || altitude >= maxAltitude {
            stopGame()
            return
        }
        
        // Update climbing based on wrist position
        updateClimbing()
    }
    
    private func updateClimbing() {
        guard let keypoints = motionService.poseKeypoints else { return }
        
        // Get wrist positions (average of both for climbing)
        let leftWrist = keypoints.leftWrist
        let rightWrist = keypoints.rightWrist
        
        // Calculate average wrist Y position (normalized 0-1)
        var currentWristY: Double = lastWristY
        if let left = leftWrist, let right = rightWrist {
            currentWristY = Double((left.y + right.y) / 2)
        } else if let left = leftWrist {
            currentWristY = Double(left.y)
        } else if let right = rightWrist {
            currentWristY = Double(right.y)
        }
        
        // Detect climbing phases (lower Y = hands up)
        let deltaY = lastWristY - currentWristY
        
        switch climbingPhase {
        case .waitingToStart:
            if deltaY > climbThreshold {
                // Started going up
                climbingPhase = .goingUp
                currentRepStartY = currentWristY
                currentRepMaxY = currentWristY
            }
            
        case .goingUp:
            if currentWristY < currentRepMaxY {
                currentRepMaxY = currentWristY // Track highest point
            }
            
            if deltaY < -climbThreshold {
                // Started going down - complete the climb
                climbingPhase = .goingDown
                
                // Calculate climb distance and update altitude
                let climbDistance = (currentRepStartY - currentRepMaxY) * 1000
                if climbDistance > 50 { // Minimum distance to count
                    altitude = min(maxAltitude, altitude + climbDistance)
                    score += Int(climbDistance)
                    reps += 1
                    
                    // Track ROM for this rep
                    let rom = motionService.currentROM
                    romHistory.append(rom)
                    maxROM = max(maxROM, rom)
                    
                    // Track SPARC
                    let sparc = motionService.getCurrentSPARC()
                    sparcHistory.append(sparc)
                }
            }
            
        case .goingDown:
            if deltaY > climbThreshold {
                // Started going up again
                climbingPhase = .goingUp
                currentRepStartY = currentWristY
                currentRepMaxY = currentWristY
            } else if abs(deltaY) < 0.01 {
                // Hands at rest
                climbingPhase = .waitingToStart
            }
        }
        
        lastWristY = currentWristY
    }
    
    private func endGame() {
        isGameActive = false
        
        // Stop motion services properly
        motionService.stopSession()
        
        // Create session data
        let sessionData = ExerciseSessionData(
            exerciseType: "Wall Climbers",
            score: Int(altitude),
            reps: reps,
            maxROM: maxROM,
            duration: gameTime,
            romHistory: romHistory,
            sparcHistory: sparcHistory
        )
        
        self.sessionData = sessionData
        showingAnalyzing = true
    }
    
    private func cleanupGame() {
        gameTimer?.invalidate()
        motionService.stopSession()
    }
}

struct ScoreDisplay: View {
    let score: Int
    
    var body: some View {
        VStack(spacing: 4) {
            Text("SCORE")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white.opacity(0.8))
            
            Text("\(score)")
                .font(.largeTitle)
                .fontWeight(.heavy)
                .foregroundColor(.yellow)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(Color.black.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.yellow.opacity(0.3), lineWidth: 1))
        )
    }
}

struct AltitudeMeter: View {
    let altitude: Double
    let maxAltitude: Double
    
    private var progress: Double {
        min(altitude / maxAltitude, 1.0)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            Text("ALTITUDE")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .rotationEffect(.degrees(-90))
            
            ZStack(alignment: .bottom) {
                // Background bar
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.4))
                    .frame(width: 30, height: 200)
                
                // Progress bar
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [.blue, .cyan, .green, .yellow, .red]),
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 30, height: 200 * progress)
                
                // Altitude text
                VStack {
                    Spacer()
                    Text("\(Int(altitude))m")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .rotationEffect(.degrees(-90))
                    Spacer()
                }
            }
            
            Text("\(Int(maxAltitude))m")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white.opacity(0.7))
                .rotationEffect(.degrees(-90))
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(Color.black.opacity(0.6))
        )
    }
}

struct GameTimer: View {
    let timeRemaining: TimeInterval
    private var minutes: Int {
        Int(timeRemaining) / 60
    }
    
    private var seconds: Int {
        Int(timeRemaining) % 60
    }
    
    var body: some View {
        VStack(spacing: 4) {
            Text("TIME")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white.opacity(0.8))
            
            Text(String(format: "%d:%02d", minutes, seconds))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(timeRemaining < 10 ? .red : .white)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(Color.black.opacity(0.6))
                .overlay(Circle().stroke(timeRemaining < 10 ? Color.red.opacity(0.5) : Color.clear, lineWidth: 2))
        )
    }
}

struct GameResultsView: View {
    let sessionData: ExerciseSessionData
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Text("🧗‍♀️ Climbing Complete!")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            VStack(spacing: 16) {
                ResultRow(label: "Duration", value: "\(Int(sessionData.duration / 60)) minutes")
                ResultRow(label: "Max ROM", value: "\(Int(sessionData.maxROM))°")
                ResultRow(label: "Average ROM", value: "\(Int(sessionData.averageROM))°")
                ResultRow(label: "Estimated Reps", value: "\(sessionData.reps)")
            }
            
            Button("Continue") {
                onDismiss()
            }
            .font(.headline)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.green)
            .cornerRadius(12)
        }
        .padding()
    }
}

struct ResultRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .fontWeight(.medium)
            Spacer()
            Text(value)
                .fontWeight(.bold)
                .foregroundColor(.blue)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

#Preview {
    WallClimbersGameView()
        .environmentObject(SimpleMotionService.shared)
}
