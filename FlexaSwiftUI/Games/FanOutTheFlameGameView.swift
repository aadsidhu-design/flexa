import SwiftUI
import CoreMotion
import AVFoundation

struct FanOutTheFlameGameView: View {
    @EnvironmentObject var motionService: SimpleMotionService
    @Environment(\.backendService) var backendService
    @StateObject private var calibrationCheck = CalibrationCheckService.shared
    @State private var score: Int = 0
    @State private var gameTime: TimeInterval = 0
    @State private var isGameActive = false
    @State private var gameTimer: Timer?
    @State private var reps: Int = 0
    
    // Game state
    @State private var flameIntensity: Double = 1.0
    @State private var fanMotions: Int = 0
    @State private var lastFanTime: TimeInterval = 0
    @State private var isFlameOut = false
    @State private var fanAngle: Double = 0
    @State private var observedMotionServiceReps: Int = 0
    @State private var hasInitializedGame = false
    
    // Fan animation state (ROM tracking now handled by Universal3D engine)
    
    private let maxGameDuration: TimeInterval = 120
    private let flameDecayRate: Double = 0.02 // Smaller decay so it takes more reps to extinguish the flame
    
    var body: some View {
        // Check calibration status first
        if !calibrationCheck.isCalibrated {
            CalibrationRequiredView()
                .environmentObject(calibrationCheck)
        } else {
            ZStack {
                // Dark background
                Color.black.ignoresSafeArea()
            
            VStack(spacing: 40) {
                // Remove score display from top
                
                Spacer()
                
                // Candle with Flame properly positioned
                ZStack {
                    VStack(spacing: 0) {
                        // Flame on top of wick (lowered position)
                        FlameView(intensity: flameIntensity, isOut: isFlameOut)
                            .frame(height: 80)  // Reduced height
                            .offset(y: 30)  // Moved down further
                        
                        // Candle body with wick (moved down)
                        ZStack(alignment: .top) {
                            // Candle body
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(red: 0.9, green: 0.85, blue: 0.7))
                                .frame(width: 80, height: 160)  // Shorter candle
                                .offset(y: 20)  // Moved down
                            
                            // Wick at top of candle
                            Rectangle()
                                .fill(Color.black)
                                .frame(width: 4, height: 16)  // Shorter wick
                                .offset(y: 10)  // Adjusted position
                        }
                    }
                }
                .frame(height: 300)
                
                Spacer()
                
                // No instructions during gameplay
                
                Spacer()
                
                // Hand fanning animation based on user movement
                HandFanningView(fanAngle: fanAngle, isActive: isGameActive)
                    .offset(y: -40)
                    .padding(.bottom, 40)
            }
        }
        .onAppear {
            guard !hasInitializedGame else {
                FlexaLog.motion.info("🔁 [FanOutTheFlame] View reappeared - skipping automatic setup (already initialized)")
                return
            }
            hasInitializedGame = true
            setupGame()
        }
        .onDisappear {
            FlexaLog.motion.info("👋 [FanOutTheFlame] View disappearing - forcing cleanup")
            // Explicitly stop game first
            if isGameActive {
                FlexaLog.motion.info("⚠️ [FanOutTheFlame] Game still active in onDisappear - forcing stop")
                isGameActive = false
                gameTimer?.invalidate()
                gameTimer = nil
            }
            cleanupGame()
        }
        .onReceive(motionService.$currentReps) { newReps in
            handleMotionServiceRepChange(newReps)
        }
        .toolbar(.hidden, for: .navigationBar)
        }
    }
    
    private func setupGame() {
        // Prevent double-starts if session already active
        guard !motionService.isSessionActive else {
            FlexaLog.motion.warning("⏸️ [FanOutTheFlame] setupGame skipped — motionService already active")
            return
        }
        // Use unified session start for handheld game
        motionService.startGameSession(gameType: .fanOutFlame)
        resetGame()
        // Auto-start the game
        startGame()
    }
    
    private func resetGame() {
        score = 0
        gameTime = 0
        flameIntensity = 1.0
        fanMotions = 0
        lastFanTime = 0
        isFlameOut = false
        reps = 0
        observedMotionServiceReps = 0
    }
    
    
    private func updateFanMotion() {
        // Use ARKit position for fan animation (ROM calculation now handled by Universal3D engine)
        guard let currentTransform = motionService.universal3DEngine.currentTransform else { return }
        
        // Extract position for animation feedback only
        let currentPosition = SIMD3<Double>(
            Double(currentTransform.columns.3.x),
            Double(currentTransform.columns.3.y),
            Double(currentTransform.columns.3.z)
        )
        
        let currentTime = CACurrentMediaTime()
        
        // Use ARKit position changes for fan animation visualization
        let positionChange = sqrt(pow(currentPosition.x, 2) + pow(currentPosition.y, 2) + pow(currentPosition.z, 2))
        
        // More responsive fan visualization based on ARKit movement
        let baseAngle = sin(currentTime * 4.0) * 20.0  // Faster oscillation, smaller base angle
        let motionScale = min(abs(positionChange) * 10.0, 1.0)  // Scale motion but cap it
        fanAngle = baseAngle * (1.0 + motionScale)  // More responsive fan motion
        
        // Only update lastFanTime for visual feedback
        if positionChange > 0.05 && (currentTime - lastFanTime) > 0.15 {
            lastFanTime = currentTime
        }
    }
    
    private func handleMotionServiceRepChange(_ reps: Int) {
        // CRITICAL: Only process reps when game is actually active
        // This prevents SPARC/rep updates during Analyzing/Results screens
        guard isGameActive else {
            FlexaLog.motion.debug("🚫 [FanOutTheFlame] Ignoring rep update (\(reps)) - game not active (isGameActive=false)")
            return
        }
        
        // Double-check game hasn't ended
        guard gameTimer != nil else {
            FlexaLog.motion.debug("🚫 [FanOutTheFlame] Ignoring rep update (\(reps)) - timer is nil (game ended)")
            return
        }
        
        // Check if reps actually increased (new rep detected)
        // Fan the Flame now uses IMU direction-change detection via FanTheFlameRepDetector
        // Each swing LEFT = 1 rep, each swing RIGHT = 1 rep
        if reps > observedMotionServiceReps {
            let newReps = reps - observedMotionServiceReps
            FlexaLog.motion.debug("� [FanOutTheFlame] Direction-change reps: \(observedMotionServiceReps) -> \(reps) (+\(newReps))")
            
            // Perform fan motion for each new rep (each direction change)
            for _ in 0..<newReps {
                performRepDetectedFanMotion()
            }
            
            observedMotionServiceReps = reps
        }
    }

    private func performRepDetectedFanMotion() {
        fanMotions += 1
        
        // Reduce flame intensity only when a rep is detected
        // Rep = direction change detected by IMU gyroscope (left swing OR right swing)
        flameIntensity = max(0, flameIntensity - flameDecayRate)
        
        // Sync reps with motion service
        reps = motionService.currentReps
        
        // Check if flame is out
        if flameIntensity <= 0 {
            isFlameOut = true
            stopGame()
        }
        
        // Haptic feedback for successful rep
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        print("🔥 [FanFlame] Direction-change rep! Reps: \(reps), Fan motions: \(fanMotions), Flame intensity: \(String(format: "%.3f", flameIntensity))")
    }
    
    private func toggleGame() {
        if isGameActive {
            stopGame()
        } else {
            startGame()
        }
    }
    
    private func startGame() {
        guard !isGameActive else {
            FlexaLog.motion.debug("⏸️ [FanOutTheFlame] startGame ignored — already active")
            return
        }
        FlexaLog.motion.info("🎮 [FanOutTheFlame] Starting game - motionService active: \(motionService.isSessionActive), ARKit running: \(motionService.isARKitRunning)")
        isGameActive = true
        // More responsive update cadence
        gameTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { _ in
            updateGame()
        }
        FlexaLog.motion.info("🎮 [FanOutTheFlame] Game started successfully with timer at 0.06s intervals")
    }
    
    private func stopGame() {
        FlexaLog.motion.info("🎮 [FanOutTheFlame] Stopping game - reps: \(reps), gameTime: \(gameTime)s")
        
        // CRITICAL: Set isGameActive to false FIRST to prevent any new updates
        isGameActive = false
        
        // Invalidate and nil out the timer to stop all updates
        gameTimer?.invalidate()
        gameTimer = nil
        
        FlexaLog.motion.info("🎮 [FanOutTheFlame] Game stopped and timer invalidated")
        endGame()
    }
    
    private func updateGame() {
        // CRITICAL: Stop processing if game is not active
        guard isGameActive else {
            FlexaLog.motion.debug("🚫 [FanOutTheFlame] updateGame() called but game not active - stopping")
            gameTimer?.invalidate()
            gameTimer = nil
            return
        }
        
        gameTime += 0.1
        
        // Update fan motion from sensors
        updateFanMotion()
        
        // Check max game duration
        if gameTime >= maxGameDuration {
            stopGame()
            return
        }
        
        // NO automatic flame regeneration or decay - flame only changes when reps are detected
        // This ensures the flame stays stable when the arm is still
    }
    
    private func endGame() {
        isGameActive = false
        gameTimer?.invalidate()
        gameTimer = nil
        
        // Use motion service's getFullSessionData for consistent data
        let data = motionService.getFullSessionData()
        
        print("🔥 [FanFlame] EndGame - MotionService Data:")
        print("  Score: \(data.score), Reps: \(data.reps), MaxROM: \(data.maxROM)°")
        print("  RomHistory: \(data.romHistory.count) values, SparcHistory: \(data.sparcHistory.count) values")
        print("  SPARC Score: \(data.sparcScore)")
        
        // Stop motion service properly
        motionService.stopSession()
        
        // Post a unified game-ended notification for host to handle navigation
        let userInfo = motionService.buildSessionNotificationPayload(from: data)

        print("📣 [FanFlame] Posting game end with payload → score=\(data.score), reps=\(data.reps), maxROM=\(String(format: "%.1f", data.maxROM))°, SPARC=\(String(format: "%.2f", data.sparcScore))")
        NotificationCenter.default.post(name: NSNotification.Name("FanFlameGameEnded"), object: nil, userInfo: userInfo)
    }

    private func cleanupGame() {
        FlexaLog.motion.info("🧹 [FanOutTheFlame] Cleaning up game (onDisappear called)")
        
        // CRITICAL: Set isGameActive to false to stop all processing
        isGameActive = false
        
        // Stop and cleanup the game timer
        gameTimer?.invalidate()
        gameTimer = nil
        
        // Stop motion service to prevent SPARC updates during Analyzing/Results
        motionService.stopSession()
        
        FlexaLog.motion.info("🧹 [FanOutTheFlame] Cleanup complete - timer stopped, motion service stopped")
    }
}

// MARK: - View Components
struct FlameView: View {
    let intensity: Double
    let isOut: Bool
    
    var body: some View {
        ZStack {
            if isOut {
                // Smoke effect when flame is out
                VStack {
                    Text("💨")
                        .font(.system(size: 60))
                        .opacity(0.6)
                    
                    Text("Flame Extinguished!")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.gray)
                }
            } else {
                // Animated flame
                VStack(spacing: -20) {
                    // Main flame body
                    ZStack {
                        // Outer flame
                        Ellipse()
                            .fill(
                                RadialGradient(
                                    gradient: Gradient(colors: [
                                        Color.yellow.opacity(intensity * 0.9),
                                        Color.orange.opacity(intensity * 0.7),
                                        Color.red.opacity(intensity * 0.5)
                                    ]),
                                    center: .bottom,
                                    startRadius: 10,
                                    endRadius: 100
                                )
                            )
                            .frame(width: 120 * intensity, height: 200 * intensity)
                        
                        // Inner flame
                        Ellipse()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.white.opacity(intensity * 0.8),
                                        Color.yellow.opacity(intensity * 0.6),
                                        Color.orange.opacity(intensity * 0.4)
                                    ]),
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(width: 60 * intensity, height: 120 * intensity)
                    }
                    .scaleEffect(x: 1.0 + sin(Date().timeIntervalSince1970 * 6) * 0.05 * intensity,
                               y: 1.0 + sin(Date().timeIntervalSince1970 * 8) * 0.03 * intensity)
                    .animation(.easeInOut(duration: 0.2).repeatForever(autoreverses: true), value: intensity)
                    
                    // Flame base
                    Rectangle()
                        .fill(Color.brown)
                        .frame(width: 20, height: 40)
                        .cornerRadius(10)
                }
            }
        }
    }
}

struct FlameScoreDisplay: View {
    let score: Int
    let fanMotions: Int
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text("SCORE")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white.opacity(0.8))
                    
                    Text("\(score)")
                        .font(.title)
                        .fontWeight(.heavy)
                        .foregroundColor(.orange)
                }
                
                VStack(spacing: 4) {
                    Text("FAN MOTIONS")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white.opacity(0.8))
                    
                    Text("\(fanMotions)")
                        .font(.title)
                        .fontWeight(.heavy)
                        .foregroundColor(.yellow)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 15)
                .background(Color.black.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.3), lineWidth: 1))
        )
    }
}

// Hand fanning animation component
struct HandFanningView: View {
    let fanAngle: Double
    let isActive: Bool
    
    var body: some View {
        ZStack {
            // Hand emoji that moves left and right based on user movement
            Text("✋")
                .font(.system(size: 80))
                .offset(x: sin(fanAngle * 0.1) * 30) // Convert rotation to horizontal movement
                .animation(.easeInOut(duration: 0.3), value: fanAngle)
                .opacity(isActive ? 1.0 : 0.6)
            
            // Add wind effect lines when fanning
            if abs(fanAngle) > 5 {
                ForEach(0..<3) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.blue.opacity(0.3))
                        .frame(width: 20, height: 2)
                        .offset(x: 40 + Double(i) * 15, y: Double(i) * 8 - 8)
                        .animation(.easeInOut(duration: 0.2), value: fanAngle)
                }
            }
        }
        .frame(width: 150, height: 100)
    }
}

#Preview {
    FanOutTheFlameGameView()
        .environmentObject(SimpleMotionService.shared)
}
