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
    @State private var showingAnalyzing = false
    @State private var showingResults = false
    @State private var sessionData: ExerciseSessionData?
    @State private var allowLocalCovers: Bool = true
    @State private var gameHasEnded: Bool = false
    
    var body: some View {
        if !calibrationCheck.isCalibrated {
            CalibrationRequiredView()
                .environmentObject(calibrationCheck)
        } else {
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
                            Text("\(3 - (gameScene?.bombsHit ?? 0))")
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
                    if !isHosted {
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
    
    private func setupGame() {
        FlexaLog.motion.info("🎮 [FruitSlicer] Setting up game - motionService active: \(motionService.isSessionActive), ARKit running: \(motionService.isARKitRunning)")
        // ROM tracking mode automatically determined by SimpleMotionService based on game type
        motionService.startGameSession(gameType: .fruitSlicer)
        
        let scene = FruitSlicerScene()
        scene.size = CGSize(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
        scene.scaleMode = .resizeFill
        scene.motionService = motionService
        scene.physicsWorld.gravity = CGVector(dx: 0, dy: -4.9) // Reduced gravity
        self.gameScene = scene
        self.isGameActive = true
        FlexaLog.motion.info("✅ [FruitSlicer] Game setup completed - scene created, motionService started")
    }
    
    private func cleanup() {
        FlexaLog.motion.info("🎮 [FruitSlicer] Starting cleanup - motionService active: \(motionService.isSessionActive), ARKit running: \(motionService.isARKitRunning)")
        isGameActive = false
        
        // Re-enable idle timer (allow screen to sleep)
        UIApplication.shared.isIdleTimerDisabled = false
        
        // Clean up scene resources
        if let scene = gameScene {
            scene.removeAllActions()
            scene.removeAllChildren()
            scene.physicsWorld.contactDelegate = nil
        }
        gameScene = nil
        
        // Remove notification observers
        NotificationCenter.default.removeObserver(self)
        
        FlexaLog.motion.info("🛑 [FruitSlicer] Cleanup completed - scene destroyed, observers removed")
    }
}

class FruitSlicerScene: SKScene, SKPhysicsContactDelegate {
    var motionService: SimpleMotionService?
    var isGameActive = false
    var bombsHit = 0
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
    private var imuRetryCount = 0
    private let imuMaxRetries = 30
    
    // Direction-change rep detection
    private var lastPendulumDirection: Int = 0  // -1 (backward), 0 (neutral), 1 (forward)
    private var lastDirectionChangeTime: TimeInterval = 0
    private let repCooldown: TimeInterval = 0.3  // Minimum time between reps (300ms)
    
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
        
        // Setup IMU motion tracking
        setupIMUMotionTracking()
        
        // Create slicer visual element
        createSlicer()
        
        // Set game as active to enable fruit spawning
        isGameActive = true
        
        // Reset direction tracking for rep detection
        lastPendulumDirection = 0
        lastDirectionChangeTime = 0
        pendulumVelocity = 0.0
        
        // Start spawning fruits with shorter intervals for more action
        let spawnAction = SKAction.sequence([
            SKAction.wait(forDuration: 1.2), // Reduced for faster spawning
            SKAction.run(spawnFruit)
        ])
        run(SKAction.repeatForever(spawnAction))
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
        slicer.physicsBody?.categoryBitMask = 4 // Slicer category
        slicer.physicsBody?.contactTestBitMask = 1 | 2 // Contact with fruit and bombs
        slicer.physicsBody?.collisionBitMask = 0
        slicer.physicsBody?.isDynamic = false
        
        addChild(slicer)
    }
    
    override func update(_ currentTime: TimeInterval) {
        frameCount += 1
        lastUpdateTime = currentTime
        // Update slicer position from IMU motion
        updateSlicerFromIMU()
    }
    
    // MARK: - SKPhysicsContactDelegate
    
    func didBegin(_ contact: SKPhysicsContact) {
        let contactMask = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        
        // Check if slicer (4) contacted fruit (1) or bomb (2)
        if contactMask == 5 { // Slicer + Fruit
            let fruit = contact.bodyA.categoryBitMask == 1 ? contact.bodyA.node : contact.bodyB.node
            if let fruitNode = fruit {
                // Create slice effect
                createSliceEffect(at: fruitNode.position, isGood: true)
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
                // Create explosion effect
                createSliceEffect(at: bombNode.position, isGood: false)
                bombNode.removeFromParent()
                bombsHit += 1
                
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
                    endGame()
                }
            }
        }
    }
    
    private func createSliceEffect(at position: CGPoint, isGood: Bool) {
        // Simple visual feedback - no particle effects
        // Just a brief color flash on the slicer handled in didBegin contact
    }
    
    private func spawnFruit() {
        guard isGameActive else { return }
        
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
        sprite.physicsBody?.categoryBitMask = sprite.name == "bomb" ? 2 : 1 // Different categories for fruit vs bomb
        sprite.physicsBody?.contactTestBitMask = 4 // Contact with slicer
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
        
        // Remove after 4 seconds to reduce memory usage
        let removeAction = SKAction.sequence([
            SKAction.wait(forDuration: 4.0),
            SKAction.removeFromParent()
        ])
        sprite.run(removeAction)
    }
    
    
    private func setupIMUMotionTracking() {
        // Use the shared motion service instead of creating our own CMMotionManager
        guard let motionService = motionService,
              let manager = motionService.motionManager,
              manager.isDeviceMotionAvailable else {
            if imuRetryCount < imuMaxRetries {
                imuRetryCount += 1
                if imuRetryCount % 5 == 0 {
                    print("⌛ [FruitSlicer] Waiting for CoreMotion manager (retry \(imuRetryCount)/\(imuMaxRetries))…")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    self?.setupIMUMotionTracking()
                }
            } else {
                print("❌ [FruitSlicer] Device motion not available or motion service not set — giving up")
            }
            return
        }
        
        // Wait a moment for initial readings to stabilize, then capture reference
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let motion = manager.deviceMotion {
                self.initialGravityVector = motion.gravity
                self.initialPitch = motion.attitude.pitch
                self.initialRoll = motion.attitude.roll
                print("✅ [FruitSlicer] IMU calibrated with reference gravity: y=\(motion.gravity.y)")
            }
        }
        
        print("✅ [FruitSlicer] Using shared motion service for IMU tracking")
    }
    
    private func updateSlicerFromIMU() {
        // Get motion data from the shared motion service with better error handling
        guard let motionService = motionService,
              let manager = motionService.motionManager else {
            // Motion service not yet ready — retry setup
            if imuRetryCount < imuMaxRetries {
                imuRetryCount += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    self?.setupIMUMotionTracking()
                }
            }
            return
        }
        
        guard let motion = manager.deviceMotion else {
            // No motion data available - motion might have stopped, try to restart
            if !manager.isDeviceMotionActive && manager.isDeviceMotionAvailable {
                manager.startDeviceMotionUpdates()
            }
            return
        }
        
        // Initialize reference gravity vector on first reading
        if initialGravityVector == nil {
            initialGravityVector = motion.gravity
            initialPitch = motion.attitude.pitch
            initialRoll = motion.attitude.roll
            print("✅ [FruitSlicer] IMU initialized with gravity reference")
            return
        }
        
        updateSlicerPosition(with: motion)
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
        pendulumVelocity += upDownAccel * deltaTime
        
        // Apply damping to prevent runaway velocity
        pendulumVelocity *= 0.95
        
        // Detect direction change for rep counting
        detectDirectionChangeRep(acceleration: upDownAccel)
        
        // Map velocity to screen position
        let screenHeight = size.height
        let padding: CGFloat = 100
        let availableHeight = screenHeight - (2 * padding)
        
        // MUCH MORE SENSITIVE: how much velocity for full screen travel
        let maxVelocity: Double = 0.3 // Much more sensitive - smaller value = more movement
        
        // Calculate movement ratio (-1 to 1)
        // Positive velocity (forward swing) -> UP on screen
        let movementRatio = CGFloat(pendulumVelocity / maxVelocity)
        let clampedRatio = max(-1.0, min(1.0, movementRatio))
        
        // Calculate target Y position - MUCH MORE DRAMATIC MOVEMENT
        // Forward swing = higher Y (slicer moves up)
        let targetY = slicerBaseY + clampedRatio * (availableHeight * 0.8) // Use 80% of available height
        
        // Apply bounds
        let minY = padding
        let maxY = screenHeight - padding
        let finalY = max(minY, min(maxY, targetY))
        
        // Smooth interpolation for fluid movement
        let currentSlicerY = slicer.position.y
        let smoothingFactor: CGFloat = 0.3 // Responsive for pendulum
        let interpolatedY = currentSlicerY + (finalY - currentSlicerY) * smoothingFactor
        
        // Update slicer position
        slicer.position = CGPoint(x: size.width / 2, y: interpolatedY)
        
    }
    
    private func detectDirectionChangeRep(acceleration: Double) {
        // Determine current direction: 1 (forward/positive), -1 (backward/negative)
        let currentDirection: Int = acceleration > 0.05 ? 1 : (acceleration < -0.05 ? -1 : lastPendulumDirection)
        
        // Skip if direction is neutral or hasn't changed
        guard currentDirection != 0 && lastPendulumDirection != 0 && lastPendulumDirection != currentDirection else {
            // Initialize or neutral state
            if lastPendulumDirection == 0 && currentDirection != 0 {
                lastPendulumDirection = currentDirection
            }
            return
        }
        
        // Check cooldown to avoid multiple reps in quick succession
        let currentTime = CACurrentMediaTime()
        guard currentTime - lastDirectionChangeTime >= repCooldown else {
            return
        }
        
        // Direction change detected!
        lastPendulumDirection = currentDirection
        lastDirectionChangeTime = currentTime
        
        // Record the rep with motion service
        recordRepForFruitSlicer()
    }
    
    private func recordRepForFruitSlicer() {
        guard let motionService = motionService else { return }
        
        // Complete the rep with ARKit-based ROM (from HandheldROMCalculator)
        motionService.completeHandheldRep()
        
        // Get the ARKit-based ROM that was just calculated (NOT IMU-based)
        let arkitROM = motionService.getLastHandheldRepROM()
        let minimumThreshold = motionService.getMinimumROMThreshold(for: .fruitSlicer)
        
        // Only count as rep if ROM meets threshold
        if arkitROM >= minimumThreshold {
            motionService.addRomPerRep(arkitROM)
            FlexaLog.game.info("🍎 [FruitSlicer] Rep from direction change | ROM: \(String(format: "%.1f", arkitROM))° (threshold: \(String(format: "%.1f", minimumThreshold))°) | Reps: \(motionService.romPerRepCount)")
        }
    }

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
        guard let dm = motionService?.motionManager?.deviceMotion else { return }
        initialGravityVector = dm.gravity
        initialPitch = dm.attitude.pitch
        initialRoll = dm.attitude.roll
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
        isGameActive = false
        
        // Clean up all scene resources immediately
        removeAllActions()
        removeAllChildren()
        physicsWorld.contactDelegate = nil
        
        // Stop IMU motion tracking
        motionService?.motionManager?.stopDeviceMotionUpdates()
        print("🛑 [FruitSlicer] IMU motion tracking stopped and scene cleaned up")
        
        // Build rich payload for CleanGameHostView consumers
        if let ms = motionService {
            let data = ms.getFullSessionData(
                overrideExerciseType: GameType.fruitSlicer.displayName,
                overrideScore: score
            )
            ms.stopSession()

            let userInfo = ms.buildSessionNotificationPayload(from: data)
            print("📣 [FruitSlicer] Posting game end with payload → score=\(data.score), reps=\(data.reps), maxROM=\(String(format: "%.1f", data.maxROM))°, SPARC=\(String(format: "%.2f", data.sparcScore))")
            NotificationCenter.default.post(name: NSNotification.Name("FruitSlicerGameEnded"), object: nil, userInfo: userInfo)
        } else {
            print("📣 [FruitSlicer] Posting game end without payload (no motionService)")
            NotificationCenter.default.post(name: NSNotification.Name("FruitSlicerGameEnded"), object: nil)
        }
    }
}
