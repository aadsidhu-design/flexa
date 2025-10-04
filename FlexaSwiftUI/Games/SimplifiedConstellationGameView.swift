import SwiftUI

struct ArmRaisesGameView: View {
    @EnvironmentObject var motionService: SimpleMotionService
    @EnvironmentObject var backendService: BackendService
    @StateObject private var calibrationCheck = CalibrationCheckService.shared
    var isHosted: Bool = false
    @State private var handPosition: CGPoint = .zero
    @State private var currentTargetIndex: Int = 0
    @State private var connectedPoints: [Int] = []
    @State private var currentPattern: [CGPoint] = []
    @State private var gameTime: Double = 0
    @State private var score = 0
    @State private var currentPatternName = "Triangle"
    @State private var isGameActive = false
    @State private var sessionData: ExerciseSessionData?
    @State private var gameTimer: Timer?
    @State private var completedPatterns = 0
    @State private var isUserInteracting: Bool = false
    @State private var wrongConnectionCount = 0
    @State private var showIncorrectFeedback = false
    @State private var incorrectFeedbackToken: UUID?
    @State private var lastDetectedPointIndex: Int?
    @State private var lastDetectionTimestamp: TimeInterval = 0
    @State private var isHoveringOverCurrentTarget: Bool = false
    @State private var screenSize: CGSize = UIScreen.main.bounds.size
    private let maxGameDuration: TimeInterval = 60

    var body: some View {
        Group {
            // Check calibration status first
            if !calibrationCheck.isCalibrated {
                CalibrationRequiredView()
                    .environmentObject(calibrationCheck)
            } else {
                GeometryReader { geometry in
                    ZStack {
                        CameraGameBackground()

                        // Arm Raises pattern dots - STAY IN PLACE WHEN SELECTED
                        ForEach(Array(currentPattern.enumerated()), id: \.offset) { index, point in
                            Circle()
                                .foregroundColor(connectedPoints.contains(index) ? Color.green : Color.white)
                                .overlay(
                                    Circle()
                                        .stroke(Color.cyan, lineWidth: connectedPoints.contains(index) ? 4 : 3)
                                )
                                .frame(width: 24, height: 24)
                                .position(point)  // NEVER MOVE - dots stay locked in position
                                .scaleEffect(connectedPoints.contains(index) ? 1.3 : 1.0)
                                .animation(.easeInOut(duration: 0.2), value: connectedPoints)
                        }

                        // Persistent connection lines between completed dots
                        if connectedPoints.count > 1 {
                            Path { path in
                                path.move(to: currentPattern[connectedPoints[0]])
                                for i in 1..<connectedPoints.count {
                                    path.addLine(to: currentPattern[connectedPoints[i]])
                                }
                            }
                            .stroke(Color.cyan, lineWidth: 4)
                            .opacity(0.9)
                        }
                        
                        // Dynamic connection line - ONLY shows when hovering near an unconnected dot
                        if isGameActive && connectedPoints.count > 0 && isHoveringOverCurrentTarget && handPosition != .zero {
                            // Find which dot we're hovering over
                            if let (nearestIndex, _) = nearestPatternPoint(to: handPosition, within: targetHitTolerance()),
                               !connectedPoints.contains(nearestIndex) {
                                // Draw line from LAST connected dot to hand position
                                Path { path in
                                    let lastConnectedDot = currentPattern[connectedPoints.last!]
                                    path.move(to: lastConnectedDot)
                                    path.addLine(to: handPosition)
                                }
                                .stroke(Color.cyan, lineWidth: 3)
                                .opacity(0.6)
                                .animation(.easeInOut(duration: 0.1), value: handPosition)
                            }
                        }
                    
                    // Hand tracking circle - only show when wrist is detected
                    if isGameActive && handPosition != .zero {
                        Circle()
                            .stroke(Color.cyan, lineWidth: 4)
                            .frame(width: 50, height: 50)
                            .position(handPosition)
                            .opacity(0.9)
                            .overlay(
                                Circle()
                                    .fill(Color.cyan.opacity(0.3))
                                    .frame(width: 30, height: 30)
                            )
                    }

                    // (camera is drawn behind; do not overlay again)
                
                    // Camera obstruction warning overlay
                    CameraObstructionOverlay(
                        isObstructed: motionService.isCameraObstructed,
                        reason: motionService.cameraObstructionReason,
                        isBackCamera: false
                    )
                    .zIndex(1000)
                    
                    // Fast movement warning overlay
                    if motionService.isMovementTooFast {
                        VStack {
                            FastMovementWarningOverlay(
                                isMovementTooFast: motionService.isMovementTooFast,
                                reason: motionService.fastMovementReason
                            )
                            .padding(.top, 100)
                            Spacer()
                        }
                        .zIndex(999)
                    }

                    // Minimal UI overlay - ONLY patterns completed (no timer)
                    VStack {
                        HStack {
                            Spacer()
                            VStack(spacing: 4) {
                                Text("Pattern \(completedPatterns + 1)/3")
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                Text("Connect any dot to start!")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .padding()
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(15)
                            Spacer()
                        }
                        .padding(.top, 60)

                        if showIncorrectFeedback {
                            Text("Incorrect")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 10)
                                .background(Color.red.opacity(0.85))
                                .cornerRadius(12)
                                .foregroundColor(.white)
                                .transition(.opacity)
                                .padding(.top, 12)
                        }

                        Text(formattedTimeRemaining())
                            .font(.system(.title3, design: .rounded).monospacedDigit())
                            .fontWeight(.semibold)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(14)
                            .foregroundColor(.white)
                            .padding(.top, 8)

                        Spacer()
                    }
                    }
                    .onAppear {
                        screenSize = geometry.size
                    }
                }
            }
        }
        .onAppear {
            FlexaLog.game.info("🔍 [ArmRaises] onAppear called - setting up game")
            setupGame()
        }
        .onDisappear {
            cleanup()
        }
        .onChange(of: motionService.isCameraObstructed) { _ in
            // Camera obstruction handled by overlay
        }
        .onReceive(motionService.$currentReps) { newReps in
            completedPatterns = newReps
        }
    // Navigation is now driven by NavigationCoordinator to avoid conflicting local covers.
    // When the game ends, call NavigationCoordinator.shared.showAnalyzing(sessionData:).
        .toolbar(.hidden, for: .navigationBar)
    }

    private func setupGame() {
        FlexaLog.game.info("🔍 [ArmRaises] setupGame called - starting game session")
        motionService.startGameSession(gameType: .constellation)
        FlexaLog.game.info("🔍 [ArmRaises] Game session started")
        FlexaLog.game.info("🔍 [ArmRaises] Generating new pattern...")
        generateNewPattern()
        FlexaLog.game.info("🔍 [ArmRaises] Pattern generated with \(currentPattern.count) points")
        FlexaLog.game.info("🔍 [ArmRaises] Starting game timer...")
        gameTime = 0
        startGameTimer()
        isGameActive = true
        FlexaLog.game.info("🔍 [ArmRaises] Game is now active!")
        
    }

    private func startGame() {
        isGameActive = true
        startGameTimer()
    }

    private func startGameTimer() {
        gameTimer?.invalidate()
        gameTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { timer in
            guard self.isGameActive else {
                timer.invalidate()
                DispatchQueue.main.async {
                    self.gameTimer = nil
                }
                return
            }
            self.updateGame()
        }
    }

    private func updateGame() {
        // Drive gameplay from camera tracking; no IMU required here
        if motionService.isCameraObstructed {
            FlexaLog.game.warning("🚨 [ArmRaises] Camera obstructed - pausing game tick")
            return
        }
        updateHandTracking()
        evaluateTargetHit()
        gameTime += 1.0/60.0
        FlexaLog.game.debug("⏱ [ArmRaises] Game tick - time: \(gameTime), score: \(score), completedPatterns: \(completedPatterns)")
        if gameTime >= maxGameDuration {
            FlexaLog.game.info("⏰ [ArmRaises] 60-second limit reached - stopping game")
            endGame()
            return
        }
        // End game ONLY when 3 patterns are completed (no time limit)
        if completedPatterns >= 3 {
            FlexaLog.game.info("🎯 [ArmRaises] 3 patterns completed - stopping game")
            endGame()
        }
    }
    
    private func updateHandTracking() {
        // Ensure we have valid pose data before tracking
        guard let poseKeypoints = motionService.poseKeypoints else {
            // NO WRIST DETECTED - hide hand circle by setting to zero
            handPosition = .zero
            isUserInteracting = false
            isHoveringOverCurrentTarget = false
            return
        }
        
        // Use the active arm for tracking
        let activeSide = poseKeypoints.phoneArm
        let activeWrist = (activeSide == .left) ? poseKeypoints.leftWrist : poseKeypoints.rightWrist
        
        if let wrist = activeWrist {
            let previousPosition = handPosition
            // Map using coordinate mapper with better smoothing for precise control
            let mapped = CoordinateMapper.mapVisionPointToScreen(wrist, previewSize: screenSize)
            
            // DETAILED COORDINATE LOGGING
            print("🎯 [ArmRaises-COORDS] RAW Vision: x=\(String(format: "%.4f", wrist.x)), y=\(String(format: "%.4f", wrist.y))")
            print("🎯 [ArmRaises-COORDS] MAPPED Screen: x=\(String(format: "%.1f", mapped.x)), y=\(String(format: "%.1f", mapped.y)) (preview: \(screenSize.width)×\(screenSize.height))")
            
            // CRITICAL: Use DIRECT mapping with minimal smoothing for precision
            // The circle MUST stick to the wrist landmark
            let alpha: CGFloat = 0.8  // Very high alpha = instant response, sticks to wrist
            handPosition = CGPoint(
                x: previousPosition == .zero ? mapped.x : (previousPosition.x * (1 - alpha) + mapped.x * alpha),
                y: previousPosition == .zero ? mapped.y : (previousPosition.y * (1 - alpha) + mapped.y * alpha)
            )
            
            print("🎯 [ArmRaises-COORDS] Hand circle position: x=\(String(format: "%.1f", handPosition.x)), y=\(String(format: "%.1f", handPosition.y))")

            // Check if user is actively moving (interacting)
            if previousPosition != .zero {
                let distance = sqrt(pow(handPosition.x - previousPosition.x, 2) + pow(handPosition.y - previousPosition.y, 2))
                isUserInteracting = distance > 2.0 // Lower threshold for better responsiveness
            }
            
            // Check if hovering over current target dot
            if currentTargetIndex < currentPattern.count {
                let targetPoint = currentPattern[currentTargetIndex]
                let distanceToTarget = hypot(handPosition.x - targetPoint.x, handPosition.y - targetPoint.y)
                let hoverTolerance = targetHitTolerance() * 1.2 // Slightly larger radius for visual feedback
                isHoveringOverCurrentTarget = distanceToTarget <= hoverTolerance
            } else {
                isHoveringOverCurrentTarget = false
            }

            // Add SPARC data based on mapped preview coordinates (use screen-space positions)
            motionService.sparcService.addVisionMovement(
                timestamp: Date().timeIntervalSince1970,
                position: mapped
            )
        } else {
            // NO WRIST FOR ACTIVE ARM - hide circle
            handPosition = .zero
            isUserInteracting = false
            isHoveringOverCurrentTarget = false
        }
    }

    private func evaluateTargetHit() {
        guard isGameActive, !currentPattern.isEmpty, handPosition != .zero else { return }

        let tolerance = targetHitTolerance()
        guard let (index, _) = nearestPatternPoint(to: handPosition, within: tolerance) else { 
            // Not near any dot - just hovering
            isHoveringOverCurrentTarget = false
            return 
        }

        let now = CACurrentMediaTime()
        
        // Allow starting from ANY dot (not just index 0)
        if connectedPoints.isEmpty {
            // First dot - user can select any dot to start
            if let lastIndex = lastDetectedPointIndex,
               lastIndex == index,
               now - lastDetectionTimestamp < 0.4 {
                return // Debounce
            }
            lastDetectedPointIndex = index
            lastDetectionTimestamp = now
            
            // Start the constellation from this dot
            handleCorrectHit(for: index)
            isUserInteracting = true
            isHoveringOverCurrentTarget = true
            print("🌟 [ArmRaises] Starting constellation from dot #\(index)")
            return
        }
        
        // Check if hovering over an unconnected dot
        if !connectedPoints.contains(index) {
            isHoveringOverCurrentTarget = true
            
            // Debounce hit detection
            if let lastIndex = lastDetectedPointIndex,
               lastIndex == index,
               now - lastDetectionTimestamp < 0.4 {
                return
            }
            
            lastDetectedPointIndex = index
            lastDetectionTimestamp = now
            
            // Connect to this new dot (point-to-point is a rep!)
            handleCorrectHit(for: index)
            isUserInteracting = true
        } else {
            // Already connected - just hovering
            isHoveringOverCurrentTarget = connectedPoints.contains(index)
        }
    }

    private func handleCorrectHit(for index: Int) {
        print("✅ [ArmRaises] Connected to dot #\(index)")
        wrongConnectionCount = 0
        clearIncorrectFeedback()
        HapticFeedbackService.shared.successHaptic()

        if !connectedPoints.contains(index) {
            connectedPoints.append(index)
            
            // CRITICAL: Each point-to-point connection is a REP!
            if connectedPoints.count > 1 {
                // Record rep for this connection
                if let keypoints = motionService.poseKeypoints {
                    let rawROM = keypoints.getArmpitROM(side: keypoints.phoneArm)
                    let normalized = motionService.validateAndNormalizeROM(rawROM)
                    let minimumThreshold = motionService.getMinimumROMThreshold(for: .constellation)
                    if normalized >= minimumThreshold {
                        motionService.recordVisionRepCompletion(rom: normalized)
                        print("🎯 [ArmRaises] Rep recorded! Total reps: \(motionService.currentReps), ROM: \(String(format: "%.1f", normalized))°")
                    }
                }
            }
            
            score += 10 // Points for each dot connection
        }

        // Check if pattern is completed (all dots connected)
        if connectedPoints.count >= currentPattern.count {
            onPatternCompleted()
        }
    }

    private func nearestPatternPoint(to position: CGPoint, within tolerance: CGFloat) -> (Int, CGFloat)? {
        guard !currentPattern.isEmpty else { return nil }
        var bestMatch: (Int, CGFloat)?
        for (index, point) in currentPattern.enumerated() {
            let distance = hypot(position.x - point.x, position.y - point.y)
            guard distance <= tolerance else { continue }
            if let existing = bestMatch {
                if distance < existing.1 {
                    bestMatch = (index, distance)
                }
            } else {
                bestMatch = (index, distance)
            }
        }
        return bestMatch
    }

    private func targetHitTolerance() -> CGFloat {
        max(36, screenSize.width * 0.06)
    }

    private func scheduleIncorrectFeedbackHide() {
        let token = UUID()
        incorrectFeedbackToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            guard incorrectFeedbackToken == token else { return }
            withAnimation {
                showIncorrectFeedback = false
            }
            incorrectFeedbackToken = nil
        }
    }

    private func clearIncorrectFeedback() {
        incorrectFeedbackToken = nil
        if showIncorrectFeedback {
            withAnimation {
                showIncorrectFeedback = false
            }
        }
    }

    private func onPatternCompleted() {
        completedPatterns += 1
        score += 100
        
        // Calculate ROM for this pattern completion (count as one rep)
        if let keypoints = motionService.poseKeypoints {
            let rawROM = keypoints.getArmpitROM(side: keypoints.phoneArm)
            let normalized = motionService.validateAndNormalizeROM(rawROM)
            let minimumThreshold = motionService.getMinimumROMThreshold(for: .constellation)
            if normalized >= minimumThreshold {
                motionService.recordVisionRepCompletion(rom: normalized)
                completedPatterns = motionService.currentReps
                print("🌟 [ArmRaises] Pattern completed! Patterns: \(completedPatterns), ROM: \(String(format: "%.1f", normalized))° (threshold: \(String(format: "%.1f", minimumThreshold))°)")
            } else {
                print("⚠️ [ArmRaises] Pattern ROM below threshold — ROM: \(String(format: "%.1f", normalized))°")
            }
        }
        
        // Check if game should end (3 patterns completed)
        if completedPatterns >= 3 {
            endGame()
            return
        }
        
        generateNewPattern()
    }
    
    private func generateNewPattern() {
        // Reset pattern state
        currentPattern.removeAll()
        connectedPoints.removeAll()
        currentTargetIndex = 0
        wrongConnectionCount = 0
        lastDetectedPointIndex = nil
        lastDetectionTimestamp = 0
        isUserInteracting = false
        isHoveringOverCurrentTarget = false
        clearIncorrectFeedback()
        
        let centerX = screenSize.width / 2
        let centerY = screenSize.height / 2
        let patternSize: CGFloat = 120
        
        switch currentPatternName {
        case "Circle":
            // Generate circle pattern with 8 points
            let numPoints = 8
            currentPattern = (0..<numPoints).map { i in
                let angle = (Double(i) * 2.0 * .pi) / Double(numPoints)
                let x = centerX + patternSize * CGFloat(cos(angle))
                let y = centerY + patternSize * CGFloat(sin(angle))
                return CGPoint(x: x, y: y)
            }
            currentPatternName = "Triangle"
            print("⭕ [ArmRaises] Generated CIRCLE pattern with \(numPoints) points")
        case "Triangle":
            currentPattern = [
                CGPoint(x: centerX, y: centerY - patternSize),
                CGPoint(x: centerX - patternSize * 0.866, y: centerY + patternSize * 0.5),
                CGPoint(x: centerX + patternSize * 0.866, y: centerY + patternSize * 0.5)
            ]
            currentPatternName = "Square"
        case "Square":
            currentPattern = [
                CGPoint(x: centerX - patternSize, y: centerY - patternSize),
                CGPoint(x: centerX + patternSize, y: centerY - patternSize),
                CGPoint(x: centerX + patternSize, y: centerY + patternSize),
                CGPoint(x: centerX - patternSize, y: centerY + patternSize)
            ]
            currentPatternName = "Circle"
        default:
            currentPatternName = "Circle"
            generateNewPattern()
            return
        }
    }
    
    private func endGame() {
        isGameActive = false
        gameTimer?.invalidate()
        gameTimer = nil
        let snapshot = motionService.getFullSessionData(
            overrideScore: score,
            overrideExerciseType: GameType.constellationMaker.displayName
        )
        var sessionData = snapshot
        if sessionData.romHistory.isEmpty {
            sessionData.romHistory = motionService.romPerRepArray.filter { $0.isFinite }
        }
        if sessionData.sparcHistory.isEmpty {
            sessionData.sparcHistory = motionService.sparcHistoryArray.filter { $0.isFinite }
        }

        print("🌟 [ArmRaises] Final stats - Score: \(sessionData.score), Patterns: \(sessionData.reps), MaxROM: \(String(format: "%.1f", sessionData.maxROM))°, SPARC avg: \(String(format: "%.1f", sessionData.sparcScore))")

        motionService.stopSession()
        self.sessionData = sessionData
        let userInfo = motionService.buildSessionNotificationPayload(from: sessionData)
        NotificationCenter.default.post(name: NSNotification.Name("ConstellationGameEnded"), object: nil, userInfo: userInfo)

        if !isHosted {
            NavigationCoordinator.shared.showAnalyzing(sessionData: sessionData)
        }
    }

    private func cleanup() {
        isGameActive = false
        isUserInteracting = false
        isHoveringOverCurrentTarget = false
        motionService.stopSession()
        gameTimer?.invalidate()
        gameTimer = nil
        incorrectFeedbackToken = nil
        showIncorrectFeedback = false
        wrongConnectionCount = 0
        lastDetectedPointIndex = nil
        lastDetectionTimestamp = 0
        
        // Reset pattern state
        currentPattern.removeAll()
        connectedPoints.removeAll()
        currentTargetIndex = 0
        handPosition = .zero
        
        // Clear any pending timers or async operations
        DispatchQueue.main.async {
            // Reset all state variables
            self.gameTime = 0
            self.score = 0
            self.completedPatterns = 0
            self.currentPatternName = "Triangle"
        }
    }

    private func formattedTimeRemaining() -> String {
        let remaining = max(0, maxGameDuration - gameTime)
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return String(format: "%01d:%02d", minutes, seconds)
    }
}
