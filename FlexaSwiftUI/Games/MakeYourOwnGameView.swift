import SwiftUI
import CoreMotion

struct MakeYourOwnGameView: View {
    @Binding var score: Int
    @Binding var reps: Int
    @Binding var rom: Double
    @Binding var isActive: Bool
    var isHosted: Bool = false
    
    @EnvironmentObject var motionService: SimpleMotionService
    @EnvironmentObject var backendService: BackendService
    @StateObject private var calibrationCheck = CalibrationCheckService.shared
    
    // Configuration options
    @State private var selectedHours: Int = 0
    @State private var selectedMinutes: Int = 0
    @State private var selectedSeconds: Int = 0
    @State private var selectedMode: ExerciseMode = .handheld
    @State private var selectedJoint: CameraJoint = .elbow
    @State private var showingConfiguration = true
    
    // Game state
    @State private var isGameActive = false
    @State private var gameTime: TimeInterval = 0
    @State private var sessionData: ExerciseSessionData?
    @State private var showingAnalyzing = false
    @State private var showingResults = false
    @State private var gameTimer: Timer?
    
    enum ExerciseMode: String, CaseIterable {
        case handheld = "Handheld"
        case camera = "Camera"
    }
    
    enum CameraJoint: String, CaseIterable {
        case elbow = "Elbow"
        case armpit = "Armpit"
    }
    
    var body: some View {
        if !calibrationCheck.isCalibrated {
            CalibrationRequiredView()
        } else if showingConfiguration {
            // Configuration screen
            VStack(spacing: 30) {
                Text("Make Your Own Exercise")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                VStack(spacing: 20) {
                    // Duration selection
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Duration")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            // Apple-style time picker
                            HStack(spacing: 0) {
                                // Hours
                                Picker("Hours", selection: $selectedHours) {
                                    ForEach(0..<24, id: \.self) { hour in
                                        Text("\(hour)").tag(hour)
                                    }
                                }
                                .pickerStyle(WheelPickerStyle())
                                .frame(width: 80)
                                
                                Text("h")
                                    .foregroundColor(.white)
                                    .font(.title2)
                                    .padding(.horizontal, 5)
                                
                                // Minutes
                                Picker("Minutes", selection: $selectedMinutes) {
                                    ForEach(0..<60, id: \.self) { minute in
                                        Text("\(minute)").tag(minute)
                                    }
                                }
                                .pickerStyle(WheelPickerStyle())
                                .frame(width: 80)
                                
                                Text("m")
                                    .foregroundColor(.white)
                                    .font(.title2)
                                    .padding(.horizontal, 5)
                                
                                // Seconds
                                Picker("Seconds", selection: $selectedSeconds) {
                                    ForEach(0..<60, id: \.self) { second in
                                        Text("\(second)").tag(second)
                                    }
                                }
                                .pickerStyle(WheelPickerStyle())
                                .frame(width: 80)
                                
                                Text("s")
                                    .foregroundColor(.white)
                                    .font(.title2)
                                .padding(.horizontal, 5)
                            }
                            .frame(height: 120)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(10)
                        }
                    
                    // Mode selection
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Exercise Mode")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Picker("Mode", selection: $selectedMode) {
                            ForEach(ExerciseMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                    
                    // Joint selection (only for camera mode)
                    if selectedMode == .camera {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Track Joint")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            Picker("Joint", selection: $selectedJoint) {
                                ForEach(CameraJoint.allCases, id: \.self) { joint in
                                    Text(joint.rawValue).tag(joint)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(15)
                
                Button("Start Exercise") {
                    startExercise()
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .background(Color.blue)
                .cornerRadius(10)
            }
            .padding()
            .background(Color.black.ignoresSafeArea())
        } else {
            // Game view
            ZStack {
                Color.black.ignoresSafeArea()
                
                if isGameActive {
                    if selectedMode == .camera {
                        // Camera mode - only timer and camera preview
                        ZStack {
                            // Full screen camera with skeleton
                            CameraExerciseView(
                                joint: selectedJoint,
                                duration: getTotalDurationInSeconds()
                            )
                            
                            // Timer overlay at top
                            VStack {
                                Text(formatTimeRemaining())
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(Color.black.opacity(0.6))
                                    .cornerRadius(12)
                                
                                Spacer()
                            }
                            .padding(.top, 50)
                        }
                    } else {
                        // Handheld mode - show countdown circle
                        HandheldExerciseView(
                            totalDuration: TimeInterval(getTotalDurationInSeconds()),
                            currentTime: gameTime
                        )
                    }
                } else {
                    // Waiting to start
                    VStack(spacing: 20) {
                        Text("Ready to Start")
                            .font(.title)
                            .foregroundColor(.white)
                        
                        Text("\(formatTotalDuration()) • \(selectedMode.rawValue) • \(selectedMode == .camera ? selectedJoint.rawValue : "Phone Motion")")
                            .font(.body)
                            .foregroundColor(.gray)
                    }
                }
            }
            .onAppear {
                setupGame()
            }
            .onDisappear {
                cleanup()
            }
            .fullScreenCover(isPresented: $showingAnalyzing) {
                if let sessionData = sessionData {
                    AnalyzingView(sessionData: sessionData)
                        .environmentObject(NavigationCoordinator.shared)
                        .onDisappear {
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
        }
    }
    
    private func setupGame() {
        print("🎯 [MakeYourOwn] Setting up game")
        
        // Determine appropriate game type based on selected mode for consistent ROM calculation
        let gameType: SimpleMotionService.GameType = selectedMode == .camera ? .camera : .makeYourOwn
        
        // ROM tracking mode automatically determined by SimpleMotionService based on game type
        motionService.startGameSession(gameType: gameType)
        
        // Set camera joint preference for Vision ROM (only applies to camera mode)
        if selectedMode == .camera {
            motionService.preferredCameraJoint = (selectedJoint == .elbow) ? .elbow : .armpit
            print("👁️ [MakeYourOwn] Camera joint preference set to \(selectedJoint == .elbow ? "ELBOW" : "ARMPIT")")
            print("📱 [ROM Consistency] MakeYourOwn camera mode using Vision-only ROM calculation")
        } else {
            print("📱 [ROM Consistency] MakeYourOwn handheld mode using ARKit-only ROM calculation")
        }
    }
    
    private func startExercise() {
        let totalDuration = getTotalDurationInSeconds()
        print("🎯 [MakeYourOwn] Starting exercise - \(totalDuration)s, \(selectedMode.rawValue)")
        showingConfiguration = false
        isGameActive = true
        gameTime = 0
        
        // Start game timer
        startGameTimer()
    }
    
    private func startGameTimer() {
        gameTimer?.invalidate()
        gameTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { timer in
            if !isGameActive {
                timer.invalidate()
                return
            }
            
            gameTime += 1.0/60.0
            
            // Check if time is up
            if gameTime >= Double(getTotalDurationInSeconds()) {
                endExercise()
                timer.invalidate()
            }
        }
    }
    
    private func endExercise() {
        print("🎯 [MakeYourOwn] Exercise ended")
        isGameActive = false
        
        // Stop motion service and get full session data
        motionService.stopSession()
        let data = motionService.getFullSessionData()
        
        // Create session data using the motion service's comprehensive data
        let sessionData = ExerciseSessionData(
            exerciseType: "Make Your Own (\(selectedMode.rawValue))",
            score: data.score,
            reps: data.reps,
            maxROM: data.maxROM,
            duration: gameTime,
            timestamp: Date(),
            romHistory: data.romHistory,
            repTimestamps: data.repTimestamps,
            sparcHistory: data.sparcHistory,
            sparcScore: data.sparcScore
        )
        FlexaLog.game.info("🧩 [MakeYourOwn] Session stats → reps=\(sessionData.reps), maxROM=\(String(format: "%.1f", sessionData.maxROM))°, SPARC=\(String(format: "%.2f", sessionData.sparcScore)), romPerRep=\(sessionData.romHistory.count), sparcHistory=\(sessionData.sparcHistory.count)")
        print("🧩 [MakeYourOwn] Session stats → reps=\(sessionData.reps), maxROM=\(String(format: "%.1f", sessionData.maxROM))°, SPARC=\(String(format: "%.2f", sessionData.sparcScore)), romPerRep=\(sessionData.romHistory.count), sparcHistory=\(sessionData.sparcHistory.count)")
        
        self.sessionData = sessionData
        NavigationCoordinator.shared.showAnalyzing(sessionData: data)
        
        // Update bindings
        score = data.score
        reps = data.reps
        rom = data.maxROM
        isActive = false
    }
    
    private func cleanup() {
        print("🎯 [MakeYourOwn] Cleaning up")
        gameTimer?.invalidate()
        gameTimer = nil
        motionService.stopSession()
        isActive = false
    }
    
    // MARK: - Helper Functions
    
    private func getTotalDurationInSeconds() -> Int {
        return selectedHours * 3600 + selectedMinutes * 60 + selectedSeconds
    }
    
    private func formatTotalDuration() -> String {
        let total = getTotalDurationInSeconds()
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m \(seconds)s"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
    
    private func formatTimeRemaining() -> String {
        let total = getTotalDurationInSeconds()
        let remaining = max(0, total - Int(gameTime))
        
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        let seconds = remaining % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        } else {
            return "\(seconds)s"
        }
    }
}

struct CameraExerciseView: View {
    let joint: MakeYourOwnGameView.CameraJoint
    let duration: Int
    
    @EnvironmentObject var motionService: SimpleMotionService
    @State private var motionTimer: Timer?
    @State private var handCursor: CGPoint = CGPoint(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY)
    
    var body: some View {
        ZStack {
            // Full screen camera preview with skeleton overlay
            LiveCameraView()
                .environmentObject(motionService)
                .ignoresSafeArea()

            // Small hand cursor for MakeYourOwn camera mode to match handheld parity
            Circle()
                .fill(Color.orange.opacity(0.9))
                .frame(width: 18, height: 18)
                .position(handCursor)
                .shadow(radius: 6)
        }
        .onAppear {
            startMotionTracking()
        }
        .onDisappear {
            stopMotionTracking()
        }
    }
    
    private func startMotionTracking() {
        // Start tracking motion for ROM per rep analysis (for camera mode)
        motionTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { _ in
            trackCameraMotionForReps()
        }
    }
    
    private func stopMotionTracking() {
        motionTimer?.invalidate()
        motionTimer = nil
    }
    
    private func trackCameraMotionForReps() {
        // For camera mode, the motion service should already be receiving pose data
        // from the Vision framework through the LiveCameraWithSkeletonView
        // Rep detection is handled by the standard ROM calculation system
        guard let keypoints = motionService.poseKeypoints else { return }
        let activeSide = keypoints.phoneArm
        let wrist = (activeSide == .left) ? keypoints.leftWrist : keypoints.rightWrist
        if let w = wrist {
            let mapped = CoordinateMapper.mapVisionPointToScreen(w)
            // smooth cursor movement
            let alpha: CGFloat = 0.35
            handCursor = CGPoint(x: handCursor.x * (1 - alpha) + mapped.x * alpha,
                                 y: handCursor.y * (1 - alpha) + mapped.y * alpha)
            // Feed SPARC with mapped preview coords for MakeYourOwn camera mode
            motionService.sparcService.addVisionMovement(timestamp: Date().timeIntervalSince1970, position: mapped)
        }
    }
}

struct HandheldExerciseView: View {
    @EnvironmentObject var motionService: SimpleMotionService
    let totalDuration: TimeInterval
    let currentTime: TimeInterval
    
    @State private var cursorPosition = CGPoint(x: 200, y: 400)
    @State private var targetCirclePosition = CGPoint(x: 200, y: 400)
    @State private var targetCircleAngle: Double = 0
    @State private var targetCircleRadius: CGFloat = 80
    @State private var animationTimer: Timer?
    @State private var cursorTimer: Timer?
    
    private func formatTimeRemaining() -> String {
        let remaining = totalDuration - currentTime
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    var body: some View {
        ZStack {
            // Black background
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Time display at top
                Text(formatTimeRemaining())
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding()
                
                Spacer()
                
                // Game area with cursor and moving circle
                ZStack {
                    // Moving target circle
                    Circle()
                        .stroke(Color.cyan, lineWidth: 3)
                        .frame(width: targetCircleRadius * 2, height: targetCircleRadius * 2)
                        .position(targetCirclePosition)
                        .animation(.easeInOut(duration: 0.1), value: targetCirclePosition)
                    
                    // User cursor (smaller)
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 20, height: 20)
                        .position(cursorPosition)
                        .animation(.easeInOut(duration: 0.1), value: cursorPosition)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                Spacer()
                
                // Instructions
                Text("Follow the circle with your phone")
                    .font(.body)
                    .foregroundColor(.gray)
                    .padding(.bottom, 50)
            }
        }
        .onAppear {
            startTargetCircleAnimation()
            startCursorTracking()
        }
        .onDisappear {
            stopAnimations()
        }
    }
    
    private func startTargetCircleAnimation() {
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            // Move target circle in a figure-8 pattern
            targetCircleAngle += 0.05
            
            let centerX = UIScreen.main.bounds.width / 2
            let centerY = UIScreen.main.bounds.height / 2
            
            // Figure-8 pattern
            let x = centerX + sin(targetCircleAngle) * 100
            let y = centerY + sin(targetCircleAngle * 2) * 60
            
            targetCirclePosition = CGPoint(x: x, y: y)
        }
    }
    
    private func startCursorTracking() {
        cursorTimer?.invalidate()
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { _ in
            updateCursorFromMotion()
        }
    }
    
    private func updateCursorFromMotion() {
        guard let motion = motionService.currentDeviceMotion else { return }
        
        // Use device pitch and roll for cursor movement (no tilt)
        let attitude = motion.attitude
        let pitch = attitude.pitch // Forward/backward tilt
        let roll = attitude.roll   // Left/right tilt
        
        let centerX = UIScreen.main.bounds.width / 2
        let centerY = UIScreen.main.bounds.height / 2
        let maxRange: CGFloat = 150
        
        // Map pitch and roll to screen position
        let normalizedPitch = -pitch / (Double.pi / 2) // -1 to +1 range
        let normalizedRoll = roll / (Double.pi / 2)    // -1 to +1 range
        
        let targetX = centerX + CGFloat(normalizedRoll) * maxRange
        let targetY = centerY + CGFloat(normalizedPitch) * maxRange
        
        // Apply screen bounds
        let padding: CGFloat = 50
        let clampedX = max(padding, min(UIScreen.main.bounds.width - padding, targetX))
        let clampedY = max(padding, min(UIScreen.main.bounds.height - padding, targetY))
        
        // Smooth movement
        let smoothing: CGFloat = 0.3
        cursorPosition.x = smoothing * clampedX + (1.0 - smoothing) * cursorPosition.x
        cursorPosition.y = smoothing * clampedY + (1.0 - smoothing) * cursorPosition.y
        
        // Track motion for ROM per rep analysis (for handheld mode)
        trackMotionForReps()
    }
    
    private func trackMotionForReps() {
        // For handheld mode, use ARKit position tracking if available
        guard let currentTransform = motionService.universal3DEngine.currentTransform else { return }
        
        let _ = SIMD3<Float>(
            currentTransform.columns.3.x,
            currentTransform.columns.3.y,
            currentTransform.columns.3.z
        )
        
        // Feed accelerometer data to SPARC service for smoothness calculation
        if let deviceMotion = motionService.motionManager?.deviceMotion {
            let acceleration = SIMD3<Float>(
                Float(deviceMotion.userAcceleration.x),
                Float(deviceMotion.userAcceleration.y),
                Float(deviceMotion.userAcceleration.z)
            )
            let velocity = SIMD3<Float>(0, 0, 0) // We don't have direct velocity
            motionService.sparcService.addMovement(timestamp: Date().timeIntervalSince1970, acceleration: acceleration, velocity: velocity)
        }
    }
    
    private func stopAnimations() {
        animationTimer?.invalidate()
        animationTimer = nil
        cursorTimer?.invalidate()
        cursorTimer = nil
    }
}

#Preview {
    MakeYourOwnGameView(
        score: .constant(0),
        reps: .constant(0),
        rom: .constant(0),
        isActive: .constant(false)
    )
    .environmentObject(SimpleMotionService.shared)
    .environmentObject(BackendService())
}
