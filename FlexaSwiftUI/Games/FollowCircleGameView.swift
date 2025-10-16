import SwiftUI
import CoreMotion

struct FollowCircleGameView: View {
    @Binding var score: Int
    @Binding var reps: Int
    @Binding var rom: Double
    @Binding var isActive: Bool
    
    @StateObject private var motionService = SimpleMotionService.shared
    @StateObject private var calibrationCheck = CalibrationCheckService.shared
    @State private var showingResults = false
    @State private var showingAnalyzing = false
    @State private var gameTime: TimeInterval = 0
    @State private var gameTimer: Timer?
    @State private var sessionData: ExerciseSessionData?
    @State private var gameHasEnded: Bool = false
    
    // Game state
    @State private var isGameActive = false
    @State private var gameScore = 0
    @State private var lastTouchTime: Date = Date()
    @State private var isTouchingCircle = false
    @State private var consecutiveTouches = 0
    @State private var gameStartTime: Date = Date()
    @State private var gracePeriodEnded = false
    @State private var lastContactTime: Date = Date()
    @State private var offCircleStartTime: Date? = nil
    
    // Circle positions and properties
    @State private var userCirclePosition = CGPoint(x: 200, y: 400) // Green hollow cursor circle
    @State private var guideCirclePosition = CGPoint(x: 200, y: 400) // White solid moving circle
    @State private var guideCircleRadius: CGFloat = 40
    @State private var guideCircleSpeed: CGFloat = 1.0
    @State private var guideCircleAngle: Double = 0
    @State private var guideCircleCenter = CGPoint(x: 200, y: 400)
    @State private var guideCircleOrbitRadius: CGFloat = 80
    @State private var cursorRadius: CGFloat = 25 // Much bigger cursor
    
    // Movement-based cursor control
    @State private var cursorVelocity = CGPoint.zero
    @State private var lastAcceleration = CGPoint.zero
    @State private var screenSize = CGSize(width: 400, height: 800)
    @State private var arBaseline: SIMD3<Double>? = nil
    @State private var lastScreenPoint: CGPoint? = nil
    @State private var showRecalibrateMessage = false
    @State private var lastLoggedSecond: Int = -1
    @State private var hasLoggedBaselineCapture = false
    @State private var hasLoggedMissingTransform = false
    
    // Rep tracking now handled by Universal3D engine
    
    // Direct cursor control - no smoothing for perfect synchronization
    @State private var smoothedCursorPosition: CGPoint = CGPoint(x: 195, y: 422)
    private let cursorSmoothing: CGFloat = 1.0  // 1.0 = completely synchronous, no lag

    private let gracePeriodDuration: TimeInterval = 5.0  // 5 seconds to get ready
    private let offCircleGraceDuration: TimeInterval = 2.5
    
    var body: some View {
        if !calibrationCheck.isCalibrated {
            CalibrationRequiredView()
        } else {
            ZStack {
                // Background with subtle pattern
                Color.black.ignoresSafeArea()
                
                // Game scene
                FollowCircleGameScene(
                    userCirclePosition: $userCirclePosition,
                    guideCirclePosition: $guideCirclePosition,
                    guideCircleRadius: $guideCircleRadius,
                    isTouchingCircle: $isTouchingCircle,
                    cursorRadius: $cursorRadius
                )
                .ignoresSafeArea()
                .onAppear {
                    screenSize = UIScreen.main.bounds.size
                }
                .onTapGesture(count: 2) {
                    // Double tap to recalibrate center position
                    recalibrateCenter()
                }
                
                // UI Overlay - Only Score
                VStack {
                    // Score at top
                    HStack {
                        Spacer()
                        
                        Text("\(gameScore)")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(20)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    
                    // Grace period countdown
                    if !gracePeriodEnded {
                        let remainingTime = max(0, gracePeriodDuration - Date().timeIntervalSince(gameStartTime))
                        VStack(spacing: 8) {
                            Text("Get Ready!")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                            
                            Text("\(Int(ceil(remainingTime)))")
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundColor(.green)
                            
                            Text("Start moving to begin")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding()
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(20)
                        .transition(.scale.combined(with: .opacity))
                    }
                    
                    Spacer()
                    
                    // Recalibration message
                    if showRecalibrateMessage {
                        Text("Center Recalibrated!")
                            .font(.headline)
                            .foregroundColor(.green)
                            .padding()
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(10)
                            .transition(.opacity)
                    }
                    
                    Spacer()
                }
                
            }
            .onAppear {
                FlexaLog.game.info("🎯 [FollowCircle] View appeared — isGameActive=\(self.isGameActive, privacy: .public) showingAnalyzing=\(self.showingAnalyzing, privacy: .public) showingResults=\(self.showingResults, privacy: .public) gameHasEnded=\(self.gameHasEnded, privacy: .public)")
                if !isGameActive && !showingAnalyzing && !showingResults && !gameHasEnded {
                    FlexaLog.game.info("🎯 [FollowCircle] Preparing game setup — isActiveBinding=\(self.isActive, privacy: .public)")
                    setupGame()
                } else {
                    FlexaLog.game.debug("🎯 [FollowCircle] Skipping setup (isGameActive=\(self.isGameActive, privacy: .public), showingAnalyzing=\(self.showingAnalyzing, privacy: .public), showingResults=\(self.showingResults, privacy: .public), gameHasEnded=\(self.gameHasEnded, privacy: .public))")
                }
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("FollowCircleGameEnded"),
                    object: nil,
                    queue: .main
                ) { notification in
                    FlexaLog.game.info("📥 [FollowCircle] Received FollowCircleGameEnded notification — isActiveBinding=\(self.isActive, privacy: .public) gameHasEnded=\(self.gameHasEnded, privacy: .public)")
                    if let payload = notification.userInfo {
                        let keysDescription = payload.keys.map { "\($0)" }.joined(separator: ",")
                        FlexaLog.game.debug("📥 [FollowCircle] Notification payload keys=\(keysDescription, privacy: .public)")
                        if let providedSession = payload["exerciseSession"] as? ExerciseSessionData {
                            self.sessionData = providedSession
                            FlexaLog.game.debug("📥 [FollowCircle] Using provided ExerciseSessionData — reps=\(providedSession.reps, privacy: .public) duration=\(String(format: "%.1f", providedSession.duration), privacy: .public)s")
                        }
                    }

                    if self.sessionData == nil {
                        let snapshot = motionService.getFullSessionData()
                        FlexaLog.game.debug("📥 [FollowCircle] Fallback session snapshot — reps=\(snapshot.reps, privacy: .public) maxROM=\(String(format: "%.1f", snapshot.maxROM), privacy: .public) score=\(snapshot.score, privacy: .public)")
                        self.sessionData = snapshot
                    }

                    self.gameHasEnded = true
                    if let session = self.sessionData {
                        if !isActive {
                            FlexaLog.game.info("📥 [FollowCircle] Forwarding session to NavigationCoordinator (Analyzing)")
                            NavigationCoordinator.shared.showAnalyzing(sessionData: session)
                        } else {
                            FlexaLog.game.warning("📥 [FollowCircle] Skipping NavigationCoordinator flow because binding isActive is true")
                        }
                    } else {
                        FlexaLog.game.error("📥 [FollowCircle] No session data available to present results")
                    }
                }
            }
            .onDisappear {
                FlexaLog.game.info("🎯 [FollowCircle] View disappeared — stopping game")
                stopGame(reason: "viewDisappear")
            }
            .fullScreenCover(isPresented: $showingAnalyzing) {
                if let sessionData = sessionData {
                    AnalyzingView(sessionData: sessionData)
                        .environmentObject(NavigationCoordinator.shared)
                        .onDisappear {
                            // When AnalyzingView is dismissed, show ResultsView
                            showingResults = true
                        }
                }
            }
            .fullScreenCover(isPresented: $showingResults) {
                if let sessionData = sessionData {
                    ResultsView(sessionData: sessionData)
                        .environmentObject(NavigationCoordinator.shared)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
    
    private func setupGame() {
        FlexaLog.game.info("🎯 [FollowCircle] setupGame() — isARKitRunning=\(motionService.isARKitRunning, privacy: .public) sessionActive=\(motionService.isSessionActive, privacy: .public)")
        
        // Reset SPARC service to clear old data from previous sessions
        motionService.sparcService.reset()
        
        // ROM tracking mode automatically determined by SimpleMotionService based on game type
        motionService.startGameSession(gameType: .followCircle)
        FlexaLog.game.info("🎯 [FollowCircle] Requested SimpleMotionService.startGameSession(.followCircle)")
        
        startGame()
    }
    
    private func startGame() {
        FlexaLog.game.info("🎯 [FollowCircle] startGame() — resetting state and timers")
        FlexaLog.motion.info("🎮 [FollowCircle] Starting game - motionService active: \(motionService.isSessionActive), ARKit running: \(motionService.isARKitRunning)")
        gameHasEnded = false // Reset the flag for new game
        isGameActive = true
        gameScore = 0
        gameTime = 0
        lastTouchTime = Date()
        isTouchingCircle = false
        consecutiveTouches = 0
        gameStartTime = Date()
        gracePeriodEnded = false
        lastContactTime = Date()
        offCircleStartTime = nil
        lastLoggedSecond = -1
        hasLoggedBaselineCapture = false
        hasLoggedMissingTransform = false
        
        // Reset circle positions to center (rep tracking handled by Universal3D engine)
        let centerX = screenSize.width / 2
        let centerY = screenSize.height / 2
        userCirclePosition = CGPoint(x: centerX, y: centerY)
        guideCirclePosition = CGPoint(x: centerX, y: centerY)
        guideCircleCenter = CGPoint(x: centerX, y: centerY)
        guideCircleRadius = 12 // Much smaller guide circle
        guideCircleSpeed = 1.0
        guideCircleAngle = 0
        guideCircleOrbitRadius = 60 // Made smaller
        
        // Reset movement tracking
        cursorVelocity = CGPoint.zero
        lastAcceleration = CGPoint.zero
        
        // Start game timer at 60fps for smooth movement
        gameTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { _ in
            updateGame()
        }
        FlexaLog.game.debug("🎯 [FollowCircle] Game timer scheduled at 60 FPS")
        
        // Start motion tracking
        motionService.startSession(gameType: .followCircle)
        FlexaLog.game.info("🎯 [FollowCircle] motionService.startSession(.followCircle)")

        // AR baseline will be captured on first position update
        arBaseline = nil
        hasLoggedBaselineCapture = false
    }
    
    private func updateGame() {
        guard isGameActive else { return }
        
        gameTime += 0.016
        let formattedTime = String(format: "%.2f", gameTime)
        let currentSecond = Int(gameTime)
        if currentSecond != lastLoggedSecond {
            lastLoggedSecond = currentSecond
            let guideDescription = String(format: "%.0f,%.0f", guideCirclePosition.x, guideCirclePosition.y)
            let cursorDescription = String(format: "%.0f,%.0f", userCirclePosition.x, userCirclePosition.y)
            FlexaLog.game.debug("⏱️ [FollowCircle] t=\(formattedTime, privacy: .public)s contact=\(self.isTouchingCircle, privacy: .public) score=\(self.gameScore, privacy: .public) streak=\(self.consecutiveTouches, privacy: .public) guide=\(guideDescription, privacy: .public) cursor=\(cursorDescription, privacy: .public)")
        }
        
        // Record frame for performance monitoring
        motionService.recordFrame()
        
        // Short grace period before enforcing contact requirement
        if !gracePeriodEnded && Date().timeIntervalSince(gameStartTime) >= gracePeriodDuration {
            gracePeriodEnded = true
            lastContactTime = Date()
            FlexaLog.game.info("🛡️ [FollowCircle] Grace period ended at t=\(formattedTime, privacy: .public)s")
        }
        
        // Update user circle position based on device movement (not tilt!)
        updateUserCirclePosition()
        
        // Update guide circle movement
        updateGuideCircle()
        
        // Check if user is touching the guide circle
        let distance = sqrt(pow(userCirclePosition.x - guideCirclePosition.x, 2) +
                           pow(userCirclePosition.y - guideCirclePosition.y, 2))
        let tolerance: CGFloat = 8
        let isCurrentlyTouching = distance <= (guideCircleRadius + cursorRadius + tolerance)
        
        if isCurrentlyTouching {
            if !isTouchingCircle {
                isTouchingCircle = true
                lastTouchTime = Date()
                lastContactTime = Date() // Reset contact timer
                if let offStart = offCircleStartTime {
                    let downtime = Date().timeIntervalSince(offStart)
                    FlexaLog.game.debug("🟢 [FollowCircle] Guide contact regained — downtime=\(String(format: "%.2f", downtime), privacy: .public)s")
                }
                offCircleStartTime = nil
                consecutiveTouches += 1
                FlexaLog.game.debug("🟢 [FollowCircle] Guide contact gained — distance=\(String(format: "%.1f", distance), privacy: .public) touches=\(self.consecutiveTouches, privacy: .public)")
            }
            // Add score while touching (more points for longer streaks) - only after grace period
            if gracePeriodEnded {
                let streakMultiplier = max(1, consecutiveTouches / 10)
                gameScore += streakMultiplier
                if consecutiveTouches % 20 == 0 {
                    FlexaLog.game.debug("🔥 [FollowCircle] Streak milestone — touches=\(self.consecutiveTouches, privacy: .public) score=\(self.gameScore, privacy: .public) multiplier=\(streakMultiplier, privacy: .public)")
                }
            }
        } else {
            if isTouchingCircle {
                isTouchingCircle = false
                lastTouchTime = Date()
                consecutiveTouches = 0
                FlexaLog.game.debug("🔴 [FollowCircle] Guide contact lost — distance=\(String(format: "%.1f", distance), privacy: .public)")
            }
            // Only start grace timer after initial grace period ends
            if gracePeriodEnded && offCircleStartTime == nil {
                offCircleStartTime = Date()
                FlexaLog.game.debug("⏳ [FollowCircle] Guide contact grace timer started")
            }
        }
        
        // End session once the cursor has been away from the guide for the timeout duration
        if gracePeriodEnded,
           let offStart = offCircleStartTime,
           !isTouchingCircle,
           Date().timeIntervalSince(offStart) >= offCircleGraceDuration,
           !gameHasEnded {
            let downtime = Date().timeIntervalSince(offStart)
            FlexaLog.game.info("🎯 [FollowCircle] Off-circle timeout reached — downtime=\(String(format: "%.2f", downtime), privacy: .public)s t=\(formattedTime, privacy: .public)s")
            completeSession(trigger: "no_contact_timeout")
        }
        
        // Auto-end game after 2 minutes maximum
        if gameTime >= 120.0 && !gameHasEnded {
            FlexaLog.game.info("🎯 [FollowCircle] Maximum time reached — ending session")
            completeSession(trigger: "max_duration")
        }
        
        // Update bindings
        score = gameScore
        rom = motionService.currentROM
    }
    
    private func updateUserCirclePosition() {
        guard let transform = motionService.currentARKitTransform else {
            // No ARKit data available - center cursor
            userCirclePosition = CGPoint(x: screenSize.width / 2, y: screenSize.height / 2)
            rom = motionService.currentROM
            return
        }
        
        // Extract 3D position from ARKit transform (columns.3 is translation vector)
        let pos = SIMD3<Double>(
            Double(transform.columns.3.x),
            Double(transform.columns.3.y),
            Double(transform.columns.3.z)
        )
        
        // Initialize baseline on first frame
        if arBaseline == nil {
            arBaseline = pos
            userCirclePosition = CGPoint(x: screenSize.width / 2, y: screenSize.height / 2)
            return
        }
        
        guard let baseline = arBaseline else {
            rom = motionService.currentROM
            return
        }
        
        // Calculate relative movement from baseline
        let relX = pos.x - baseline.x  // Horizontal: right/left
        let relZ = pos.z - baseline.z  // Vertical: up/down
        
        let centerX = screenSize.width / 2
        let centerY = screenSize.height / 2
        
        // Movement range for responsive tracking
        let horizontalRange = min(screenSize.width / 2 - 40, 250.0)
        let verticalRange = min(screenSize.height / 2 - 60, 300.0)
        
        // Apply gain for 1:1 hand tracking
        let gain: Double = 4.5
        let screenDeltaX = relX * gain
        let screenDeltaY = relZ * gain
        
        // Clamp to normalized range
        let nx = max(-1.0, min(1.0, screenDeltaX))
        let ny = max(-1.0, min(1.0, screenDeltaY))
        
        // Calculate target position
        let targetX = centerX + CGFloat(nx) * horizontalRange
        let targetY = centerY + CGFloat(ny) * verticalRange
        
        // Apply bounds with padding
        let horizontalPadding = cursorRadius + 12
        let boundedX = max(horizontalPadding, min(screenSize.width - horizontalPadding, targetX))
        let verticalTopPadding: CGFloat = 60
        let verticalBottomPadding: CGFloat = 100
        let boundedY = max(verticalTopPadding, min(screenSize.height - verticalBottomPadding, targetY))
        
        // Update cursor position
        userCirclePosition = CGPoint(x: boundedX, y: boundedY)
        lastScreenPoint = userCirclePosition
        rom = motionService.currentROM
    }
    
    // Rep tracking now handled by Universal3D engine via live callbacks
    
    private func updateGuideCircle() {
        // Don't move guide circle during grace period - let user get ready
        if !gracePeriodEnded {
            return
        }
        
        // Gradually increase speed for difficulty progression
        guideCircleSpeed += 0.0005
        
        // Increase orbit radius gradually, but cap it
        if guideCircleOrbitRadius < 120 {
            guideCircleOrbitRadius += 0.01
        }
        
        // Make the circle smaller over time for more challenge
        if guideCircleRadius > 8 {
            guideCircleRadius -= 0.0015
        }
        
        // Update angle for circular motion
        guideCircleAngle += guideCircleSpeed * 0.016
        
        // Add some randomness to make it more interesting
        let randomVariation = sin(gameTime * 2) * 0.1
        let currentAngle = guideCircleAngle + randomVariation
        
        // Calculate new position
        let newX = guideCircleCenter.x + cos(currentAngle) * guideCircleOrbitRadius
        let newY = guideCircleCenter.y + sin(currentAngle) * guideCircleOrbitRadius
        
        // Keep within screen bounds
        let padding: CGFloat = 50
        let boundedX = max(padding, min(screenSize.width - padding, newX))
        let boundedY = max(padding + 50, min(screenSize.height - padding - 100, newY))
        
        guideCirclePosition = CGPoint(x: boundedX, y: boundedY)
    }
    
    private func completeSession(trigger: String) {
        guard isGameActive && !gameHasEnded else { return } // Prevent multiple calls
        
        FlexaLog.game.info("🎯 [FollowCircle] Starting session completion — trigger=\(trigger, privacy: .public) score=\(self.gameScore, privacy: .public)")
        gameHasEnded = true
        isGameActive = false
        gameTimer?.invalidate()
        gameTimer = nil
        offCircleStartTime = nil
        
        // Calculate final values with safety checks
    let finalReps = max(0, motionService.currentReps)
        let finalROM = max(0, motionService.maxROM)
        
        // Get SPARC data points (full history for graphing)
        let sparcDataPoints = motionService.sparcService.getSPARCDataPoints()
        let finalSPARC = max(0, motionService.sparcService.getCurrentSPARC())
        
        // Convert SPARC data points to Double array for history
        let sparcHistory = sparcDataPoints.map { $0.sparcValue }
        
        print("📊 [FollowCircle] SPARC collected: \(sparcDataPoints.count) data points, final score: \(String(format: "%.2f", finalSPARC))")
        
        // Update bindings safely
        score = gameScore
        reps = finalReps
        rom = finalROM
        
        // Snapshot raw session data for diagnostics
        _ = motionService.getSessionData()
        FlexaLog.game.debug("🎯 [FollowCircle] Requested motion session snapshot for diagnostics")
        
        // Stop motion tracking with proper cleanup and delay to prevent camera conflicts
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // Snapshot motion metrics before stopping the session (stopSession clears buffers)
            let romHistoryValues = self.motionService.romPerRepArray
            let repTimestamps = self.motionService.romPerRepTimestampsDates
            let sparcHistoryValues = sparcHistory.isEmpty ? self.motionService.sparcHistoryArray : sparcHistory
            
            // Convert SPARCDataPoints to SPARCPoint array with real timestamps
            let sparcDataWithTimestamps: [SPARCPoint] = sparcDataPoints.map { dataPoint in
                SPARCPoint(sparc: dataPoint.sparcValue, timestamp: dataPoint.timestamp)
            }

            // Build comprehensive session data with safety checks
            var exerciseSession = ExerciseSessionData(
                exerciseType: GameType.followCircle.displayName,
                score: self.gameScore,
                reps: finalReps,
                maxROM: finalROM,
                duration: self.gameTime,
                timestamp: Date(),
                romHistory: romHistoryValues.isEmpty ? [finalROM] : romHistoryValues,
                repTimestamps: repTimestamps,
                sparcHistory: sparcHistoryValues.isEmpty ? [finalSPARC] : sparcHistoryValues,
                sparcData: sparcDataWithTimestamps,
                sparcScore: finalSPARC
            )

            // Ensure histories contain at least one data point for downstream consumers
            if exerciseSession.romHistory.isEmpty {
                exerciseSession.romHistory = [finalROM]
            }
            if exerciseSession.sparcHistory.isEmpty {
                exerciseSession.sparcHistory = [finalSPARC]
            }

            self.sessionData = exerciseSession

            FlexaLog.game.info("🎯 [FollowCircle] Session complete → reps=\(finalReps, privacy: .public) maxROM=\(String(format: "%.1f", finalROM), privacy: .public)° SPARC=\(String(format: "%.2f", finalSPARC), privacy: .public) sparcPoints=\(exerciseSession.sparcHistory.count, privacy: .public)")

            // Post game end notification to trigger analyzing screen
            let userInfo = self.motionService.buildSessionNotificationPayload(from: exerciseSession)
            FlexaLog.game.info("📣 [FollowCircle] Posting game end → score=\(exerciseSession.score, privacy: .public) reps=\(exerciseSession.reps, privacy: .public) maxROM=\(String(format: "%.1f", exerciseSession.maxROM), privacy: .public)° SPARC=\(String(format: "%.2f", exerciseSession.sparcScore), privacy: .public)")
            NotificationCenter.default.post(name: NSNotification.Name("FollowCircleGameEnded"), object: nil, userInfo: userInfo)

            FlexaLog.game.info("🎯 [FollowCircle] Stopping motion service (trigger=\(trigger, privacy: .public))")
            self.motionService.stopSession()
        }
    }
    
    private func stopGame(reason: String = "unspecified") {
        FlexaLog.game.info("🎯 [FollowCircle] stopGame(reason: \(reason, privacy: .public)) — isGameActive=\(self.isGameActive, privacy: .public) gameHasEnded=\(self.gameHasEnded, privacy: .public)")
        FlexaLog.motion.info("🎮 [FollowCircle] Stopping game - score: \(gameScore), gameTime: \(gameTime)s, reason: \(reason)")
        gameHasEnded = true
        isGameActive = false
        gameTimer?.invalidate()
        gameTimer = nil
        offCircleStartTime = nil
        FlexaLog.motion.info("🎮 [FollowCircle] Game stopped and timer invalidated")
        
        // Stop session with delay to prevent camera conflicts
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            FlexaLog.game.debug("🎯 [FollowCircle] stopGame() requesting motionService.stopSession() (reason=\(reason, privacy: .public))")
            self.motionService.stopSession()
        }
        
        arBaseline = nil
        lastScreenPoint = nil
        hasLoggedMissingTransform = false
    }
    
    private func recalibrateCenter() {
        // Reset baseline to current position for better cursor control
        // Reset baseline for recalibration
        arBaseline = nil
        
        // Reset cursor to center
        let centerX = screenSize.width / 2
        let centerY = screenSize.height / 2
        userCirclePosition = CGPoint(x: centerX, y: centerY)
        lastScreenPoint = CGPoint(x: centerX, y: centerY)
        hasLoggedBaselineCapture = false
        
        // Show recalibration message
        withAnimation(.easeInOut(duration: 0.3)) {
            showRecalibrateMessage = true
        }
        
        // Hide message after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.3)) {
                showRecalibrateMessage = false
            }
        }
        
        FlexaLog.game.info("🎯 [FollowCircle] Center recalibrated — baseline reset")
    }
}

struct FollowCircleGameScene: View {
    @Binding var userCirclePosition: CGPoint
    @Binding var guideCirclePosition: CGPoint
    @Binding var guideCircleRadius: CGFloat
    @Binding var isTouchingCircle: Bool
    @Binding var cursorRadius: CGFloat
    
    var body: some View {
        Canvas { context, size in
            // Draw user circle (green with hollow center)
            let userCircle = Path { path in
                path.addEllipse(in: CGRect(
                    x: userCirclePosition.x - cursorRadius,
                    y: userCirclePosition.y - cursorRadius,
                    width: cursorRadius * 2,
                    height: cursorRadius * 2
                ))
            }
            
            // User circle with hollow center effect
            context.fill(userCircle, with: .color(.green.opacity(0.25)))
            context.stroke(userCircle, with: .color(.green), lineWidth: 2)
            
            // Draw guide circle (white solid)
            let guideCircle = Path { path in
                path.addEllipse(in: CGRect(
                    x: guideCirclePosition.x - guideCircleRadius,
                    y: guideCirclePosition.y - guideCircleRadius,
                    width: guideCircleRadius * 2,
                    height: guideCircleRadius * 2
                ))
            }
            
            // Guide circle with solid fill
            context.fill(guideCircle, with: .color(.white))
            context.stroke(guideCircle, with: .color(.gray), lineWidth: 2)
            
            // Draw connection line when touching
            if isTouchingCircle {
                let connectionLine = Path { path in
                    path.move(to: userCirclePosition)
                    path.addLine(to: guideCirclePosition)
                }
                context.stroke(connectionLine, with: .color(.green), lineWidth: 3)
            }
        }
    }
}

#Preview {
    FollowCircleGameView(
        score: .constant(0),
        reps: .constant(0),
        rom: .constant(0),
        isActive: .constant(false)
    )
    .environmentObject(SimpleMotionService.shared)
    .environmentObject(BackendService())
}
