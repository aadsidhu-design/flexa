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
    private var previousPosition: CGPoint = .zero
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
        
        // Prefer the wrist on the phone-side (phoneArm), fall back to any visible wrist
        if let keypoints = motionService.poseKeypoints {
            let preferredSide = keypoints.phoneArm
            let wristPoint = preferredSide == .left ? keypoints.leftWrist : keypoints.rightWrist
            var wrist = wristPoint
            // Fallback: if preferred side not visible, try the other side
            if wrist == nil {
                wrist = preferredSide == .left ? keypoints.rightWrist : keypoints.leftWrist
            }
            if let wrist = wrist {
            let cameraRes = motionService.cameraResolution
            FlexaLog.game.debug("📍 [Constellation] Raw wrist: (\(String(format: "%.4f", wrist.x)), \(String(format: "%.4f", wrist.y))) | Camera: \(cameraRes.width)x\(cameraRes.height) | Screen: \(self.screenSize.width)x\(self.screenSize.height)")
            
            // Map vision point to screen; no vertical flip required (MediaPipe provides top-left origin)
            let mapped = CoordinateMapper.mapVisionPointToScreen(wrist, cameraResolution: cameraRes, previewSize: screenSize, isPortrait: true, flipY: false)
            FlexaLog.game.debug("📍 [Constellation] Mapped wrist: (\(String(format: "%.1f", mapped.x)), \(String(format: "%.1f", mapped.y)))")
            
            let alpha: CGFloat = 0.8
            handPosition = CGPoint(
                x: previousPosition == .zero ? mapped.x : (previousPosition.x * (1 - alpha) + mapped.x * alpha),
                y: previousPosition == .zero ? mapped.y : (previousPosition.y * (1 - alpha) + mapped.y * alpha)
            )
            previousPosition = handPosition
            
            FlexaLog.game.debug("📍 [Constellation] Final hand position: (\(String(format: "%.1f", self.handPosition.x)), \(String(format: "%.1f", self.handPosition.y)))")
            } else {
                FlexaLog.game.debug("📍 [Constellation] No wrist detected in pose keypoints")
                handPosition = .zero
            }
        } else {
            FlexaLog.game.debug("📍 [Constellation] No pose keypoints available")
            handPosition = .zero
        }
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
           connectedPoints.contains(startIdx),
           !connectedPoints.contains(index) {

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
        } else if connectedPoints.count == currentPattern.count - 1 && index == connectedPoints.first {
            // Closing the loop for triangle
            handleCorrectHit(for: index)
        }
    }

    func handleCorrectHit(for index: Int) {
        // Validate connection using CameraRepDetector
        if !connectedPoints.isEmpty {
            let lastConnected = connectedPoints.last!
            let pattern = getConstellationPattern()
            
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
                connectedPoints.removeAll()
                activeLineStartIndex = nil
                activeLineEndIndex = nil
                return
            }
        }
        
        wrongConnectionCount = 0
        clearIncorrectFeedback()
        HapticFeedbackService.shared.successHaptic()

        if !connectedPoints.contains(index) {
            connectedPoints.append(index)
            
            if connectedPoints.count > 1 {
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
            }
            
            score += 10
        }

        // Check if pattern is complete using CameraRepDetector
        let pattern = getConstellationPattern()
        let isComplete = repDetector.isConstellationComplete(
            pattern: pattern,
            connectedPoints: connectedPoints,
            totalPoints: currentPattern.count
        )
        
        if isComplete {
            FlexaLog.game.info("✅ [Constellation] \(self.currentPatternName) pattern completed")
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
        
        if completedPatterns >= 3 {
            endGame()
            return
        }
        
        generateNewPattern()
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

        motionService.stopSession()
        let userInfo = motionService.buildSessionNotificationPayload(from: sessionData)
        NotificationCenter.default.post(name: NSNotification.Name("ConstellationGameEnded"), object: nil, userInfo: userInfo)

        NavigationCoordinator.shared.showAnalyzing(sessionData: sessionData)
    }

    func cleanup() {
        isGameActive = false
        motionService?.stopSession()
        gameTimer?.invalidate()
        gameTimer = nil
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
    }
}
