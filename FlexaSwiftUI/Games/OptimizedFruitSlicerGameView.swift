import SwiftUI
import SpriteKit
import CoreMotion
import UIKit

struct OptimizedFruitSlicerGameView: View {
    @EnvironmentObject var motionService: SimpleMotionService
    @EnvironmentObject var backendService: BackendService
    @StateObject private var calibrationCheck = CalibrationCheckService.shared
    var isHosted: Bool = false
    @State private var gameScene: FruitSlicerScene?
    @State private var isGameActive = false
    @State private var bombsHitLocal: Int = 0
    @State private var showingAnalyzing = false
    @State private var showingResults = false
    @State private var sessionData: ExerciseSessionData?
    @State private var allowLocalCovers: Bool = true
    @State private var gameHasEnded: Bool = false
    
    @State private var motion: CMDeviceMotion? = nil

    var body: some View {
        if !calibrationCheck.isCalibrated {
            CalibrationRequiredView()
                .environmentObject(calibrationCheck)
        } else {
            TimelineView(.animation) { timeline in
                ZStack {
                    if let scene = gameScene {
                        SpriteView(scene: scene)
                            .ignoresSafeArea()
                            .background(Color.black)
                    }
                    
                    // Game UI overlay
                    VStack {
                        HStack {
                            // Bomb counter
                            VStack(spacing: 4) {
                                Text("💣")
                                    .font(.title)
                                    Text("\(bombsHitLocal)")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            }
                            .padding()
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(12)
                            .padding(.leading, 20)
                            .padding(.top, 60)
                            
                            Spacer()
                        }
                        
                        Spacer()
                    }
                    .zIndex(500)
                }
                // Listen for bombs changed notifications from the SpriteKit scene
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FruitSlicerBombsChanged"))) { note in
                    if let info = note.userInfo, let count = info["count"] as? Int {
                        // The scene now posts remaining bombs (0..3) as 'count'
                        self.bombsHitLocal = count
                    }
                }
                // Listen for scene ending (3 bombs hit)
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FruitSlicerSceneEnded"))) { note in
                    guard !gameHasEnded else { return }
                    
                    let finalScore = (note.userInfo?["score"] as? Int) ?? gameScene?.score ?? 0
                    
                    // Get session data from motion service
                    let exerciseSession = motionService.getFullSessionData(
                        overrideExerciseType: GameType.fruitSlicer.displayName,
                        overrideScore: finalScore
                    )
                    
                    // Build rich payload for CleanGameHostView
                    let userInfo = motionService.buildSessionNotificationPayload(from: exerciseSession)
                    FlexaLog.game.info("📣 [FruitSlicer] Posting game end → score=\(exerciseSession.score) reps=\(exerciseSession.reps) maxROM=\(String(format: "%.1f", exerciseSession.maxROM))° SPARC=\(String(format: "%.2f", exerciseSession.sparcScore))")
                    NotificationCenter.default.post(name: NSNotification.Name("FruitSlicerGameEnded"), object: nil, userInfo: userInfo)
                    
                    // Stop motion service
                    motionService.stopSession()
                    gameHasEnded = true
                }
                .onChange(of: timeline.date) { newDate in
                    self.motion = motionService.motionManager?.deviceMotion
                    if let motion = self.motion {
                        gameScene?.update(motion: motion)
                    }
                    // Forward ARKit transform to scene for ROM/rep processing
                    if let transform = motionService.currentARKitTransform {
                        let ts = Date().timeIntervalSince1970
                        gameScene?.receiveARKitTransform(transform, timestamp: ts)
                    }
                }
                .statusBarHidden()
                .toolbar(.hidden, for: .navigationBar)
                .onAppear {
                    // Keep screen on during game
                    UIApplication.shared.isIdleTimerDisabled = true
                    
                    if !isGameActive && !showingAnalyzing && !showingResults && !gameHasEnded {
                        setupGame()
                    }
                    NotificationCenter.default.addObserver(
                        forName: NSNotification.Name("FruitSlicerGameEnded"),
                        object: nil,
                        queue: .main
                    ) { notification in
                        let resolvedSession: ExerciseSessionData = {
                            guard
                                let payload = notification.userInfo,
                                let encoded = payload["sessionDataJSON"] as? Data
                            else {
                                return motionService.getFullSessionData(
                                    overrideExerciseType: GameType.fruitSlicer.displayName,
                                    overrideScore: self.gameScene?.score ?? self.motionService.currentReps * 10
                                )
                            }
                            let decoder = JSONDecoder()
                            decoder.dateDecodingStrategy = .millisecondsSince1970
                            if let decoded = try? decoder.decode(ExerciseSessionData.self, from: encoded) {
                                return decoded
                            }
                            return motionService.getFullSessionData(
                                overrideExerciseType: GameType.fruitSlicer.displayName,
                                overrideScore: self.gameScene?.score ?? self.motionService.currentReps * 10
                            )
                        }()

                        self.sessionData = resolvedSession
                        self.gameHasEnded = true
                        // Pause and tear down SpriteKit scene to ensure clean transition
                        if let scene = self.gameScene {
                            scene.isPaused = true
                            scene.removeAllActions()
                            scene.removeAllChildren()
                        }
                        self.gameScene = nil
                        if !self.isHosted {
                            NavigationCoordinator.shared.showAnalyzing(sessionData: resolvedSession)
                        }
                    }
                }
                .onDisappear {
                    cleanup()
                }
                .fullScreenCover(isPresented: $showingAnalyzing) {
                    if let sessionData = sessionData, allowLocalCovers {
                        AnalyzingView(sessionData: sessionData)
                            .environmentObject(NavigationCoordinator.shared)
                    }
                }
            }
        }
    }
    
    private func setupGame() {
        FlexaLog.motion.info("🎮 [FruitSlicer] Setting up game - motionService active: \(motionService.isSessionActive), ARKit running: \(motionService.isARKitRunning)")
        // ROM tracking mode automatically determined by SimpleMotionService based on game type
        motionService.startGameSession(gameType: .fruitSlicer)
        
        let scene = FruitSlicerScene(size: UIScreen.main.bounds.size)
        scene.scaleMode = .resizeFill
        scene.physicsWorld.gravity = CGVector(dx: 0, dy: -4.9) // Reduced gravity
        self.gameScene = scene
        self.isGameActive = true
        FlexaLog.motion.info("✅ [FruitSlicer] Game setup completed - scene created, motionService started")
    }
    
    private func cleanup() {
        FlexaLog.motion.info("🎮 [FruitSlicer] Starting cleanup - motionService active: \(motionService.isSessionActive), ARKit running: \(motionService.isARKitRunning)")
        isGameActive = false
        
        // Stop motion service
        motionService.stopSession()

        // Re-enable idle timer (allow screen to sleep)
        UIApplication.shared.isIdleTimerDisabled = false
        
        // Clean up scene resources
        if let scene = gameScene {
            scene.removeAllActions()
            scene.removeAllChildren()
            scene.physicsWorld.contactDelegate = nil
        }
        gameScene = nil
        // Reset local bombs counter
        bombsHitLocal = 0
        
        // Remove notification observers
        NotificationCenter.default.removeObserver(self)
        
        FlexaLog.motion.info("🛑 [FruitSlicer] Cleanup completed - scene destroyed, observers removed")
    }
}

class FruitSlicerScene: SKScene, SKPhysicsContactDelegate {
    var bombsHit = 0
    // Note: SwiftUI host listens for "FruitSlicerBombsChanged" notifications to update counters.
    var frameCount = 0
    var score = 0
    
    // IMU-based motion control
    private var initialGravityVector: CMAcceleration?
    private var initialPitch: Double?
    private var initialRoll: Double?
    private var slicerBaseY: CGFloat = 150
    private var pendulumVelocity: Double = 0.0
    private var lastUpdateTime: TimeInterval = 0
    private var currentOrientation: UIDeviceOrientation = UIDevice.current.orientation
    
    // Rep detection handled by HandheldRepDetector via ARKit position data
    
    // ARKit baseline / streaming support for ROM & rep calculations
    private var arBaseline3D: SIMD3<Float>? = nil
    private var lastARKitTimestamp: TimeInterval = 0

    /// Receive ARKit transform from the hosting view and forward 3D positions to handheld pipelines.
    /// This keeps IMU-driven slicer behavior intact while using ARKit positions for ROM/rep calculations.
    func receiveARKitTransform(_ transform: simd_float4x4, timestamp: TimeInterval) {
        // Simple rate limiting: don't forward more than 120 Hz
        let minInterval: TimeInterval = 1.0 / 120.0
        guard timestamp - lastARKitTimestamp >= minInterval else { return }
        lastARKitTimestamp = timestamp

        let pos = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)

        // Initialize baseline if needed
        if arBaseline3D == nil {
            arBaseline3D = pos
        }

        // Forward to shared calculators provided by SimpleMotionService to keep logic centralized
        DispatchQueue.main.async {
            let svc = SimpleMotionService.shared
            // Only forward when session active and not a camera exercise
            if svc.isSessionActive && !svc.isCameraExercise {
                let ts = Date().timeIntervalSince1970
                // Use the public ingestion API so we don't access private internals
                svc.ingestExternalHandheldPosition(pos, timestamp: ts)
            }
        }
    }
    
    override func didMove(to view: SKView) {
        backgroundColor = SKColor.black
        physicsBody = nil
        
        // Set up physics world delegate for collision detection
        physicsWorld.contactDelegate = self

        // Configure SKView for better performance and lower memory usage
        view.preferredFramesPerSecond = 60 // Reduced from 120 to save resources
        view.ignoresSiblingOrder = true
        view.shouldCullNonVisibleNodes = true // Enable culling for better performance
        // Observe device orientation changes so tilt works in any orientation
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(self, selector: #selector(handleOrientationChange), name: UIDevice.orientationDidChangeNotification, object: nil)
        currentOrientation = UIDevice.current.orientation
        
        // Create slicer visual element
        createSlicer()
        // Initialize bombs remaining (3 total) for SwiftUI host
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NSNotification.Name("FruitSlicerBombsChanged"), object: nil, userInfo: ["count": 3])
        }
        
        // Start spawning fruits. Slightly slower spawn to reduce chaos and CPU pressure
        // Use an explicit closure capture for spawnFruit so the action reliably calls the instance method
        let spawnSequence = SKAction.sequence([
            SKAction.wait(forDuration: 1.6), // Slightly slower spawn
            SKAction.run { [weak self] in self?.spawnFruit() }
        ])
        run(SKAction.repeatForever(spawnSequence), withKey: "spawnFruits")
    }
    
    override func willMove(from view: SKView) {
        NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        super.willMove(from: view)
    }
    
    private func createSlicer() {
        // Create a simple red circle slicer
        let slicer = SKShapeNode(circleOfRadius: 18)
        slicer.fillColor = .red
        slicer.strokeColor = .clear
        slicer.lineWidth = 0
        slicer.name = "slicer"
        slicer.zPosition = 10
        
        // Position slicer at middle of screen
        let centerY = size.height * 0.5
        slicer.position = CGPoint(x: size.width / 2, y: centerY)
        slicerBaseY = centerY // Store base position for IMU movement
        
    // Add physics body for collision detection
    slicer.physicsBody = SKPhysicsBody(circleOfRadius: 18)
    // Use explicit bit flags for clarity (fruit=1<<0, bomb=1<<1, slicer=1<<2)
    slicer.physicsBody?.categoryBitMask = UInt32(1 << 2) // Slicer category
    slicer.physicsBody?.contactTestBitMask = UInt32((1 << 0) | (1 << 1)) // Contact with fruit and bombs
        slicer.physicsBody?.collisionBitMask = 0
        slicer.physicsBody?.isDynamic = false
        
        addChild(slicer)
    }
    
    func update(motion: CMDeviceMotion) {
        frameCount += 1
        
        // Initialize reference gravity vector on first reading
        if initialGravityVector == nil {
            initialGravityVector = motion.gravity
            initialPitch = motion.attitude.pitch
            initialRoll = motion.attitude.roll
            print("✅ [FruitSlicer] IMU initialized with gravity reference")
        }
        
        updateSlicerPosition(with: motion)
    }

    // MARK: - SKPhysicsContactDelegate
    
    func didBegin(_ contact: SKPhysicsContact) {
        let contactMask = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        
        // Check if slicer (4) contacted fruit (1) or bomb (2)
        if contactMask == 5 { // Slicer + Fruit
            let fruit = contact.bodyA.categoryBitMask == 1 ? contact.bodyA.node : contact.bodyB.node
            if let fruitNode = fruit {
                // Logging for debugging spawn/despawn lifecycle
                FlexaLog.motion.info("🍓 [FruitSlicer] Fruit sliced at pos=\(String(describing: fruitNode.position)), node=\(String(describing: fruitNode.name))")

                // Create slice effect
                createSliceEffect(at: fruitNode.position, isGood: true)

                // Ensure any scheduled actions are removed before deleting node to avoid delayed re-adds
                fruitNode.removeAllActions()
                fruitNode.physicsBody = nil
                fruitNode.removeFromParent()
                score += 10

                // Brief slicer flash for feedback
                if let slicer = childNode(withName: "slicer") as? SKShapeNode {
                    let flashAction = SKAction.sequence([
                        SKAction.run { slicer.fillColor = .green },
                        SKAction.wait(forDuration: 0.1),
                        SKAction.run { slicer.fillColor = .red }
                    ])
                    slicer.run(flashAction)
                }
            }
        } else if contactMask == 6 { // Slicer + Bomb
            let bomb = contact.bodyA.categoryBitMask == 2 ? contact.bodyA.node : contact.bodyB.node
            if let bombNode = bomb {
                FlexaLog.motion.info("💣 [FruitSlicer] Bomb hit at pos=\(String(describing: bombNode.position))")
                // Create explosion effect
                createSliceEffect(at: bombNode.position, isGood: false)
                bombNode.removeAllActions()
                bombNode.physicsBody = nil
                bombNode.removeFromParent()
                bombsHit += 1
                // Clamp bombsHit to valid range
                bombsHit = max(0, min(3, bombsHit))
                // Compute remaining bombs (0..3) to report to UI
                let remaining = max(0, 3 - bombsHit)
                // Notify any SwiftUI host about remaining bombs
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: NSNotification.Name("FruitSlicerBombsChanged"), object: nil, userInfo: ["count": remaining])
                }

                // Slicer flash darker red for bomb hit
                if let slicer = childNode(withName: "slicer") as? SKShapeNode {
                    let flashAction = SKAction.sequence([
                        SKAction.run { slicer.fillColor = SKColor(red: 0.5, green: 0, blue: 0, alpha: 1) },
                        SKAction.wait(forDuration: 0.2),
                        SKAction.run { slicer.fillColor = .red }
                    ])
                    slicer.run(flashAction)
                }

                if bombsHit >= 3 {
                    // When we've hit the limit, post remaining=0 and end the game immediately
                    DispatchQueue.main.async { [weak self] in
                        NotificationCenter.default.post(name: NSNotification.Name("FruitSlicerBombsChanged"), object: nil, userInfo: ["count": 0])
                        // End game immediately - no delay needed
                        self?.endGame()
                    }
                }
            }
        }
    }
    
    private func createSliceEffect(at position: CGPoint, isGood: Bool) {
        // Simple visual feedback - no particle effects
        // Just a brief color flash on the slicer handled in didBegin contact
    }
    
    private func spawnFruit() {
        // Limit active fruit/bombs to prevent node overload and frame drops
        let activeProjectiles = children.filter { $0.name == "fruit" || $0.name == "bomb" }.count
        if activeProjectiles >= 20 { return }
        
        // Create fruit as visible colored circles
        let sprite: SKNode
        if Int.random(in: 1...100) <= 35 {
            // Bomb: emoji
            let bomb = SKLabelNode(text: "💣")
            bomb.fontSize = 40
            bomb.name = "bomb"
            sprite = bomb
        } else {
            // Fruit: random fruit emoji
            let fruitEmojis = ["🍎", "🍊", "🍌", "🍇", "🍓", "🥝", "🍑", "🍒"]
            let fruit = SKLabelNode(text: fruitEmojis.randomElement()!)
            fruit.fontSize = 40
            fruit.name = "fruit"
            sprite = fruit
        }
        
        // Spawn from left/right edge toward center to ensure middle crossing
        let spawnFromLeft = Bool.random()
        let spawnX: CGFloat = spawnFromLeft ? size.width * 0.1 : size.width * 0.9
        let spawnY: CGFloat = size.height * 0.12
        
        sprite.position = CGPoint(x: spawnX, y: spawnY)
        sprite.zPosition = 5
        
        // Physics with higher launch, less gravity effect
    sprite.physicsBody = SKPhysicsBody(circleOfRadius: 25)
        sprite.physicsBody?.usesPreciseCollisionDetection = false
        sprite.physicsBody?.allowsRotation = false
        sprite.physicsBody?.linearDamping = 0.1
        sprite.physicsBody?.angularDamping = 0.1
        sprite.physicsBody?.affectedByGravity = true
        sprite.physicsBody?.restitution = 0.2
        sprite.physicsBody?.mass = 2.0 // Heavier = less affected by gravity
    // Set explicit categories: fruit -> 1<<0, bomb -> 1<<1
    sprite.physicsBody?.categoryBitMask = sprite.name == "bomb" ? UInt32(1 << 1) : UInt32(1 << 0)
    sprite.physicsBody?.contactTestBitMask = UInt32(1 << 2) // Contact with slicer
        sprite.physicsBody?.collisionBitMask = 0
        sprite.physicsBody?.isDynamic = true
        
        // Launch toward center-middling area with adequate height and cross-screen travel
        let targetX: CGFloat = size.width * 0.5
        let targetY: CGFloat = size.height * 0.65
        let launchForce: CGFloat = CGFloat.random(in: 900...1100)
        
        let baseAngle = atan2(targetY - spawnY, targetX - spawnX)
        let angleVariation = CGFloat.random(in: -0.12...0.12)
        let finalAngle = baseAngle + angleVariation
        
        let velocity = CGVector(dx: cos(finalAngle) * launchForce, dy: sin(finalAngle) * launchForce)
        sprite.physicsBody?.velocity = velocity
        
        addChild(sprite)
        
        // Remove after 4 seconds to reduce memory usage — but fade out first so removal isn't abrupt
        let fadeDuration: TimeInterval = 0.35
        let lifeDuration: TimeInterval = 4.0
        let removeAction = SKAction.sequence([
            SKAction.wait(forDuration: lifeDuration - fadeDuration),
            SKAction.fadeAlpha(to: 0.0, duration: fadeDuration),
            SKAction.run { [weak sprite] in
                if let s = sprite {
                    FlexaLog.motion.debug("🍌 [FruitSlicer] Auto-despawning node name=\(String(describing: s.name)) pos=\(String(describing: s.position))")
                    s.removeAllActions()
                    s.physicsBody = nil
                    s.removeFromParent()
                }
            }
        ])
        sprite.run(removeAction)
    }
    
    private func updateSlicerPosition(with motion: CMDeviceMotion) {
        guard let slicer = childNode(withName: "slicer") else { return }
        
        // Use user acceleration (gravity-compensated) for up/down motion - orientation agnostic
        // Use Y-axis (up/down) acceleration for pendulum motion
        // Positive Y acceleration = slicer moves UP
        // Negative Y acceleration = slicer moves DOWN
        let upDownAccel = motion.userAcceleration.y
        
        // Integrate acceleration for velocity-based movement
        let deltaTime = 1.0 / 60.0 // Assuming 60Hz updates
        pendulumVelocity += upDownAccel * deltaTime * 2.5 // Increased multiplier for more responsive movement

        // Apply lighter damping for more dynamic motion
        pendulumVelocity *= 0.88 // Reduced from 0.92 for more movement
        
        // Map velocity to screen position
        let screenHeight = size.height
        let padding: CGFloat = 80 // Reduced padding for more vertical range
        let availableHeight = screenHeight - (2 * padding)
        
        // Sensitivity: how much velocity for full screen travel
        // Lower value = more movement per unit velocity
        let maxVelocity: Double = 0.45 // Reduced from 0.7 for more movement
        
        // Calculate movement ratio (-1 to 1)
        // Positive velocity (forward swing) -> UP on screen
        let movementRatio = CGFloat(pendulumVelocity / maxVelocity)
        let clampedRatio = max(-1.0, min(1.0, movementRatio))
        
        // Calculate target Y position - increased range for more dramatic movement
        // Forward swing = higher Y (slicer moves up)
        let targetY = slicerBaseY + clampedRatio * (availableHeight * 0.75) // Increased from 0.55 to 0.75
        
        // Apply bounds
        let minY = padding
        let maxY = screenHeight - padding
        let finalY = max(minY, min(maxY, targetY))
        
        // Reduced smoothing for more responsive movement
        let currentSlicerY = slicer.position.y
        let smoothingFactor: CGFloat = 0.35 // Increased from 0.22 for more responsive motion
        let interpolatedY = currentSlicerY + (finalY - currentSlicerY) * smoothingFactor
        
        // Update slicer position
        slicer.position = CGPoint(x: size.width / 2, y: interpolatedY)
    }
    
    // Direction-based rep counting is now handled by HandheldRepDetector
    // via ARKit position data forwarded through receiveARKitTransform
    // This ensures consistent rep detection across all handheld games

    // MARK: - Orientation Handling
    @objc private func handleOrientationChange() {
        let ori = UIDevice.current.orientation
        if isUsableOrientation(ori) {
            currentOrientation = ori
            recalibrateBaselineForCurrentOrientation()
            print("🔄 [FruitSlicer] Orientation changed → baseline recalibrated: \(ori.rawValue)")
        }
    }

    private func recalibrateBaselineForCurrentOrientation() {
        // This is now handled by the view
    }

    private func isUsableOrientation(_ o: UIDeviceOrientation) -> Bool {
        return o == .portrait || o == .portraitUpsideDown || o == .landscapeLeft || o == .landscapeRight
    }

    private func orientationAdjustedTiltDelta(_ motion: CMDeviceMotion) -> Double {
        let pitch = motion.attitude.pitch
        let roll = motion.attitude.roll
        let p0 = initialPitch ?? pitch
        let r0 = initialRoll ?? roll
        switch currentOrientation {
        case .portrait:
            return pitch - p0
        case .portraitUpsideDown:
            return -(pitch - p0)
        case .landscapeLeft:
            // In landscapeLeft, roll increases when tilting screen-top upward; invert to keep "up" positive
            return -(roll - r0)
        case .landscapeRight:
            return (roll - r0)
        default:
            return pitch - p0
        }
    }
    

    private func endGame() {
        // Scene posts notification with score - SwiftUI view will handle session data
        FlexaLog.game.info("💣 [FruitSlicer] Game ended - 3 bombs hit, score=\(self.score)")
        NotificationCenter.default.post(
            name: NSNotification.Name("FruitSlicerSceneEnded"),
            object: nil,
            userInfo: ["score": self.score]
        )
    }
}
