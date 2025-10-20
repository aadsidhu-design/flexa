import SwiftUI

struct SimplifiedConstellationGameView: View {
    @StateObject private var game = ConstellationGame()
    @EnvironmentObject var motionService: SimpleMotionService

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CameraGameBackground()

                ForEach(Array(game.currentPattern.enumerated()), id: \.offset) { index, point in
                Circle()
                    .foregroundColor(game.connectedPoints.contains(index) ? Color.green : Color.white)
                    .overlay(
                        Circle()
                            .stroke(Color.cyan, lineWidth: game.connectedPoints.contains(index) ? 3 : 3)
                    )
                    .frame(width: 24, height: 24)
                    .position(point)
                    .scaleEffect(game.connectedPoints.contains(index) ? 1.07 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: game.connectedPoints)
                    .zIndex(2)
            }

            if game.connectedPoints.count > 1 {
                Path { path in
                    path.move(to: game.currentPattern[game.connectedPoints[0]])
                    for i in 1..<game.connectedPoints.count {
                        path.addLine(to: game.currentPattern[game.connectedPoints[i]])
                    }
                }
                .stroke(Color.cyan, lineWidth: 4)
                .opacity(0.9)
                .zIndex(0)
            }

            if let startIdx = game.activeLineStartIndex,
               game.connectedPoints.contains(startIdx),
               game.handPosition != .zero {
                Path { path in
                    let startPoint = game.currentPattern[startIdx]
                    path.move(to: startPoint)
                    if let endIdx = game.activeLineEndIndex,
                       game.connectedPoints.contains(endIdx) {
                        path.addLine(to: game.currentPattern[endIdx])
                    } else {
                        path.addLine(to: game.handPosition)
                    }
                }
                .stroke(Color.cyan.opacity(0.75), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .zIndex(1)
            }
        
            if game.isGameActive && game.handPosition != .zero {
                Circle()
                    .stroke(Color.cyan, lineWidth: 4)
                    .frame(width: 50, height: 50)
                    .position(game.handPosition)
                    .opacity(0.9)
                    .overlay(
                        Circle()
                            .fill(Color.cyan.opacity(0.3))
                            .frame(width: 30, height: 30)
                    )
            }

            CameraObstructionOverlay(
                isObstructed: motionService.isCameraObstructed,
                reason: motionService.cameraObstructionReason,
                isBackCamera: false
            )
            .zIndex(1000)
            // Fast movement overlay removed per request.

            VStack {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Text("Pattern \(game.completedPatterns + 1)/3")
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

                if game.showIncorrectFeedback {
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

                Spacer()
            }
            }
            .onAppear {
                game.screenSize = geometry.size
                game.motionService = motionService
                game.setupGame()
            }
            .onChange(of: geometry.size) { newSize in
                game.screenSize = newSize
            }
        }
        .onAppear {
            // Additional setup if needed
        }
        .onDisappear {
            game.cleanup()
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

class ConstellationGame: ObservableObject {
    @Published var handPosition: CGPoint = .zero
    @Published var currentTargetIndex: Int = 0
    @Published var connectedPoints: [Int] = []
    @Published var currentPattern: [CGPoint] = []
    @Published var score = 0
    @Published var currentPatternName = "Triangle"
    @Published var isGameActive = false
    @Published var completedPatterns = 0
    @Published var showIncorrectFeedback = false
    @Published var activeLineStartIndex: Int?
    @Published var activeLineEndIndex: Int?

    var motionService: SimpleMotionService?
    private var gameTimer: Timer?
    private var wrongConnectionCount = 0
    private var incorrectFeedbackToken: UUID?
    private var lastDetectedPointIndex: Int?
    private var lastDetectionTimestamp: TimeInterval = 0
    var screenSize: CGSize = .zero  // Changed to internal for GeometryReader access
    private var repDetector: CameraRepDetector = CameraRepDetector(minimumInterval: 0.3)

    func setupGame() {
        guard let motionService = motionService else { return }
        FlexaLog.game.info("🔍 [ArmRaises] setupGame called - starting game session")
        motionService.preferredCameraJoint = .armpit
        motionService.startGameSession(gameType: .constellation)
        FlexaLog.game.info("🔍 [ArmRaises] Game session started")
        FlexaLog.game.info("🔍 [ArmRaises] Generating new pattern...")
        generateNewPattern()
        FlexaLog.game.info("🔍 [ArmRaises] Pattern generated with \(self.currentPattern.count) points")
        FlexaLog.game.info("🔍 [ArmRaises] Starting game timer...")
        startGameTimer()
        isGameActive = true
        FlexaLog.game.info("🔍 [ArmRaises] Game is now active!")
    }

    func startGameTimer() {
        gameTimer?.invalidate()
        gameTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] timer in
            guard let self = self, self.isGameActive else {
                timer.invalidate()
                self?.gameTimer = nil
                return
            }
            self.updateGame()
        }
    }

    func updateGame() {
        guard let motionService = motionService else { return }
        if motionService.isCameraObstructed {
            FlexaLog.game.warning("🚨 [ArmRaises] Camera obstructed - pausing game tick")
            return
        }
        updateHandTracking()
        evaluateTargetHit()
        if completedPatterns >= 3 {
            FlexaLog.game.info("🎯 [ArmRaises] 3 patterns completed - stopping game")
            endGame()
        }
    }

    func updateHandTracking() {
        guard let motionService = motionService else {
            FlexaLog.game.debug("📍 [Constellation] No motion service available")
            return
        }
        
        // Ensure screen size is set
        if screenSize == .zero {
            screenSize = UIScreen.main.bounds.size
            FlexaLog.game.info("📍 [Constellation] Screen size initialized: \(self.screenSize.width)x\(self.screenSize.height)")
        }
        
        guard let keypoints = motionService.poseKeypoints else {
            FlexaLog.game.debug("📍 [Constellation] No pose keypoints available")
            handPosition = .zero
            return
        }

        let preferredSide = keypoints.phoneArm
        let confidenceThreshold: Float = 0.2
        
        var wrist: CGPoint?
        var wristConfidence: Float = 0
        
        // Try preferred side first
        if preferredSide == .left {
            if let leftWrist = keypoints.leftWrist, keypoints.leftWristConfidence > confidenceThreshold {
                wrist = leftWrist
                wristConfidence = keypoints.leftWristConfidence
            } else if let rightWrist = keypoints.rightWrist, keypoints.rightWristConfidence > confidenceThreshold {
                wrist = rightWrist
                wristConfidence = keypoints.rightWristConfidence
            }
        } else {
            if let rightWrist = keypoints.rightWrist, keypoints.rightWristConfidence > confidenceThreshold {
                wrist = rightWrist
                wristConfidence = keypoints.rightWristConfidence
            } else if let leftWrist = keypoints.leftWrist, keypoints.leftWristConfidence > confidenceThreshold {
                wrist = leftWrist
                wristConfidence = keypoints.leftWristConfidence
            }
        }

        guard let wristPoint = wrist else {
            FlexaLog.game.debug("📍 [Constellation] No wrist detected above confidence threshold")
            handPosition = .zero
            return
        }

        let cameraRes = motionService.cameraResolution
        let mapped = CoordinateMapper.mapVisionPointToScreen(wristPoint, cameraResolution: cameraRes, previewSize: screenSize, isPortrait: true, flipY: false)
        
        // Direct position update - no caching for responsive tracking
        handPosition = mapped

        let wristVector = SIMD3<Float>(Float(mapped.x), Float(mapped.y), 0)
        motionService.sparcService.addCameraMovement(position: wristVector, timestamp: Date().timeIntervalSince1970)
    }

    func evaluateTargetHit() {
        guard isGameActive, !currentPattern.isEmpty, handPosition != .zero else { return }

        let tolerance = targetHitTolerance()
        guard let (index, _) = nearestPatternPoint(to: handPosition, within: tolerance) else { 
            return 
        }

        let now = CACurrentMediaTime()
        
        if connectedPoints.isEmpty {
            if let lastIndex = lastDetectedPointIndex,
               lastIndex == index,
               now - lastDetectionTimestamp < 0.4 {
                return
            }
            lastDetectedPointIndex = index
            lastDetectionTimestamp = now

            handleCorrectHit(for: index)
            activeLineStartIndex = index
            activeLineEndIndex = nil
            return
        }

        if let startIdx = activeLineStartIndex,
           connectedPoints.contains(startIdx) {

            // Check if we're trying to close the loop (all vertices visited, touching first point)
            if connectedPoints.count == currentPattern.count && index == connectedPoints.first {
                if let lastIndex = lastDetectedPointIndex,
                   lastIndex == index,
                   now - lastDetectionTimestamp < 0.35 {
                    return
                }
                
                lastDetectedPointIndex = index
                lastDetectionTimestamp = now
                
                // Close the loop
                activeLineEndIndex = index
                handleCorrectHit(for: index, closingLoop: true)
                return
            }
            
            // Regular connection to a new unconnected point
            if !connectedPoints.contains(index) {
                if let lastIndex = lastDetectedPointIndex,
                   lastIndex == index,
                   now - lastDetectionTimestamp < 0.35 {
                    return
                }

                lastDetectedPointIndex = index
                lastDetectionTimestamp = now

                activeLineEndIndex = index
                handleCorrectHit(for: index)
                activeLineStartIndex = index
                activeLineEndIndex = nil
            }
        }
    }

    func handleCorrectHit(for index: Int, closingLoop: Bool = false) {
        let pattern = getConstellationPattern()
        
        // Validate connection using CameraRepDetector
        if !connectedPoints.isEmpty {
            let lastConnected = connectedPoints.last!
            let isValid = repDetector.validateConstellationConnection(
                from: lastConnected,
                to: index,
                pattern: pattern,
                connectedPoints: connectedPoints,
                totalPoints: currentPattern.count
            )
            
            if !isValid {
                showIncorrectFeedback = true
                wrongConnectionCount += 1
                scheduleIncorrectFeedbackHide()
                HapticFeedbackService.shared.errorHaptic()
                FlexaLog.game.warning("🚫 [Constellation] Invalid connection: from=\(lastConnected) to=\(index) pattern=\(self.currentPatternName)")
                
                // Reset progress for this constellation
                resetCurrentPattern()
                return
            }
        }
        
        wrongConnectionCount = 0
        clearIncorrectFeedback()
        HapticFeedbackService.shared.successHaptic()

        let alreadyConnected = connectedPoints.contains(index)
        var addedNewPoint = false
        
        if !alreadyConnected {
            connectedPoints.append(index)
            addedNewPoint = true
        } else if closingLoop,
                  let first = connectedPoints.first,
                  first == index,
                  connectedPoints.last != index {
            FlexaLog.game.debug("🎯 [Constellation] Closing loop by returning to start point")
            connectedPoints.append(index)
        }
        
        if addedNewPoint {
            score += 10
        }

        // Check if pattern is complete using CameraRepDetector
        let isComplete = repDetector.isConstellationComplete(
            pattern: pattern,
            connectedPoints: connectedPoints,
            totalPoints: currentPattern.count
        )
        
        if isComplete {
            FlexaLog.game.info("✅ [Constellation] \(self.currentPatternName) pattern completed - loop closed!")
            
            // Record ROM completion for this pattern
            if let motionService = motionService, let keypoints = motionService.poseKeypoints {
                var normalized = motionService.currentROM
                if normalized <= 0 {
                    let rawROM = keypoints.getArmpitROM(side: keypoints.phoneArm)
                    normalized = motionService.validateAndNormalizeROM(rawROM)
                }
                let minimumThreshold = motionService.getMinimumROMThreshold(for: .constellation)
                if normalized >= minimumThreshold {
                    motionService.recordCameraRepCompletion(rom: normalized)
                    FlexaLog.game.info("📊 [Constellation] Pattern ROM recorded: \(String(format: "%.1f", normalized))°")
                }
            }
            
            onPatternCompleted()
        }
    }
    
    func getConstellationPattern() -> CameraRepDetector.ConstellationPattern {
        switch currentPatternName {
        case "Triangle":
            return .triangle
        case "Square":
            return .rectangle
        case "Circle":
            return .circle
        default:
            return .triangle
        }
    }

    func nearestPatternPoint(to position: CGPoint, within tolerance: CGFloat) -> (Int, CGFloat)? {
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

    func targetHitTolerance() -> CGFloat {
        max(36, screenSize.width * 0.06)
    }

    func scheduleIncorrectFeedbackHide() {
        let token = UUID()
        incorrectFeedbackToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            guard self.incorrectFeedbackToken == token else { return }
            withAnimation {
                self.showIncorrectFeedback = false
            }
            self.incorrectFeedbackToken = nil
        }
    }

    func clearIncorrectFeedback() {
        incorrectFeedbackToken = nil
        if showIncorrectFeedback {
            withAnimation {
                showIncorrectFeedback = false
            }
        }
    }
    
    func onPatternCompleted() {
        completedPatterns += 1
        score += 100
        
        FlexaLog.game.info("🎯 [Constellation] Pattern \(self.completedPatterns) completed! Moving to next pattern...")
        
        if let motionService = motionService, let keypoints = motionService.poseKeypoints {
            var normalized = motionService.currentROM
            if normalized <= 0 {
                let rawROM = keypoints.getArmpitROM(side: keypoints.phoneArm)
                normalized = motionService.validateAndNormalizeROM(rawROM)
            }
            let minimumThreshold = motionService.getMinimumROMThreshold(for: .constellation)
            if normalized >= minimumThreshold {
                motionService.recordCameraRepCompletion(rom: normalized)
            }
        }
        
        HapticFeedbackService.shared.successHaptic()
        
        if completedPatterns >= 3 {
            FlexaLog.game.info("🎯 [Constellation] All 3 patterns completed! Ending game...")
            endGame()
            return
        }
        
        // Brief delay before showing next pattern for visual feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.generateNewPattern()
            FlexaLog.game.info("🎯 [Constellation] New pattern generated: \(self?.currentPatternName ?? "unknown")")
        }
    }
    
    func generateNewPattern() {
        currentPattern.removeAll()
        connectedPoints.removeAll()
        currentTargetIndex = 0
        wrongConnectionCount = 0
        lastDetectedPointIndex = nil
        lastDetectionTimestamp = 0
        activeLineStartIndex = nil
        activeLineEndIndex = nil
        clearIncorrectFeedback()
        
        // Ensure screen size is set
        if screenSize == .zero {
            screenSize = UIScreen.main.bounds.size
        }
        
        let centerX = screenSize.width / 2
        let centerY = screenSize.height / 2
        let patternSize: CGFloat = 120
        
        switch currentPatternName {
        case "Circle":
            let numPoints = 8
            currentPattern = (0..<numPoints).map { i in
                let angle = (Double(i) * 2.0 * .pi) / Double(numPoints)
                let x = centerX + patternSize * CGFloat(cos(angle))
                let y = centerY + patternSize * CGFloat(sin(angle))
                return CGPoint(x: x, y: y)
            }
            currentPatternName = "Triangle"
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
    
    func endGame() {
        isGameActive = false
        gameTimer?.invalidate()
        gameTimer = nil
        guard let motionService = motionService else { return }
        let snapshot = motionService.getFullSessionData(
            overrideExerciseType: GameType.constellationMaker.displayName,
            overrideScore: score
        )
        var sessionData = snapshot
        if sessionData.romHistory.isEmpty {
            sessionData.romHistory = motionService.romPerRepArray.filter { $0.isFinite }
        }
        if sessionData.sparcHistory.isEmpty {
            sessionData.sparcHistory = motionService.sparcHistoryArray.filter { $0.isFinite }
        }

    // Ensure session and camera are stopped and fully torn down before posting game end
    motionService.stopSession()
    motionService.stopCamera(tearDownCompletely: true)
    let userInfo = motionService.buildSessionNotificationPayload(from: sessionData)
    NotificationCenter.default.post(name: NSNotification.Name("ConstellationGameEnded"), object: nil, userInfo: userInfo)
    }

    func resetCurrentPattern() {
        FlexaLog.game.info("🔄 [Constellation] Resetting current pattern due to invalid connection")
        connectedPoints.removeAll()
        activeLineStartIndex = nil
        activeLineEndIndex = nil
        lastDetectedPointIndex = nil
        lastDetectionTimestamp = 0
        wrongConnectionCount = 0
    }
    
    func cleanup() {
        isGameActive = false
        gameTimer?.invalidate()
        gameTimer = nil
        
        // Explicitly stop camera and session
        motionService?.stopSession()
        motionService?.stopCamera(tearDownCompletely: true)
        
        incorrectFeedbackToken = nil
        showIncorrectFeedback = false
        wrongConnectionCount = 0
        lastDetectedPointIndex = nil
        lastDetectionTimestamp = 0
        
        currentPattern.removeAll()
        connectedPoints.removeAll()
        currentTargetIndex = 0
        handPosition = .zero
        
        completedPatterns = 0
        currentPatternName = "Triangle"
        
        FlexaLog.game.info("🧹 [Constellation] Cleanup complete - camera and session stopped")
    }
}
