import SwiftUI

struct SimplifiedConstellationGameView: View {
    @StateObject private var game = ConstellationGame()
    @EnvironmentObject var motionService: SimpleMotionService

    var body: some View {
        ZStack {
            CameraGameBackground()

            ForEach(Array(game.currentPattern.enumerated()), id: \.offset) { index, point in
                Circle()
                    .foregroundColor(game.connectedPoints.contains(index) ? Color.green : Color.white)
                    .overlay(
                        Circle()
                            .stroke(Color.cyan, lineWidth: game.connectedPoints.contains(index) ? 4 : 3)
                    )
                    .frame(width: 24, height: 24)
                    .position(point)
                    .scaleEffect(game.connectedPoints.contains(index) ? 1.3 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: game.connectedPoints)
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
            game.motionService = motionService
            game.setupGame()
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
    private var screenSize: CGSize = .zero

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
        guard let motionService = motionService else { return }
        if let wrist = motionService.poseKeypoints?.leftWrist {
            let mapped = CoordinateMapper.mapVisionPointToScreen(wrist, cameraResolution: motionService.cameraResolution, previewSize: screenSize)
            let alpha: CGFloat = 0.8
            handPosition = CGPoint(
                x: previousPosition == .zero ? mapped.x : (previousPosition.x * (1 - alpha) + mapped.x * alpha),
                y: previousPosition == .zero ? mapped.y : (previousPosition.y * (1 - alpha) + mapped.y * alpha)
            )
            previousPosition = handPosition
        } else {
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
        if !connectedPoints.isEmpty {
            let lastConnected = connectedPoints.last!
            
            if !isValidConnection(from: lastConnected, to: index) {
                showIncorrectFeedback = true
                wrongConnectionCount += 1
                scheduleIncorrectFeedbackHide()
                HapticFeedbackService.shared.errorHaptic()
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

        if connectedPoints.count >= currentPattern.count {
            if currentPatternName == "Triangle" && connectedPoints.last != connectedPoints.first {
                // Special case for triangle, it must be a closed loop
                if connectedPoints.count == 3 {
                    let firstPoint = currentPattern[connectedPoints.first!]
                    let lastPoint = currentPattern[connectedPoints.last!]
                    let distance = hypot(firstPoint.x - lastPoint.x, firstPoint.y - lastPoint.y)
                    if distance > targetHitTolerance() * 2 {
                        return
                    }
                }
            }
            onPatternCompleted()
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
    
    func isValidConnection(from: Int, to: Int) -> Bool {
        switch currentPatternName {
        case "Triangle":
            return from != to && !connectedPoints.contains(to)
            
        case "Square":
            let diff = abs(from - to)
            if diff == 1 || diff == 3 {
                return true
            } else {
                return false
            }
            
        case "Circle":
            let numPoints = currentPattern.count
            let diff = abs(from - to)
            
            if diff == 1 || diff == numPoints - 1 {
                return true
            } else {
                return false
            }
            
        default:
            return true
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
