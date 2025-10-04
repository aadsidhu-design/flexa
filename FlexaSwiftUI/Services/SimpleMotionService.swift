import Foundation
import CoreMotion
import AVFoundation
import ARKit
import Combine
import simd
import UIKit

extension Notification.Name {
    static let SharedCaptureSessionReady = Notification.Name("SharedCaptureSessionReady")
}

// MARK:    // ROM tracking mode control Service
class SimpleMotionService: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    // MARK: - Singleton
    static let shared = SimpleMotionService()
    
    // MARK: - Published Properties
    @Published var currentROM: Double = 0
    @Published var maxROM: Double = 0
    @Published var currentReps: Int = 0
    @Published var lastRepROM: Double = 0
    @Published var isSessionActive: Bool = false
    @Published var isARKitRunning: Bool = false
    @Published var isCameraObstructed: Bool = false
    @Published var poseKeypoints: SimplifiedPoseKeypoints?
    @Published var cameraObstructionReason: String = ""
    @Published var isMovementTooFast: Bool = false
    @Published var romTrackingMode: String = "ARKit"
    // Camera joint preference for Vision ROM (portrait front camera)
    enum CameraJointPreference { case armpit, elbow }
    @Published var preferredCameraJoint: CameraJointPreference = .armpit
    @Published var fastMovementReason: String = ""
    @Published var currentPoseKeypoints: SimplifiedPoseKeypoints?
    @Published var providerHUD: String = ""
    
    // Current device motion for handheld games
    var currentDeviceMotion: CMDeviceMotion? {
        return motionManager?.deviceMotion
    }
    
    // MARK: - Session Tracking
    private var sparcHistory = BoundedArray<Double>(maxSize: 2000) // Increased for better accuracy
    private var romPerRep = BoundedArray<Double>(maxSize: 1000) // Increased for better accuracy
    private var romPerRepTimestamps = BoundedArray<TimeInterval>(maxSize: 1000)

    /// Public accessor for rep timestamps as Date objects
    var romPerRepTimestampsDates: [Date] {
        return romPerRepTimestamps.allElements.map { Date(timeIntervalSince1970: $0) }
    }
    // Per-rep callback: (repIndex, repROM)
    var onRepDetected: ((Int, Double) -> Void)?
    
    // MARK: - Public Access Methods for Bounded Arrays
    
    /// Get all ROM per rep values as an array
    var romPerRepArray: [Double] {
        return romPerRep.allElements
    }
    
    /// Get all SPARC history values as an array
    var sparcHistoryArray: [Double] {
        return sparcHistory.allElements
    }
    
    /// Get count of ROM per rep entries
    var romPerRepCount: Int {
        return romPerRep.count
    }
    
    /// Get count of SPARC history entries
    var sparcHistoryCount: Int {
        return sparcHistory.count
    }
    
    /// Check if ROM per rep is empty
    var isRomPerRepEmpty: Bool {
        return romPerRep.isEmpty
    }
    
    /// Unified rep detection service for game-specific rep detection
    let unifiedRepDetection = UnifiedRepDetectionService()
    
    /// Get maximum ROM from romPerRep
    var maxRomPerRep: Double? {
        let elements = romPerRep.allElements
        return elements.isEmpty ? nil : elements.max()
    }
    
    /// Add ROM value to romPerRep (for game views) - DEPRECATED
    /// Games should no longer call this directly - data is handled automatically
    func addRomPerRep(_ value: Double) {
        // No longer append - this causes duplicate data
        // Rep detection automatically handles ROM tracking
    FlexaLog.motion.warning("[DEPRECATED] addRomPerRep called — game view attempted direct ROM injection")
    }
    
    /// Add SPARC value to sparcHistory (for game views) - DEPRECATED  
    /// Games should no longer call this directly - data is handled automatically
    func addSparcHistory(_ value: Double) {
        // No longer append - this causes duplicate data
        // Rep detection automatically handles SPARC tracking
    FlexaLog.motion.warning("[DEPRECATED] addSparcHistory called — game view attempted direct SPARC injection")
    }
    
    // MARK: - ROM Consistency and Validation
    
    /// Standardized ROM validation - ensures consistent units and ranges across all games
    /// All ROM values should be in degrees (0-180°) regardless of calculation method
    func validateAndNormalizeROM(_ rom: Double) -> Double {
        // Ensure ROM is within valid physiological range (0-180 degrees)
        let normalizedROM = max(0.0, min(180.0, rom))
        
        // Apply minimum threshold for meaningful movement (consistent across all games)
        let minimumThreshold: Double = 5.0 // 5 degrees minimum for valid ROM
        
        return normalizedROM >= minimumThreshold ? normalizedROM : 0.0
    }

    // Simple exponential smoother for ROM to reduce jitter (alpha between 0..1)
    private var romSmoothingAlpha: Double = 0.25
    private var smoothedROM: Double = 0
    
    /// Standardized ROM threshold for rep detection - consistent across all game types
    func getMinimumROMThreshold(for gameType: GameType) -> Double {
        switch gameType {
        case .balloonPop, .wallClimbers, .camera, .constellation:
            // Camera games: use joint-specific thresholds
            return preferredCameraJoint == .elbow ? 15.0 : 20.0
        case .fruitSlicer, .followCircle, .testROM, .makeYourOwn:
            // Handheld games: use lower ARKit-based threshold to prevent false high readings
            return 5.0 // Reduced from 10.0 to prevent phone tilt from registering as significant ROM
        case .fanOutFlame:
            // Scapular retractions need gentle threshold so smaller swings register
            return 4.0
        case .mountainClimber:
            return 10.0
        }
    }
    
    func updateCurrentROM(_ rom: Double) {
        DispatchQueue.main.async {
            self.currentROM = rom
            if rom > self.maxROM {
                self.maxROM = rom
            }
            self.romHistory.append(rom)
        }
    }
    
    /// Append a ROM sample for the current rep if the cooldown has elapsed (handheld stability)
    private func appendRepSampleIfReady(_ rom: Double) {
        // Conservative sampling: enforce cooldown and only append validated, smoothed samples
        if repSampleCooldownFrames > 0 {
            repSampleCooldownFrames -= 1
            return
        }

        let validated = validateAndNormalizeROM(rom)
        // Apply light exponential smoothing to reduce noisy spikes
        if smoothedROM == 0 {
            smoothedROM = validated
        } else {
            smoothedROM = (romSmoothingAlpha * validated) + ((1 - romSmoothingAlpha) * smoothedROM)
        }

        // Only append if smoothed value still passes minimum threshold
        if validateAndNormalizeROM(smoothedROM) > 0 {
            romSamples.append(smoothedROM)
        }
    }
    
    // MARK: - Private Properties
    var motionManager: CMMotionManager?
    var universal3DEngine = Universal3DROMEngine()
    private var poseProvider = VisionPoseProvider()
    private var _sparcService = SPARCCalculationService()
    var sparcService: SPARCCalculationService {
        return _sparcService
    }
    private var repDetectionService = UnifiedRepDetectionService()
    // Use Universal3D engine for handheld rep detection/ROM (fruit slicer, fan out). Keeps IMU for SPARC only.
    var useEngineRepDetectionForHandheld: Bool = true
    private var lastSmoothedPose: SimplifiedPoseKeypoints?
    private var poseDropoutCache: [PoseJoint: PoseCacheEntry] = [:]
    private let poseDropoutGracePeriod: TimeInterval = 0.18
    
    // Fan the Flame: IMU-based direction-change rep detection
    let fanTheFlameDetector = FanTheFlameRepDetector()

    private enum PoseJoint: String {
        case leftWrist, rightWrist
        case leftElbow, rightElbow
        case leftShoulder, rightShoulder
        case neck, nose
        case leftHip, rightHip

        var isWrist: Bool { self == .leftWrist || self == .rightWrist }
        var isElbow: Bool { self == .leftElbow || self == .rightElbow }
    }

    private struct PoseCacheEntry {
        let point: CGPoint
        let expiry: TimeInterval
    }
    
    // MARK: - Error Handling and Recovery
    private let errorHandler = ROMErrorHandler()
    @Published var systemHealth: ROMErrorHandler.SystemHealth = .healthy
    @Published var isRecovering: Bool = false
    @Published var lastError: String?
    
    // MARK: - Performance Monitoring
    private let performanceMonitor = PerformanceMonitor()
    @Published var performanceMetrics: PerformanceMonitor.PerformanceMetrics?
    @Published var performanceIssueDetected: Bool = false

    // MARK: - Session Data
    var sessionStartTime: TimeInterval = 0
    private var romHistory = BoundedArray<Double>(maxSize: 2000) // Increased for better accuracy
    private var romSamples = BoundedArray<Double>(maxSize: 200) // Increased for better accuracy
    // Cooldown frames to skip after resetting ARKit so baseline stabilizes near zero before sampling next rep
    private var repSampleCooldownFrames: Int = 0
    // Track peak ROM observed since last rep for handheld games (robust to sampling phase)
    private var repPeakROM: Double = 0

    // MARK: - Pain Level Tracking
    var prePainLevel: Int? = nil
    var postPainLevel: Int? = nil
    
    // MARK: - Game Configuration
    enum GameType: String, CaseIterable {
        case camera = "camera"
        case fruitSlicer = "fruitSlicer"
        case fanOutFlame = "fanOutFlame"
        case followCircle = "followCircle"
        case balloonPop = "balloonPop"
        case wallClimbers = "wallClimbers"
        case constellation = "constellationMaker"
        case mountainClimber = "mountainClimber"
        case testROM = "testROM"
        case makeYourOwn = "makeYourOwn"
        
        
        var displayName: String {
            switch self {
            case .camera: return "Camera Exercise"
            case .fruitSlicer: return "Pendulum Swing"
            case .fanOutFlame: return "Scapular Retractions"
            case .followCircle: return "Pendulum Circles"
            case .balloonPop: return "Elbow Extension"
            case .wallClimbers: return "Wall Climb"
            case .constellation: return "Arm Raises"
            case .mountainClimber: return "Wall Climb"
            case .testROM: return "ROM Test"
            case .makeYourOwn: return "Make Your Own"
            }
        }
    }
    
    enum ROMTrackingMode {
        case arkit
        case vision
    }
    
    var currentGameType: GameType = .fruitSlicer
    var isCameraExercise: Bool {
        return [.wallClimbers, .balloonPop, .camera, .constellation].contains(currentGameType)
    }
    
    // MARK: - Camera Properties
    var captureSession: AVCaptureSession?
    @Published private(set) var previewSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let cameraQueue = DispatchQueue(label: "com.flexa.camera.sample", qos: .userInitiated)
    
    // Keep a reference to the active camera device to adjust frame rate under pressure
    private var captureDevice: AVCaptureDevice?
    private var cameraTeardownWorkItem: DispatchWorkItem?
    
    // Camera startup synchronization
    private var isStartingCamera = false
    private let cameraStartupLock = NSLock()
    
    // Memory pressure handling
    enum MemoryPressureLevel { case normal, warning, critical }
    @Published var memoryPressureLevel: MemoryPressureLevel = .normal
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var memoryRecoveryWorkItem: DispatchWorkItem?
    
    // Vision frame throttling (skip frames when under pressure)
    private var lastVisionProcessTime: CFAbsoluteTime = 0
    private let minVisionFrameIntervalNormal: CFAbsoluteTime = 1.0 / 30.0
    private let minVisionFrameIntervalThrottled: CFAbsoluteTime = 1.0 / 10.0

    // ADD: Non-critical data collection frequency knob (seconds). Default 0.5s = twice per second.
    private var dataCollectionFrequency: TimeInterval = 0.5
    
    override init() {
      super.init()
      setupServices()
      setupErrorHandling()
      setupMemoryMonitoring()
      
      // Observe calibration completion to enable ARKit path mid-session
      NotificationCenter.default.addObserver(forName: NSNotification.Name("AnatomicalCalibrationComplete"), object: nil, queue: .main) { [weak self] _ in
        guard let self = self else { return }
        // Only relevant for handheld games
        if !self.isCameraExercise && !self.isARKitRunning {
                do {
                    try self.startARKitWithErrorHandling()
                    FlexaLog.motion.info("Calibration completed — enabling ARKit ROM tracking")
                } catch {
                    self.errorHandler.handleError(.arkitSessionFailed(error))
                }
            }
        }

        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.stopCamera(tearDownCompletely: true)
        }
    }
    
    deinit {
        // Remove notification observers
        NotificationCenter.default.removeObserver(self)
        // Cancel memory pressure source
        memoryPressureSource?.cancel()
        
        // Stop all active sessions and clean up resources
        if isSessionActive {
            stopSession()
        }
        
        // Ensure motion manager is stopped and cleared
        motionManager?.stopDeviceMotionUpdates()
        motionManager = nil
        
        // Ensure camera is stopped
    stopCamera(tearDownCompletely: true)
        
        // Clear callbacks to prevent retain cycles
        onRepDetected = nil
        
        FlexaLog.motion.info("SimpleMotionService deinitializing and cleaning up all resources")
    }
    
    private func setupServices() {
        // Initialize Universal3D engine
        // Universal3D engine now uses CalibrationDataManager.shared directly
        
        // Connect Universal3D engine to SPARC service for proper data flow
        universal3DEngine.setSparcService(sparcService)
        
        // Setup pose provider with error handling
        poseProvider.onPoseDetected = { [weak self] keypoints in
            self?.processPoseKeypointsInternal(keypoints)
        }
        
        // Setup Universal3D engine rep detection callback.
        // When enabled, this becomes the source of truth for handheld rep count and per-rep ROM.
        onRepDetected = { [weak self] repIndex, repROM in
            guard let self = self else { return }
            let validatedROM = self.validateAndNormalizeROM(repROM)
            if self.useEngineRepDetectionForHandheld && !self.isCameraExercise {
                DispatchQueue.main.async {
                    self.currentReps = repIndex
                    let now = Date().timeIntervalSince1970
                    self.romPerRep.append(validatedROM)
                    self.romPerRepTimestamps.append(now)
                    self.lastRepROM = validatedROM
                    // SPARC remains IMU-based; append current SPARC snapshot
                    let sparc = self.sparcService.getCurrentSPARC()
                    self.sparcHistory.append(sparc)
                    // Reset engine position window for next rep just in case
                    if self.isARKitRunning {
                        // New engine handles rep tracking automatically
                    }
                    FlexaLog.motion.info("🎯 [Universal3D] Rep #\(repIndex) stored — ROM=\(String(format: "%.1f", validatedROM))° SPARC=\(String(format: "%.1f", sparc))")
                }
            } else {
                // Not using engine-driven reps; just keep lastRepROM updated for UI
                DispatchQueue.main.async { self.lastRepROM = validatedROM }
            }
        }
        
        // Wire Universal3D engine's live rep detection callback
        universal3DEngine.onLiveRepDetected = { [weak self] repIndex, repROM in
            guard let self = self else { return }
            // Fire the existing onRepDetected callback with live data
            self.onRepDetected?(repIndex, repROM)
        }
        
        // Connect error handlers to services
        universal3DEngine.setErrorHandler(errorHandler)
        poseProvider.setErrorHandler(errorHandler)
        sparcService.setErrorHandler(errorHandler)
    }
    
    private func setupErrorHandling() {
        // Bind error handler state to published properties
        errorHandler.onSystemHealthChanged = { [weak self] health in
            DispatchQueue.main.async {
                self?.systemHealth = health
            }
        }
        
        errorHandler.onRecoveryRequired = { [weak self] error, strategy in
            self?.executeRecoveryStrategy(error: error, strategy: strategy)
        }
        
        errorHandler.onCriticalError = { [weak self] error in
            DispatchQueue.main.async {
                self?.lastError = error.localizedDescription
                self?.isRecovering = false
                FlexaLog.motion.critical("Critical ROM system failure: \(error.localizedDescription)")
            }
        }
        
        // Bind recovery state
        errorHandler.$isRecovering
            .receive(on: DispatchQueue.main)
            .assign(to: &$isRecovering)
        
        // Bind performance monitoring
        performanceMonitor.$currentMetrics
            .receive(on: DispatchQueue.main)
            .assign(to: &$performanceMetrics)
        
        performanceMonitor.$performanceIssueDetected
            .receive(on: DispatchQueue.main)
            .assign(to: &$performanceIssueDetected)
    }

    private func resetPoseSmoothingState() {
        lastSmoothedPose = nil
        poseDropoutCache.removeAll()
    }
    
    // MARK: - Error Recovery Implementation
    
    private func executeRecoveryStrategy(error: ROMErrorHandler.ROMError, strategy: ROMErrorHandler.RecoveryStrategy) {
        FlexaLog.motion.info("Executing recovery strategy: \(strategy) for error: \(error.localizedDescription)")
        
        switch strategy {
        case .retry:
            executeRetryStrategy(for: error)
        case .fallbackToARKit:
            executeFallbackToARKit()
        case .restartSession:
            executeSessionRestart()
        case .gracefulDegradation:
            executeGracefulDegradation(for: error)
        case .criticalFailure:
            // Already handled by onCriticalError callback
            break
        }
    }
    
    private func executeRetryStrategy(for error: ROMErrorHandler.ROMError) {
        switch error {
        case .arkitSessionFailed:
            // Retry ARKit initialization
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                do {
                    try self?.startARKitWithErrorHandling()
                    FlexaLog.motion.info("ARKit retry successful")
                } catch {
                    self?.errorHandler.handleError(.arkitSessionFailed(error))
                }
            }
        case .cameraSessionFailed:
            // Retry camera initialization
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.startCamera { success in
                    if success {
                        FlexaLog.motion.info("Camera retry successful")
                    } else {
                        FlexaLog.motion.error("Camera retry failed")
                    }
                }
            }
        default:
            FlexaLog.motion.warning("No specific retry strategy for error: \(error)")
        }
    }
    
    
    private func executeFallbackToARKit() {
        FlexaLog.motion.info("Falling back to ARKit-based ROM tracking")
        
        // Stop camera if running
    stopCamera(tearDownCompletely: true)
        
        // Start ARKit
        do {
            try startARKitWithErrorHandling()
            romTrackingMode = "ARKit"
            FlexaLog.motion.info("Successfully switched to ARKit-based tracking")
        } catch {
            FlexaLog.motion.error("Failed to fallback to ARKit: \(error.localizedDescription)")
            // If ARKit fails, try graceful degradation
            executeGracefulDegradation(for: .arkitSessionFailed(error))
        }
    }
    
    private func executeSessionRestart() {
        FlexaLog.motion.info("Restarting ROM session due to recovery")
        
        // Stop current session
        stopSession()
        
        // Clear error state
        errorHandler.resetForNewSession()
        
        // Reset ROM data on main thread
        DispatchQueue.main.async {
            self.currentROM = 0
            self.maxROM = 0
            self.currentReps = 0
            self.romHistory.removeAll()
            self.romPerRep.removeAll()
            self.sparcHistory.removeAll()
        }
        
        // Restart with current game type after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self else { return }
            self.startSession(gameType: self.currentGameType)
            FlexaLog.motion.info("Session restarted successfully")
        }
    }
    
    private func executeGracefulDegradation(for error: ROMErrorHandler.ROMError) {
        FlexaLog.motion.info("Executing graceful degradation for error: \(error.localizedDescription)")
        
        switch error {
        case .calibrationDataMissing:
            // Continue with default calibration values
            FlexaLog.motion.info("Using default calibration values")
        case .memoryPressureHigh, .resourceExhaustion:
            // Reduce data collection frequency
            reduceDataCollectionFrequency()
        case .visionPoseNotDetected:
            // Continue with last known pose or use simplified tracking
            FlexaLog.motion.info("Using simplified pose tracking")
        default:
            // Generic degradation - reduce precision but continue
            FlexaLog.motion.info("Continuing with reduced precision")
        }
    }
    
    private func reduceDataCollectionFrequency() {
        // Reduce camera frame rate under memory pressure
        if let device = captureDevice {
            do {
                try device.lockForConfiguration()
                if #available(iOS 15.0, *) {
                    device.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: 15) // Reduce to 15 FPS
                    device.activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: 15)
                }
                device.unlockForConfiguration()
                FlexaLog.motion.info("Reduced camera frame rate to 15 FPS due to memory pressure")
            } catch {
                FlexaLog.motion.warning("Failed to reduce camera frame rate: \(error.localizedDescription)")
            }
        }
        
        // Reduce data collection frequency knob (non-critical paths)
        self.dataCollectionFrequency = 0.5 // Collect data twice per second under memory pressure
        FlexaLog.motion.info("Reduced non-critical data collection frequency to \(self.dataCollectionFrequency)s")
    }
    
    private func isCameraRunning() -> Bool {
        return captureSession?.isRunning == true
    }
    
    // MARK: - Memory Pressure Handling
    private func setupMemoryMonitoring() {
        // iOS memory warning
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleMemoryPressure(.critical, reason: "UIApplication.didReceiveMemoryWarningNotification")
        }
        // Dispatch memory pressure signals
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global(qos: .utility))
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            let event = source.data
            let level: MemoryPressureLevel = event.contains(.critical) ? .critical : .warning
            self.handleMemoryPressure(level, reason: "DispatchSourceMemoryPressure(\(event.rawValue))")
        }
        memoryPressureSource = source
        source.resume()
    }
    
    private func handleMemoryPressure(_ level: MemoryPressureLevel, reason: String) {
        DispatchQueue.main.async {
            self.memoryPressureLevel = level
        }
        FlexaLog.motion.warning("⚠️ Memory pressure: \(String(describing: level)) — reason=\(reason)")
        clearNonCriticalCaches()
        adjustCameraFrameRate(for: level)
        
        // Pause Vision processing at critical pressure; resume when back to normal
        if level == .critical {
            poseProvider.stop()
        } else if level == .normal, isCameraRunning() {
            poseProvider.start()
        }
        
        // Schedule recovery back to normal after a cooldown if no further warnings
        memoryRecoveryWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if self.memoryPressureLevel != .normal {
                FlexaLog.motion.info("✅ Memory pressure recovered — restoring normal settings")
                DispatchQueue.main.async { self.memoryPressureLevel = .normal }
                self.adjustCameraFrameRate(for: .normal)
            }
        }
        memoryRecoveryWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0, execute: work)
    }
    
    private func adjustCameraFrameRate(for level: MemoryPressureLevel) {
        guard let device = captureDevice else { return }
        do {
            try device.lockForConfiguration()
            switch level {
            case .normal:
                if #available(iOS 15.0, *) {
                    device.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: 30)
                    device.activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: 30)
                }
            case .warning, .critical:
                if #available(iOS 15.0, *) {
                    device.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: 15)
                    device.activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: 15)
                }
            }
            device.unlockForConfiguration()
        } catch {
            FlexaLog.motion.warning("Unable to adjust camera FPS: \(error.localizedDescription)")
        }
    }
    
    private func clearNonCriticalCaches() {
        // Drop overlays and temp samples to reduce memory footprint
        romSamples.removeAll()
    }
    
    // MARK: - Performance Monitoring
    
    /// Get current performance report for debugging
    func getPerformanceReport() -> String {
        return performanceMonitor.getPerformanceReport()
    }
    
    /// Check if system is performing within acceptable limits
    func isPerformingWell() -> Bool {
        return performanceMonitor.isPerformingWell()
    }
    
    /// Record frame for frame rate calculation (call from UI updates)
    func recordFrame() {
        performanceMonitor.recordFrame()
    }
    
    // Game session control
    func startSession(gameType: GameType) {
        let work = {
            self.currentGameType = gameType
            self.isSessionActive = true
            self.sessionStartTime = Date().timeIntervalSince1970

            // Reset counters
            self.currentReps = 0
            self.maxROM = 0
            self.romHistory.removeAll()

            // Start performance monitoring
            self.performanceMonitor.startMonitoring()

            FlexaLog.motion.info("🎮 Starting game session for \(gameType.displayName, privacy: .public)")
            if gameType == .followCircle {
                FlexaLog.motion.info("🎯 [FollowCircle] Motion session activated — resetting metrics and monitors")
            }
        }

        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
    
    func setPrePainLevel(_ level: Int) {
        DispatchQueue.main.async {
            self.prePainLevel = level
            FlexaLog.motion.info("📊 [Pain] Pre-exercise pain level set to: \(level, privacy: .public)")
        }
    }
    
    func setPostPainLevel(_ level: Int) {
        DispatchQueue.main.async {
            self.postPainLevel = level
            FlexaLog.motion.info("📊 [Pain] Post-exercise pain level set to: \(level, privacy: .public)")
        }
    }
    
    // ROM tracking mode control - automatically determined by game type
    private func setROMTrackingMode(_ mode: ROMTrackingMode) {
        switch mode {
        case .arkit:
            DispatchQueue.main.async {
                self.romTrackingMode = "ARKit"
                self.isARKitRunning = true
            }
            // Start background data collection for handheld games
            if isCameraExercise {
                // Camera games don't use Universal3D
            } else {
                let convertedGameType = Universal3DROMEngine.convertGameType(currentGameType)
                universal3DEngine.startDataCollection(gameType: convertedGameType)
            }
        case .vision:
            DispatchQueue.main.async {
                self.romTrackingMode = "Vision"
            }
            poseProvider.startPoseTracking()
        }
        FlexaLog.motion.info("🎯 ROM tracking mode set to \(String(describing: mode), privacy: .public) for \(self.currentGameType.displayName, privacy: .public)")
    }
    
    func processPoseKeypoints(_ keypoints: SimplifiedPoseKeypoints) {
        processPoseKeypointsInternal(keypoints)
    }

    /// Called by camera-driven games when a rep is completed entirely via Vision detection.
    func recordVisionRepCompletion(rom: Double) {
        DispatchQueue.main.async {
            let validatedROM = self.validateAndNormalizeROM(rom)
            self.currentReps += 1
            self.lastRepROM = validatedROM
            self.currentROM = validatedROM

            if validatedROM > self.maxROM {
                self.maxROM = validatedROM
            }

            self.romPerRep.append(validatedROM)
            self.romPerRepTimestamps.append(Date().timeIntervalSince1970)

            let sparc = self.sparcService.getCurrentSPARC()
            self.sparcHistory.append(sparc)

            let romText = String(format: "%.1f", validatedROM)
            let sparcText = String(format: "%.1f", sparc)

            if self.currentGameType != .fruitSlicer {
                HapticFeedbackService.shared.successHaptic()
            }

            self.onRepDetected?(self.currentReps, validatedROM)

            FlexaLog.motion.info("🎥 [VisionRep] Recorded camera rep #\(self.currentReps) ROM=\(romText)° SPARC=\(sparcText)")
        }
    }
    
    // MARK: - Core Motion Setup
    func setupCoreMotion() {
        motionManager = CMMotionManager()
        guard let manager = motionManager else {
            errorHandler.handleError(.motionDataUnavailable)
            return
        }
        
        guard manager.isDeviceMotionAvailable else {
            errorHandler.handleError(.motionDataUnavailable)
            FlexaLog.motion.error("Device motion not available")
            return
        }
        
        manager.deviceMotionUpdateInterval = 1.0 / 60.0 // 60 Hz
        FlexaLog.motion.info("CoreMotion setup complete")
    }
    
    func startDeviceMotionUpdatesLoop() {
        guard let manager = motionManager else {
            errorHandler.handleError(.motionDataUnavailable)
            FlexaLog.motion.error("Motion manager not initialized")
            return
        }
        
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self else { return }
            
            if let error = error {
                self.errorHandler.handleError(.motionDataUnavailable)
                FlexaLog.motion.error("Motion update error: \(error.localizedDescription)")
                return
            }
            
            guard let motion = motion else {
                FlexaLog.motion.warning("Received nil motion data")
                return
            }
            
            // Use motion data for SPARC analysis - rep detection now handled by Universal3D engine
            if !self.isCameraExercise {
                // Add motion sensor data to SPARC service for smoothness analysis
                self._sparcService.addIMUData(
                    timestamp: motion.timestamp,
                    acceleration: [Double(motion.userAcceleration.x), Double(motion.userAcceleration.y), Double(motion.userAcceleration.z)],
                    velocity: nil
                )
                
                // Fan the Flame: Use IMU direction-change detection instead of ARKit
                if self.currentGameType == .fanOutFlame {
                    self.fanTheFlameDetector.processMotion(motion)
                }
                
                // Sample ROM for tracking (actual rep detection done by Universal3D engine via live callbacks)
                self.appendRepSampleIfReady(self.currentROM)
            }
        }
    }
    
    // Convert gametype for rep detection service
    private func convertToUnifiedGameType(_ gameType: GameType) -> UnifiedRepDetectionService.GameType {
        switch gameType {
        case .camera:
            return .wallClimbers
        case .fruitSlicer:
            return .fruitSlicer  
        case .fanOutFlame:
            return .fanOutFlame
        case .followCircle:
            return .followCircle
        case .balloonPop:
            return .balloonPop
        case .wallClimbers:
            return .wallClimbers
        case .constellation:
            return .constellationMaker
        case .mountainClimber:
            return .wallClimbers
        case .testROM:
            return .fruitSlicer
        case .makeYourOwn:
            return .makeYourOwn
        }
    }

    
    func getCurrentSPARC() -> Double {
        return sparcService.getCurrentSPARC()
    }
    
    private func updateRepDetection(rom: Double, timestamp: TimeInterval) {
        // Track ROM for current rep - this captures the continuous motion
        appendRepSampleIfReady(rom)
        
        // Use standardized ROM thresholds for consistent rep detection across all games
        let standardThreshold = getMinimumROMThreshold(for: currentGameType)
        
        // Use game-specific rep detection patterns with fine-tuned thresholds
        switch currentGameType {
        case .fruitSlicer:
            // One swing forward = 1 rep, one swing backward = 1 rep
            if repDetectionService.processPendulumSwing(rom: rom, timestamp: timestamp, threshold: standardThreshold, minGap: 0.3) {
                _ = completeRep()
            }
        case .followCircle:
            // One complete circle = 1 rep
            if repDetectionService.processCircularMotion(rom: rom, timestamp: timestamp, threshold: standardThreshold, minGap: 1.0) {
                _ = completeRep()
            }
        case .fanOutFlame:
            // One swing to left = 1 rep, one swing to right = 1 rep
            if repDetectionService.processFanMotion(rom: rom, timestamp: timestamp, threshold: standardThreshold, minGap: 0.4) {
                _ = completeRep()
            }
        case .balloonPop:
            // One elbow extension = 1 rep
            if repDetectionService.processVisionRep(rom: rom, timestamp: timestamp, threshold: standardThreshold, minGap: 0.6) {
                _ = completeRep()
            }
        case .wallClimbers:
            // Climbing up fully = 1 rep
            if repDetectionService.processVisionRep(rom: rom, timestamp: timestamp, threshold: standardThreshold, minGap: 1.0) {
                _ = completeRep()
            }
        case .constellation:
            // Rep detection handled by game logic when stars are connected
            break
        case .testROM:
            break // Manual completion
        case .makeYourOwn:
            if repDetectionService.processCircularMotion(rom: rom, timestamp: timestamp, threshold: standardThreshold, minGap: 0.4) {
                _ = completeRep()
            }
        case .camera:
            if repDetectionService.processVisionRep(rom: rom, timestamp: timestamp, threshold: standardThreshold, minGap: 0.5) {
                _ = completeRep()
            }
        default:
            if repDetectionService.processDefaultRep(rom: rom, timestamp: timestamp) {
                _ = completeRep()
            }
        }
        
    FlexaLog.motion.debug("📐 [ROM Consistency] Rep detection using standardized threshold: \(String(format: "%.1f", standardThreshold))° for \(self.currentGameType.displayName, privacy: .public)")
    }
    
    private func completeRep() -> Double {
        currentReps += 1

        // Compute debug range, but store peak-based ROM for handheld games (more stable)
        var rangeROM: Double = 0
        var repMax: Double = currentROM
        var repMin: Double = currentROM
        if !romSamples.isEmpty {
            let samples = romSamples.allElements
            repMax = samples.max() ?? currentROM
            repMin = samples.min() ?? currentROM
            rangeROM = max(0, repMax - repMin)
        }

        // Prefer peak-based ROM aggregated from ARKit updates between reps
        var repROM = repPeakROM
        if repROM <= 0 {
            // Fallback to range if peak not captured
            repROM = rangeROM > 0 ? rangeROM : currentROM
        }
        repROM = validateAndNormalizeROM(repROM)

        let repTimestamp = Date()

        if !useEngineRepDetectionForHandheld || isCameraExercise {
            romPerRep.append(repROM)
            romPerRepTimestamps.append(repTimestamp.timeIntervalSince1970)
            lastRepROM = repROM

            let sparc = sparcService.getCurrentSPARC()
            sparcHistory.append(sparc)
        } else {
            // For handheld games using Universal3D engine, rely on engine callbacks to append session data
            lastRepROM = repROM
            let formattedROM = String(format: "%.1f", repROM)
            FlexaLog.motion.info("🎯 [Universal3D] Using raw peak ROM for rep #\(self.currentReps): \(formattedROM)°")
        }
        
        // Reset position tracking in ARKit engine for new rep
        if isARKitRunning {
            // New engine handles rep tracking automatically - no manual reset needed
        }
        // Prepare for next rep sampling
        repPeakROM = 0
        romSamples.removeAll()
        // Increase cooldown after rep to avoid overcounting from high-frequency noise
        repSampleCooldownFrames = 8
        
        // Haptic feedback for rep completion - disabled for Fruit Slicer
        if currentGameType != .fruitSlicer {
            HapticFeedbackService.shared.successHaptic()
        }
        // Notify listeners with concise callback and minimal logging
        onRepDetected?(currentReps, repROM)
    FlexaLog.motion.debug("♻️ [RepRange] #\(self.currentReps) min=\(String(format: "%.1f", repMin))° max=\(String(format: "%.1f", repMax))° range=\(String(format: "%.1f", rangeROM))° peak=\(String(format: "%.1f", repROM))°")
        
        return repROM
    }
    
    private func shouldUseEngineRepDetection(for gameType: GameType) -> Bool {
        // All handheld games now use Universal3D engine for consistent ARKit-based rep detection
        return true
    }

    func startGameSession(gameType: GameType) {
        FlexaLog.motion.info("🎮 [SESSION-START] startGameSession called for: \(gameType.displayName)")
        // Reset error handler for new session (state updates published on main)
        errorHandler.resetForNewSession()
        FlexaLog.motion.info("🎮 [SESSION-START] Error handler reset complete")
        // Defer readiness check to next main runloop tick to avoid race with above reset
        DispatchQueue.main.async { [weak self] in
            FlexaLog.motion.info("🎮 [SESSION-START] Main queue async block executing")
            guard let self = self else {
                FlexaLog.motion.error("🎮 [SESSION-START] ❌ self is nil, aborting")
                return
            }
            FlexaLog.motion.info("🎮 [SESSION-START] Checking system health: \(String(describing: self.errorHandler.systemHealth))")
            // Allow starting unless system health is FAILED; ignore transient isRecovering during reset
            guard self.errorHandler.systemHealth != .failed else {
                FlexaLog.motion.error("🎮 [SESSION-START] ❌ Cannot start session - system health failed")
                return
            }
            FlexaLog.motion.info("🎮 [SESSION-START] ✅ System health check passed")
            // Ensure session flags and game type are correctly set
            self.startSession(gameType: gameType)
            FlexaLog.motion.info("🎮 [SESSION-START] startSession(gameType:) called")
            self.romHistory.removeAll()
            self.romPerRep.removeAll()
            self.sparcHistory.removeAll()
            self.romSamples.removeAll()
            
            // Reset SPARC service to clear old data from previous sessions
            self.sparcService.reset()
            FlexaLog.motion.info("🧹 SPARC service reset for fresh game session")

            // Configure whether to rely on Universal3D engine for rep detection
            self.useEngineRepDetectionForHandheld = self.shouldUseEngineRepDetection(for: gameType)

            FlexaLog.motion.info("🎮 [SESSION-START] Game type: \(gameType.displayName), isCameraExercise: \(self.isCameraExercise)")
            // Automatically determine ROM tracking mode based on game type with error handling
            do {
                if self.isCameraExercise {
                    FlexaLog.motion.info("🎮 [SESSION-START] → Calling startCameraGameSession")
                    try self.startCameraGameSession(gameType: gameType)
                } else {
                    FlexaLog.motion.info("🎮 [SESSION-START] → Calling startHandheldGameSession")
                    try self.startHandheldGameSession(gameType: gameType)
                }
                
                let unifiedGameType = self.convertToUnifiedGameType(gameType)
                self.repDetectionService.startSession(gameType: unifiedGameType)
                FlexaLog.motion.info("🎮 [SESSION-START] Rep detection service started")
                
                FlexaLog.motion.info("🎮 [SESSION-START] ✅ Game session started successfully: \(gameType.displayName)")
            } catch {
                FlexaLog.motion.error("🎮 [SESSION-START] ❌ Exception caught: \(error.localizedDescription)")
                self.errorHandler.handleError(.sessionCorrupted)
            }
        }
    }
    
    private func startCameraGameSession(gameType: GameType) throws {
        FlexaLog.motion.info("📹 [CAMERA-GAME] Starting camera game session for \(gameType.displayName)")
        resetPoseSmoothingState()
        
        // Camera games ONLY use Vision pose detection
        // Ensure ARKit is not running
        if isARKitRunning {
            FlexaLog.motion.info("📹 [CAMERA-GAME] Stopping ARKit for camera-only mode")
            universal3DEngine.stop()
            isARKitRunning = false
        }
        
        FlexaLog.motion.info("📹 [CAMERA-GAME] Setting ROM tracking mode to Vision")
        setROMTrackingMode(.vision)
        
        // Wire Vision callbacks to this service
        FlexaLog.motion.info("📹 [CAMERA-GAME] Wiring Vision pose detection callbacks")
        poseProvider.onPoseDetected = { [weak self] keypoints in
            self?.processPoseKeypoints(keypoints)
        }
        
        // Start camera with error handling
        FlexaLog.motion.info("📹 [CAMERA-GAME] Starting camera session")
        startCamera { [weak self] success in
            if success {
                FlexaLog.motion.info("📹 [CAMERA-GAME] Camera session started successfully")
            } else {
                FlexaLog.motion.error("📹 [CAMERA-GAME] Camera session failed to start")
                self?.errorHandler.handleError(.cameraSessionFailed(NSError(domain: "SimpleMotionService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to start camera"])))
            }
        }
        
        FlexaLog.motion.info("📹 [CAMERA-GAME] Starting pose provider")
        poseProvider.start()
        FlexaLog.motion.info("Camera game '\(gameType.displayName)' using Vision-only ROM calculation")
    }
    
    private func startHandheldGameSession(gameType: GameType) throws {
        // Handheld games use ARKit-based ROM calculation for 3D tracking
        resetPoseSmoothingState()
        
        // Stop camera and vision since not needed for handheld games
    stopCamera(tearDownCompletely: true)
        poseProvider.stop()
        
        // Ensure ARKit is not already running to avoid conflicts
        if isARKitRunning {
            universal3DEngine.stop()
            isARKitRunning = false
        }
        
        // Setup CoreMotion with error handling
        if motionManager == nil {
            setupCoreMotion()
        }
        
        guard motionManager?.isDeviceMotionAvailable == true else {
            throw ROMErrorHandler.ROMError.motionDataUnavailable
        }
        
        // Ensure device motion updates are running before any calibration snapshots
        startDeviceMotionUpdatesLoop()
        
        // Fan the Flame: Setup IMU direction-change rep detection
        if gameType == .fanOutFlame {
            fanTheFlameDetector.reset()
            fanTheFlameDetector.onRepDetected = { [weak self] repCount, direction, peakVelocity in
                guard let self = self else { return }
                FlexaLog.motion.info("🔥 [FanFlame] Direction-change rep detected! Count: \(repCount), Direction: \(direction.description), Velocity: \(String(format: "%.2f", peakVelocity)) rad/s")
                
                // Update published rep count
                DispatchQueue.main.async {
                    self.currentReps = repCount
                }
                
                // Track ROM for this rep (ARKit provides spatial ROM)
                let currentROM = self.currentROM
                self.romPerRep.append(currentROM)
                self.romPerRepTimestamps.append(Date().timeIntervalSince1970)
                
                // Fire generic rep callback for game view
                self.onRepDetected?(repCount, currentROM)
            }
            FlexaLog.motion.info("🔥 [FanFlame] IMU direction-change detector configured")
        }
        
        // Enable ARKit-driven ROM calculation with error handling
        try startARKitWithErrorHandling()
        
        let calibrated = universal3DEngine.isCalibrated
        FlexaLog.motion.info("Calibration status: \(calibrated ? "CALIBRATED" : "NOT CALIBRATED")")
        
        if calibrated {
            FlexaLog.motion.info("Using existing calibration — ARKit will proceed smoothly")
        } else {
            FlexaLog.motion.warning("No calibration data - using default arm length")
        }
        
        FlexaLog.motion.info("Handheld game '\(gameType.displayName)' using ARKit-only ROM calculation")
    }
    
    private func startARKitWithErrorHandling() throws {
        guard ARWorldTrackingConfiguration.isSupported else {
            throw ROMErrorHandler.ROMError.arkitNotSupported
        }
        
            let convertedGameType = Universal3DROMEngine.convertGameType(currentGameType)
            universal3DEngine.startDataCollection(gameType: convertedGameType)
        isARKitRunning = true
    }
    
    func stopSession() {
        let endedGame = currentGameType
        if endedGame == .followCircle {
            let romCount = self.romPerRep.count
            let sparcCount = self.sparcHistory.count
            FlexaLog.motion.info("🎯 [FollowCircle] Preparing to stop session — reps=\(self.currentReps, privacy: .public) maxROM=\(String(format: "%.1f", self.maxROM), privacy: .public) romEntries=\(romCount, privacy: .public) sparcEntries=\(sparcCount, privacy: .public)")
        }
        // Stop pose provider and clear callbacks
        poseProvider.stop()
        poseProvider.onPoseDetected = nil
    resetPoseSmoothingState()
        
        // Stop camera session
        stopCamera()
        
        // Stop CoreMotion updates and clear motion manager
        motionManager?.stopDeviceMotionUpdates()
        motionManager = nil
        
        // Stop ARKit engine
        universal3DEngine.stop()
        
        // End SPARC service session
        _ = sparcService.endSession() // ignore result
        
        // Stop performance monitoring and log results
        performanceMonitor.stopMonitoring()
        repDetectionService.resetForNewSession()
        
        // Log performance summary
        if let avgMetrics = performanceMonitor.averageMetrics {
            FlexaLog.motion.info("Session Performance Summary: Memory=\(String(format: "%.1f", avgMetrics.memoryUsageMB))MB, CPU=\(String(format: "%.1f", avgMetrics.cpuUsagePercent))%, FPS=\(String(format: "%.1f", avgMetrics.frameRate))")
        }
        
        // Clear session state and data on main thread
        DispatchQueue.main.async {
            self.isSessionActive = false
            self.isARKitRunning = false
            
            // Clear accumulated session data to prevent contamination between games
            self.romPerRep.removeAll()
            self.sparcHistory.removeAll()
            self.romHistory.removeAll()
            self.romSamples.removeAll()
            
            // Reset counters and measurements
            self.currentReps = 0
            self.currentROM = 0
            self.maxROM = 0
            self.lastRepROM = 0
            self.repPeakROM = 0
            
            FlexaLog.motion.info("🧹 [Motion] Session data cleared — ready for new game")
        }
        
        FlexaLog.motion.info("All services stopped and resources cleaned up")
    }
    
    // MARK: - Error Recovery Methods
    

    
    
    private func fallbackToARKitMode() {
        guard !isCameraExercise else {
            FlexaLog.motion.warning("Cannot fallback to ARKit mode for camera game")
            return
        }
        
        // Stop Vision if running
        poseProvider.stop()
        
        // Start ARKit mode
        do {
            try startARKitWithErrorHandling()
            setROMTrackingMode(.arkit)
            FlexaLog.motion.info("Successfully fell back to ARKit mode")
        } catch {
            errorHandler.handleError(.arkitSessionFailed(error))
        }
    }
    
    private func restartCurrentSession() {
        let currentGame = currentGameType
        
        // Stop current session
        stopSession()
        
        // Wait briefly for cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // Restart session
            self.startGameSession(gameType: currentGame)
            FlexaLog.motion.info("Session restarted successfully")
        }
    }
    
    private func enableGracefulDegradation() {
        // Continue with basic ROM calculation even without full calibration
        FlexaLog.motion.info("Enabling graceful degradation mode")
        
        // Use default values where calibration is missing
        if !universal3DEngine.isCalibrated {
            FlexaLog.motion.warning("Using default calibration values for graceful degradation")
        }
    }
    
    private func retryCurrentOperation() {
        // Retry the last failed operation
        if isCameraExercise {
            startCamera { [weak self] success in
                if !success {
                    self?.errorHandler.handleError(.cameraSessionFailed(NSError(domain: "SimpleMotionService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Retry failed"])))
                }
            }
        } else {
            do {
                try startARKitWithErrorHandling()
            } catch {
                errorHandler.handleError(.arkitSessionFailed(error))
            }
        }
    }
    
    private func handleCriticalFailure() {
        // Stop all operations
        stopSession()
        
        DispatchQueue.main.async {
            self.lastError = "Critical system failure - please restart the app"
        }
        
        FlexaLog.motion.critical("Critical failure - all ROM operations stopped")
    }
    
    func getSessionData() -> [String: Any] {
        let sessionData: [String: Any] = [
            "gameType": currentGameType.displayName,
            "sessionStartTime": sessionStartTime,
            "sessionDuration": Date().timeIntervalSince1970 - sessionStartTime,
            "currentReps": currentReps,
            "maxROM": maxROM,
            "romHistory": romHistory.allElements,
            "romPerRep": romPerRep.allElements,
            "sparcHistory": sparcHistory.allElements,
            "isSessionActive": isSessionActive
        ]
        
        saveSessionFile()
        return sessionData
    }
    
    func getFullSessionData(
        overrideScore: Int? = nil,
        overrideExerciseType: String? = nil,
        overrideTimestamp: Date? = nil
    ) -> ExerciseSessionData {
        let duration = Date().timeIntervalSince1970 - sessionStartTime
        let finalSPARC = sparcService.getCurrentSPARC()

        let sanitizedMaxROM = maxROM.isFinite ? maxROM : 0
        let perRepROM = romPerRep.allElements.filter { $0.isFinite }
        let sparcHistoryValues = sparcHistory.allElements.filter { $0.isFinite }
        let sparcPoints: [SPARCPoint] = sparcService.getSPARCDataPoints()
            .filter { $0.sparcValue.isFinite }
            .map { dataPoint in
                SPARCPoint(sparc: dataPoint.sparcValue, timestamp: dataPoint.timestamp)
            }
        let sanitizedSPARCScore = finalSPARC.isFinite ? finalSPARC : 0

        let resolvedScore = overrideScore ?? (currentReps * 10)
        let resolvedExercise = overrideExerciseType ?? currentGameType.displayName
        let resolvedTimestamp = overrideTimestamp ?? Date()

        return ExerciseSessionData(
            exerciseType: resolvedExercise,
            score: resolvedScore,
            reps: currentReps,
            maxROM: sanitizedMaxROM,
            duration: duration,
            timestamp: resolvedTimestamp,
            romHistory: perRepROM,
            repTimestamps: romPerRepTimestampsDates,
            sparcHistory: sparcHistoryValues,
            romData: [],
            sparcData: sparcPoints,
            sparcScore: sanitizedSPARCScore
        )
    }

    func buildSessionNotificationPayload(from data: ExerciseSessionData) -> [AnyHashable: Any] {
        var userInfo: [AnyHashable: Any] = [
            "score": data.score,
            "reps": data.reps,
            "maxROM": data.maxROM,
            "sparcScore": data.sparcScore,
            "romPerRep": data.romHistory,
            "sparcHistory": data.sparcHistory,
            "duration": data.duration,
            "timestamp": data.timestamp.timeIntervalSince1970,
            "repTimestamps": data.repTimestamps.map { $0.timeIntervalSince1970 }
        ]

        if !data.sparcData.isEmpty {
            let sparcTimeline = data.sparcData.map { point in
                [
                    "timestamp": point.timestamp.timeIntervalSince1970,
                    "sparc": point.sparc
                ]
            }
            userInfo["sparcDataPoints"] = sparcTimeline
        }

        if !data.romData.isEmpty {
            let romTimeline = data.romData.map { point in
                [
                    "timestamp": point.timestamp.timeIntervalSince1970,
                    "angle": point.angle
                ]
            }
            userInfo["romDataPoints"] = romTimeline
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        if let encoded = try? encoder.encode(data) {
            userInfo["sessionDataJSON"] = encoded
        }

        return userInfo
    }
    
    func updateROMFromARKit(_ rom: Double) {
        // Validate and normalize ROM for consistency across all games
        let validatedROM = validateAndNormalizeROM(rom)
        
        // Update current ROM from ARKit (for handheld games) on main thread
        DispatchQueue.main.async {
            self.currentROM = validatedROM
            if validatedROM > self.maxROM {
                self.maxROM = validatedROM
            }
            
            // Add to ROM history for continuous tracking
            self.romHistory.append(validatedROM)
            
            // For handheld games, keep track of the peak ROM during the current rep window.
            // This ensures rep ROM reflects the maximum achieved in that swing.
            if !self.isCameraExercise {
                if validatedROM > self.repPeakROM {
                    self.repPeakROM = validatedROM
                }
            }
        }
        
        // Note: SPARC for handheld games comes from motion sensor data in startDeviceMotionUpdatesLoop()
        // ARKit position data is only used for ROM calculation, not SPARC
    }
    
    private func saveSessionFile() {
        let sparcTimeline = sparcService
            .getSPARCDataPoints()
            .filter { $0.sparcValue.isFinite }
            .map { dataPoint in
                SPARCPoint(sparc: dataPoint.sparcValue, timestamp: dataPoint.timestamp)
            }

        let sessionFile = SessionFile(
            exerciseType: currentGameType.rawValue,
            timestamp: Date(timeIntervalSince1970: sessionStartTime),
            romPerRep: romPerRep.allElements,
            sparcHistory: sparcHistory.allElements,
            romHistory: romHistory.allElements,
            maxROM: maxROM,
            reps: currentReps,
            sparcDataPoints: sparcTimeline
        )
        
    LocalDataManager.shared.saveSessionFile(sessionFile)
    FlexaLog.motion.info("💾 [Session] Saved session file for enhanced graphing")
    }
    
    /// Create comprehensive session data for complete tracking and analysis
    func createComprehensiveSessionData(
        preSurvey: PreSurveyData,
        postSurvey: PostSurveyData?,
        goalsBefore: UserGoals,
        goalsAfter: UserGoals
    ) -> ComprehensiveSessionData {
        let duration = Date().timeIntervalSince1970 - sessionStartTime
        
        // Create performance data from current session
        // Convert TimeInterval timestamps to Date for the performance payload
        let repDates = romPerRepTimestamps.allElements.map { Date(timeIntervalSince1970: $0) }
        let sparcHistoryValues = sparcHistory.allElements.filter { $0.isFinite }
        let sparcTimeline = sparcService
            .getSPARCDataPoints()
            .filter { $0.sparcValue.isFinite }

        let performanceData = ExercisePerformanceData(
            score: currentReps * 10, // Base score calculation
            reps: currentReps,
            duration: duration,
            romData: romHistory.allElements,
            romPerRep: romPerRep.allElements,
            repTimestamps: repDates,
            sparcDataPoints: sparcTimeline,
            movementQualityScores: sparcHistoryValues, // Use SPARC as quality proxy
            aiScore: calculateAIScore(),
            aiFeedback: generateAIFeedback(),
            sparcScore: sparcService.getCurrentSPARC(),
            gameSpecificData: currentGameType.rawValue,
            accelAvg: nil, // Could be enhanced with motion sensor aggregates
            accelPeak: nil,
            gyroAvg: nil,
            gyroPeak: nil
        )
        
        let sessionNumber = LocalDataManager.shared.nextSessionNumber()
        
        return ComprehensiveSessionData(
            userID: "anonymous", // Using anonymous auth
            sessionNumber: sessionNumber,
            exerciseName: currentGameType.displayName,
            duration: duration,
            performanceData: performanceData,
            preSurvey: preSurvey,
            postSurvey: postSurvey,
            goalsBefore: goalsBefore,
            goalsAfter: goalsAfter,
            streakAtSession: LocalDataManager.shared.getCachedStreak()
        )
    }
    
    /// Save comprehensive session data locally and optionally to Appwrite (backend)
    func saveComprehensiveSession(
        preSurvey: PreSurveyData,
        postSurvey: PostSurveyData?,
        goalsBefore: UserGoals,
        goalsAfter: UserGoals
    ) {
        let comprehensiveSession = createComprehensiveSessionData(
            preSurvey: preSurvey,
            postSurvey: postSurvey,
            goalsBefore: goalsBefore,
            goalsAfter: goalsAfter
        )
        
        // Save locally first
        LocalDataManager.shared.saveComprehensiveSession(comprehensiveSession)
        
        // Also save the session file for graphing
        saveSessionFile()
        
    FlexaLog.motion.info("💾 [Session] Saved comprehensive session data with ROM: \(self.maxROM, privacy: .public)° reps: \(self.currentReps)")
    }
    
    private func calculateAIScore() -> Int {
        // Simple AI score calculation based on ROM and consistency
        let romScore = min(100, Int(maxROM * 1.2)) // ROM contributes to score
        let consistencyScore = calculateConsistencyScore()
        let sparcScore = Int(sparcService.getCurrentSPARC())
        
        return min(100, (romScore + consistencyScore + sparcScore) / 3)
    }
    
    private func calculateConsistencyScore() -> Int {
        let romValues = romPerRep.allElements
        guard romValues.count > 1 else { return 50 }
        
        let mean = romValues.reduce(0, +) / Double(romValues.count)
        let variance = romValues.map { pow($0 - mean, 2) }.reduce(0, +) / Double(romValues.count)
        let standardDeviation = sqrt(variance)
        let coefficientOfVariation = standardDeviation / mean
        
        return max(0, min(100, Int(100 - (coefficientOfVariation * 100))))
    }
    
    private func generateAIFeedback() -> String {
        let romValues = romPerRep.allElements
        guard !romValues.isEmpty else { return "Complete more reps for detailed feedback." }
        
        let avgROM = romValues.reduce(0, +) / Double(romValues.count)
        let consistency = calculateConsistencyScore()
        
        var feedback = ""
        
        if avgROM > 45 {
            feedback += "Excellent range of motion! "
        } else if avgROM > 25 {
            feedback += "Good range of motion. "
        } else {
            feedback += "Try to increase your range of motion gradually. "
        }
        
        if consistency > 80 {
            feedback += "Very consistent movement pattern."
        } else if consistency > 60 {
            feedback += "Good consistency in your movements."
        } else {
            feedback += "Focus on maintaining consistent movement patterns."
        }
        
        return feedback
    }
    
    private func updatePreviewSession(_ session: AVCaptureSession?) {
        if Thread.isMainThread {
            FlexaLog.motion.info("📹 [PREVIEW] Updating preview session to: \(session?.debugDescription ?? "nil") on main thread")
            previewSession = session
            FlexaLog.motion.info("📹 [PREVIEW] Preview session updated successfully - isRunning: \(session?.isRunning ?? false)")
        } else {
            DispatchQueue.main.async { [weak self] in
                FlexaLog.motion.info("📹 [PREVIEW] Updating preview session to: \(session?.debugDescription ?? "nil") async on main thread")
                self?.previewSession = session
                FlexaLog.motion.info("📹 [PREVIEW] Preview session updated successfully async - isRunning: \(session?.isRunning ?? false)")
            }
        }
    }

    func ensureCameraPreviewReady() {
        FlexaLog.motion.info("📹 [PREVIEW-READY] Ensuring camera preview is ready")
        startCamera { success in
            if success {
                FlexaLog.motion.info("📹 [PREVIEW-READY] Camera preview warmed successfully")
            } else {
                FlexaLog.motion.error("📹 [PREVIEW-READY] Failed to warm camera preview session")
            }
        }
    }

    func startCamera(completion: @escaping (Bool) -> Void) {
        FlexaLog.motion.info("📹 [CAMERA] ========== startCamera called ==========")
        FlexaLog.motion.info("📹 [CAMERA] Current thread: \(Thread.current.isMainThread ? "MAIN" : "BACKGROUND")")
        
        cameraStartupLock.lock()
        let alreadyStarting = isStartingCamera
        let existingSession = captureSession
        cameraStartupLock.unlock()
        
        FlexaLog.motion.info("📹 [CAMERA] Status check: isStartingCamera=\(alreadyStarting), existingSession=\(existingSession != nil ? "YES" : "NO")")
        
        // Check if camera startup is already in progress
        if alreadyStarting {
            FlexaLog.motion.info("📹 [CAMERA] Camera startup already in progress - waiting and retrying in 0.1s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.startCamera(completion: completion)
            }
            return
        }
        
        FlexaLog.motion.info("📹 [CAMERA] Canceling any pending teardown work items")
        cameraTeardownWorkItem?.cancel()
        cameraTeardownWorkItem = nil

        // If we already have a configured session, resume it immediately for instant preview
        if let existingSession = captureSession {
            FlexaLog.motion.info("📹 [CAMERA] ✅ Found existing session - isRunning: \(existingSession.isRunning)")
            if existingSession.isRunning {
                FlexaLog.motion.info("📹 [CAMERA] ✅ Existing session already running - updating preview and completing")
                DispatchQueue.main.async {
                    self.updatePreviewSession(existingSession)
                    completion(true)
                }
            } else {
                FlexaLog.motion.info("📹 [CAMERA] ⚠️ Existing session not running - resuming it now")
                resumeExistingSession(existingSession, completion: completion)
            }
            return
        }

        FlexaLog.motion.info("📹 [CAMERA] 🆕 No existing session - performing fresh startup")
        cameraStartupLock.lock()
        isStartingCamera = true
        cameraStartupLock.unlock()
        FlexaLog.motion.info("📹 [CAMERA] Set isStartingCamera=true, dispatching to main queue")
        
        DispatchQueue.main.async {
            FlexaLog.motion.info("📹 [CAMERA] Main queue: calling performCameraStartup")
            self.performCameraStartup(completion: completion)
        }
    }

    private func resumeExistingSession(_ session: AVCaptureSession, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            if let output = self.videoOutput {
                output.setSampleBufferDelegate(self, queue: self.cameraQueue)
            }

            if !session.isRunning {
                session.startRunning()
            }

            let running = session.isRunning

            DispatchQueue.main.async {
                if running {
                    self.updatePreviewSession(session)
                    NotificationCenter.default.post(name: .SharedCaptureSessionReady, object: session)
                    FlexaLog.motion.info("Camera session resumed successfully")
                } else {
                    self.updatePreviewSession(nil)
                    FlexaLog.motion.error("Camera session resume failed")
                }
                completion(running)
            }
        }
    }
    
    private func performCameraStartup(completion: @escaping (Bool) -> Void) {
        FlexaLog.motion.info("📹 [CAMERA-STARTUP] ========== performCameraStartup ENTERED ==========")
        let startupStartTime = Date()
        FlexaLog.motion.info("📹 [CAMERA-STARTUP] Phase 0: Starting camera initialization at \(startupStartTime)")
        
        guard captureSession == nil else {
            FlexaLog.motion.info("📹 [CAMERA-STARTUP] ⚠️ captureSession already exists (race condition?) - using existing")
            updatePreviewSession(captureSession)
            completion(true)
            return
        }
        
        FlexaLog.motion.info("📹 [CAMERA-STARTUP] captureSession is nil - proceeding with fresh initialization")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { 
                    self?.isStartingCamera = false
                    completion(false) 
                }
                return
            }
            
            do {
                FlexaLog.motion.info("📹 [CAMERA-STARTUP] Phase 1: Checking permissions... (\(String(format: "%.3f", Date().timeIntervalSince(startupStartTime)))s)")
                
                // Check camera permission first
                guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
                    // Request permission if not granted
                    AVCaptureDevice.requestAccess(for: .video) { granted in
                        if granted {
                            // Retry camera setup after permission granted
                            DispatchQueue.global(qos: .userInitiated).async {
                                self.startCamera(completion: completion)
                            }
                        } else {
                            DispatchQueue.main.async { 
                                self.isStartingCamera = false
                                completion(false) 
                            }
                        }
                    }
                    return
                }
                
                FlexaLog.motion.info("📹 [CAMERA-STARTUP] Phase 2: Creating AVCaptureSession... (\(String(format: "%.3f", Date().timeIntervalSince(startupStartTime)))s)")
                let session = AVCaptureSession()
                
                // Small delay to allow XPC communication to stabilize (prevents FigCapture errors)
                Thread.sleep(forTimeInterval: 0.05)
                
                // Begin configuration to prevent XPC race conditions
                FlexaLog.motion.info("📹 [CAMERA-STARTUP] Phase 3: Beginning session configuration... (\(String(format: "%.3f", Date().timeIntervalSince(startupStartTime)))s)")
                session.beginConfiguration()
                session.sessionPreset = .vga640x480 // Prefer 640x480 for Vision
                FlexaLog.motion.info("📹 [CAMERA-STARTUP] Phase 4: Session preset set to VGA 640x480 (\(String(format: "%.3f", Date().timeIntervalSince(startupStartTime)))s)")
                
                // Try to get front camera first, then fallback to any available camera (for simulator support)
                var camera: AVCaptureDevice?
                camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                
                if camera != nil {
                    FlexaLog.motion.debug("✅ [Camera] Selected front-facing device for capture")
                } else {
                    FlexaLog.motion.warning("⚠️ [Camera] Front camera unavailable — attempting fallback selection")
                    // Fallback for simulator or devices without front camera
                    camera = AVCaptureDevice.default(for: .video)
                    if let fallbackDevice = camera {
                        FlexaLog.motion.info("✅ [Camera] Using fallback video device: \(fallbackDevice.localizedName, privacy: .public)")
                    }
                }
                
                guard let captureDevice = camera else {
                    FlexaLog.motion.error("❌ [Camera] No capture device available — simulator or hardware issue suspected")
                    // Use AVCaptureDeviceDiscoverySession for iOS 10+
                    let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified)
                    FlexaLog.motion.debug("📱 [Camera] Discovery session devices: \(discoverySession.devices.map { $0.localizedName }, privacy: .public)")
                    throw ROMErrorHandler.ROMError.cameraAccessDenied
                }
                
                // Configure camera format before creating input
                do {
                    try captureDevice.lockForConfiguration()
                    
                    // Find a compatible format for the session preset
                    let formats = captureDevice.formats.filter { format in
                        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                        return dimensions.width >= 640 && dimensions.height >= 480
                    }
                    
                    if let compatibleFormat = formats.first {
                        captureDevice.activeFormat = compatibleFormat
                        FlexaLog.motion.info("Set camera format: \(compatibleFormat)")
                    }
                    
                    // Set frame rate after format is set
                    if #available(iOS 15.0, *) {
                        captureDevice.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: 30)
                        captureDevice.activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: 30)
                    }
                    
                    captureDevice.unlockForConfiguration()
                } catch {
                    FlexaLog.motion.warning("Failed to configure camera format: \(error.localizedDescription)")
                    // Continue with default format
                }
                
                let input = try AVCaptureDeviceInput(device: captureDevice)
                self.captureDevice = captureDevice
                
                let output = AVCaptureVideoDataOutput()
                // Use full-range 420f for efficient Vision processing
                output.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                ]
                output.alwaysDiscardsLateVideoFrames = true
                output.setSampleBufferDelegate(self, queue: self.cameraQueue)
                
                guard session.canAddInput(input) && session.canAddOutput(output) else {
                    throw ROMErrorHandler.ROMError.cameraSessionFailed(NSError(domain: "SimpleMotionService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot add camera input/output"]))
                }
                
                session.addInput(input)
                session.addOutput(output)
                
                // Configure connection orientation/mirroring
                if let connection = output.connection(with: .video) {
                    if connection.isVideoOrientationSupported {
                        connection.videoOrientation = .portrait
                    }
                    if connection.isVideoMirroringSupported {
                        if connection.automaticallyAdjustsVideoMirroring {
                            connection.automaticallyAdjustsVideoMirroring = false
                        }
                        // Mirror only if it's a front camera
                        connection.isVideoMirrored = (captureDevice.position == .front)
                        FlexaLog.motion.debug("🎥 [Camera] Video mirroring set to: \(connection.isVideoMirrored) position: \(captureDevice.position.rawValue)")
                    }
                }
                
                // Commit configuration before storing references and starting
                FlexaLog.motion.info("📹 [CAMERA-STARTUP] Phase 7: Committing session configuration... (\(String(format: "%.3f", Date().timeIntervalSince(startupStartTime)))s)")
                session.commitConfiguration()
                FlexaLog.motion.info("📹 [CAMERA-STARTUP] Phase 8: Session configuration committed (\(String(format: "%.3f", Date().timeIntervalSince(startupStartTime)))s)")
                
                // Small delay after commit to ensure configuration is fully applied
                Thread.sleep(forTimeInterval: 0.05)
                
                self.captureSession = session
                self.videoOutput = output
                
                FlexaLog.motion.info("📹 [CAMERA-STARTUP] Phase 9: Starting session.startRunning()... (\(String(format: "%.3f", Date().timeIntervalSince(startupStartTime)))s)")
                session.startRunning()
                FlexaLog.motion.info("📹 [CAMERA-STARTUP] Phase 10: session.startRunning() returned (\(String(format: "%.3f", Date().timeIntervalSince(startupStartTime)))s)")
                
                // Verify session is running
                let running = session.isRunning
                if running {
                    self.updatePreviewSession(session)
                    FlexaLog.motion.info("✅ [Camera] Capture session running successfully")
                } else {
                    self.updatePreviewSession(nil)
                    FlexaLog.motion.error("❌ [Camera] Capture session failed to start")
                }
                
                // Notify any listeners (e.g., preview views) that the shared session is ready
                if running {
                    NotificationCenter.default.post(name: .SharedCaptureSessionReady, object: session)
                }
                
                FlexaLog.motion.info("Camera session started successfully")
                DispatchQueue.main.async { 
                    self.cameraStartupLock.lock()
                    self.isStartingCamera = false
                    self.cameraStartupLock.unlock()
                    completion(running) 
                }
                
            } catch let error as ROMErrorHandler.ROMError {
                FlexaLog.motion.error("📹 [CAMERA] ROM error during camera setup: \(error)")
                self.errorHandler.handleError(error)
                DispatchQueue.main.async { 
                    self.cameraStartupLock.lock()
                    self.isStartingCamera = false
                    self.cameraStartupLock.unlock()
                    completion(false) 
                }
            } catch {
                FlexaLog.motion.error("📹 [CAMERA] General error during camera setup: \(error)")
                self.errorHandler.handleError(.cameraSessionFailed(error))
                DispatchQueue.main.async { 
                    self.cameraStartupLock.lock()
                    self.isStartingCamera = false
                    self.cameraStartupLock.unlock()
                    completion(false) 
                }
            }
        }
    }
    
    func stopCamera(tearDownCompletely: Bool = false) {
        cameraTeardownWorkItem?.cancel()
        cameraTeardownWorkItem = nil

        guard let session = captureSession else {
            if tearDownCompletely {
                updatePreviewSession(nil)
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Notification.Name("SharedCaptureSessionStopped"), object: nil)
                }
            }
            return
        }

        if tearDownCompletely {
            updatePreviewSession(nil)
            shutdownCameraSession(postNotification: true)
            return
        }

        if session.isRunning {
            session.stopRunning()
        }

        updatePreviewSession(nil)

        videoOutput?.setSampleBufferDelegate(nil, queue: nil)

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("SharedCaptureSessionStopped"), object: nil)
        }

        scheduleCameraTeardown()
    }

    private func scheduleCameraTeardown(after delay: TimeInterval = 30.0) {
        cameraTeardownWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.shutdownCameraSession(postNotification: false)
        }
        cameraTeardownWorkItem = workItem
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func shutdownCameraSession(postNotification: Bool) {
        let sessionToStop = captureSession
        let outputToClean = videoOutput

        captureSession = nil
        captureDevice = nil
        videoOutput = nil
        cameraTeardownWorkItem = nil
    updatePreviewSession(nil)

        let shouldNotify = postNotification && ((sessionToStop != nil) || (outputToClean != nil))

        if let output = outputToClean {
            output.setSampleBufferDelegate(nil, queue: nil)
        }

        guard let session = sessionToStop else {
            if shouldNotify {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Notification.Name("SharedCaptureSessionStopped"), object: nil)
                }
            }
            return
        }

        let cleanupQueue = DispatchQueue(label: "camera.cleanup", qos: .userInitiated)
        cleanupQueue.async {
            if session.isRunning {
                session.stopRunning()
                FlexaLog.motion.info("🛑 [Camera] Session stopRunning() called")
                
                // Wait for session to fully stop (prevents FigCapture XPC errors)
                var attempts = 0
                while session.isRunning && attempts < 10 {
                    Thread.sleep(forTimeInterval: 0.05)
                    attempts += 1
                }
                
                if session.isRunning {
                    FlexaLog.motion.warning("⚠️ [Camera] Session still running after 10 attempts")
                } else {
                    FlexaLog.motion.info("✅ [Camera] Session fully stopped after \(attempts) attempts")
                }
            }

            Thread.sleep(forTimeInterval: 0.1)

            session.beginConfiguration()
            for output in session.outputs {
                session.removeOutput(output)
            }
            for input in session.inputs {
                session.removeInput(input)
            }
            session.commitConfiguration()

            FlexaLog.motion.info("🛑 [Camera] Properly stopped and cleaned up capture session")

            if shouldNotify {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Notification.Name("SharedCaptureSessionStopped"), object: nil)
                }
            }
        }
    }
    
    // Frame counting for debugging
    private var captureFrameCount: Int = 0
    
    @objc func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        captureFrameCount += 1
        
        // Log every 30th frame to avoid spam
        if captureFrameCount % 30 == 0 {
            FlexaLog.motion.debug("📹 [CAPTURE] Frame #\(self.captureFrameCount) received - session active: \(self.isSessionActive)")
        }
        
        guard isSessionActive else { 
            if captureFrameCount % 30 == 0 {
                FlexaLog.motion.warning("📹 [CAPTURE] Frame received but session not active - dropping")
            }
            return 
        }
        
        // Throttle Vision processing under memory pressure and drain autorelease pool per frame
        let now = CFAbsoluteTimeGetCurrent()
        let minInterval = (memoryPressureLevel == .normal) ? minVisionFrameIntervalNormal : minVisionFrameIntervalThrottled
        if now - lastVisionProcessTime < minInterval {
            return
        }
        lastVisionProcessTime = now
        
        if captureFrameCount % 30 == 0 {
            FlexaLog.motion.debug("📹 [CAPTURE] Processing frame #\(self.captureFrameCount) through Vision")
        }
        
        autoreleasepool {
            // Process camera frame for pose detection
            poseProvider.processFrame(sampleBuffer)
        }
    }

    private func smoothPoseKeypoints(_ keypoints: SimplifiedPoseKeypoints) -> SimplifiedPoseKeypoints {
        let previous = lastSmoothedPose
        let deltaTime = max(1.0 / 120.0, keypoints.timestamp - (previous?.timestamp ?? keypoints.timestamp))

        func smooth(_ joint: PoseJoint, newPoint: CGPoint?) -> CGPoint? {
            let previousPoint = point(from: previous, joint: joint)
            return smoothPoint(for: joint,
                               newPoint: newPoint,
                               previous: previousPoint,
                               timestamp: keypoints.timestamp,
                               deltaTime: deltaTime)
        }

        let smoothed = SimplifiedPoseKeypoints(
            timestamp: keypoints.timestamp,
            leftWrist: smooth(.leftWrist, newPoint: keypoints.leftWrist),
            rightWrist: smooth(.rightWrist, newPoint: keypoints.rightWrist),
            leftElbow: smooth(.leftElbow, newPoint: keypoints.leftElbow),
            rightElbow: smooth(.rightElbow, newPoint: keypoints.rightElbow),
            leftShoulder: smooth(.leftShoulder, newPoint: keypoints.leftShoulder),
            rightShoulder: smooth(.rightShoulder, newPoint: keypoints.rightShoulder),
            nose: smooth(.nose, newPoint: keypoints.nose),
            neck: smooth(.neck, newPoint: keypoints.neck),
            leftHip: smooth(.leftHip, newPoint: keypoints.leftHip),
            rightHip: smooth(.rightHip, newPoint: keypoints.rightHip),
            leftEye: keypoints.leftEye,
            rightEye: keypoints.rightEye,
            leftShoulder3D: keypoints.leftShoulder3D,
            rightShoulder3D: keypoints.rightShoulder3D,
            leftElbow3D: keypoints.leftElbow3D,
            rightElbow3D: keypoints.rightElbow3D,
            leftShoulderConfidence: keypoints.leftShoulderConfidence,
            rightShoulderConfidence: keypoints.rightShoulderConfidence,
            leftElbowConfidence: keypoints.leftElbowConfidence,
            rightElbowConfidence: keypoints.rightElbowConfidence,
            neckConfidence: keypoints.neckConfidence
        )

        lastSmoothedPose = smoothed
        return smoothed
    }

    private func smoothPoint(for joint: PoseJoint,
                             newPoint: CGPoint?,
                             previous: CGPoint?,
                             timestamp: TimeInterval,
                             deltaTime: TimeInterval) -> CGPoint? {
        guard let newPoint else {
            if let cached = poseDropoutCache[joint], timestamp <= cached.expiry {
                return cached.point
            }
            poseDropoutCache.removeValue(forKey: joint)
            return nil
        }

        let anchor = previous ?? newPoint
        let delta = CGPoint(x: newPoint.x - anchor.x, y: newPoint.y - anchor.y)
        let velocity = CGFloat(hypot(delta.x, delta.y)) / max(CGFloat(deltaTime), 1e-3)

        let baseAlpha: CGFloat
        if joint.isWrist {
            baseAlpha = 0.58
        } else if joint.isElbow {
            baseAlpha = 0.48
        } else {
            baseAlpha = 0.38
        }

        let dynamicBoost = min(0.25, max(0.0, (velocity - 85.0) / 650.0))
        let alpha = min(0.85, max(0.28, baseAlpha + dynamicBoost))

        let smoothed = CGPoint(
            x: anchor.x + alpha * (newPoint.x - anchor.x),
            y: anchor.y + alpha * (newPoint.y - anchor.y)
        )

        poseDropoutCache[joint] = PoseCacheEntry(point: smoothed, expiry: timestamp + poseDropoutGracePeriod)
        return smoothed
    }

    private func point(from keypoints: SimplifiedPoseKeypoints?, joint: PoseJoint) -> CGPoint? {
        guard let keypoints else { return nil }
        switch joint {
        case .leftWrist: return keypoints.leftWrist
        case .rightWrist: return keypoints.rightWrist
        case .leftElbow: return keypoints.leftElbow
        case .rightElbow: return keypoints.rightElbow
        case .leftShoulder: return keypoints.leftShoulder
        case .rightShoulder: return keypoints.rightShoulder
        case .neck: return keypoints.neck
        case .nose: return keypoints.nose
        case .leftHip: return keypoints.leftHip
        case .rightHip: return keypoints.rightHip
        }
    }
    
    private func processPoseKeypointsInternal(_ keypoints: SimplifiedPoseKeypoints) {
        let smoothedKeypoints = smoothPoseKeypoints(keypoints)
        // Calculate Vision-based ROM from smoothed pose landmarks on background thread
        let visionROM = self.calculateVisionROM(from: smoothedKeypoints)
        
        DispatchQueue.main.async {
            // Update published pose keypoints
            self.poseKeypoints = smoothedKeypoints
            self.currentPoseKeypoints = smoothedKeypoints
            
            // Skeleton lines removed - no longer needed
            
            // Update ROM for camera games only
            if self.isCameraExercise {
                // Validate and normalize ROM for consistency across all games
                let validatedROM = self.validateAndNormalizeROM(visionROM)
                
                self.currentROM = validatedROM
                
                if validatedROM > self.maxROM {
                    self.maxROM = validatedROM
                }
                
                // Add to ROM history
                self.romHistory.append(validatedROM)
                
                // Feed wrist data to SPARC for camera games
                self.feedWristDataToSPARC(smoothedKeypoints)
                
                // Update rep detection with validated Vision-based ROM (camera games only)
                self.updateRepDetection(rom: validatedROM, timestamp: Date().timeIntervalSince1970)
                
                FlexaLog.motion.debug("📐 [ROM Consistency] Vision ROM raw=\(String(format: "%.1f", visionROM))° validated=\(String(format: "%.1f", validatedROM))°")
            }
        }
    }
    
    private func calculateVisionROM(from keypoints: SimplifiedPoseKeypoints) -> Double {
        // Use detected active arm for ROM calculation
        let activeSide = keypoints.phoneArm
        
        // Get landmarks for the active arm
        let (shoulder, elbow, wrist) = (activeSide == .left) ? 
            (keypoints.leftShoulder, keypoints.leftElbow, keypoints.leftWrist) : 
            (keypoints.rightShoulder, keypoints.rightElbow, keypoints.rightWrist)
        
        guard let shoulder = shoulder, let elbow = elbow else {
            // Fallback to best available arm
            if let leftShoulder = keypoints.leftShoulder, let leftElbow = keypoints.leftElbow {
                if preferredCameraJoint == .elbow, let lw = keypoints.leftWrist {
                    return calculateElbowFlexionAngle(shoulder: leftShoulder, elbow: leftElbow, wrist: lw)
                } else {
                    return calculateArmAngle(shoulder: leftShoulder, elbow: leftElbow)
                }
            } else if let rightShoulder = keypoints.rightShoulder, let rightElbow = keypoints.rightElbow {
                if preferredCameraJoint == .elbow, let rw = keypoints.rightWrist {
                    return calculateElbowFlexionAngle(shoulder: rightShoulder, elbow: rightElbow, wrist: rw)
                } else {
                    return calculateArmAngle(shoulder: rightShoulder, elbow: rightElbow)
                }
            }
            return 0.0
        }
        if preferredCameraJoint == .elbow, let wrist = wrist {
            return calculateElbowFlexionAngle(shoulder: shoulder, elbow: elbow, wrist: wrist)
        } else {
            // Armpit ROM: angle of upper arm relative to vertical
            return calculateArmAngle(shoulder: shoulder, elbow: elbow)
        }
    }
    
    private func calculateArmAngle(shoulder: CGPoint, elbow: CGPoint) -> Double {
        // Calculate angle from shoulder to elbow relative to vertical
        let deltaY = shoulder.y - elbow.y
        let deltaX = shoulder.x - elbow.x
        let angle = atan2(deltaY, deltaX) * 180.0 / .pi
        
        // Convert to positive ROM value
        return abs(angle) // Use absolute angle from neutral position
    }
    
    // Elbow flexion: angle between upper arm (shoulder→elbow) and forearm (wrist→elbow)
    private func calculateElbowFlexionAngle(shoulder: CGPoint, elbow: CGPoint, wrist: CGPoint) -> Double {
        let u = CGVector(dx: shoulder.x - elbow.x, dy: shoulder.y - elbow.y)
        let f = CGVector(dx: wrist.x - elbow.x, dy: wrist.y - elbow.y)
        let uLen = max(1e-6, hypot(u.dx, u.dy))
        let fLen = max(1e-6, hypot(f.dx, f.dy))
        let dotVal = (u.dx * f.dx + u.dy * f.dy) / (uLen * fLen)
        let clamped = max(-1.0, min(1.0, dotVal))
        let radians = acos(clamped)
        let degrees = radians * 180.0 / .pi
        return max(0.0, min(180.0, degrees))
    }
    
    private func calculateVisionSmoothness(from keypoints: SimplifiedPoseKeypoints) {
        // Get wrist position for smoothness calculation
        let activeSide = keypoints.phoneArm
        let wristPosition = (activeSide == .left) ? keypoints.leftWrist : keypoints.rightWrist
        
        guard let wrist = wristPosition else { return }
        
        // Add wrist position to SPARC service for vision-based smoothness
        sparcService.addVisionMovement(
            timestamp: Date().timeIntervalSince1970,
            position: wrist
        )
    }
    
    
    /// Feed wrist data to SPARC for camera games
    private func feedWristDataToSPARC(_ keypoints: SimplifiedPoseKeypoints) {
        // Extract active wrist position for SPARC analysis
        let activeSide = keypoints.phoneArm
        let wrist = (activeSide == .left) ? keypoints.leftWrist : keypoints.rightWrist
        guard let wrist else { return }
        
        // Add wrist position to SPARC service for vision-based smoothness
        sparcService.addVisionMovement(
            timestamp: Date().timeIntervalSince1970,
            position: wrist
        )
    }
    
    // MARK: - Calibration Methods
    private var reformedCalibrationInProgress = false

    /// Automatic reformed calibration flow: captures 0°, 90°, 180° using ARKit
    func runReformedCalibrationFlow(gameType: String? = nil, completion: ((Bool) -> Void)? = nil) {
        guard !reformedCalibrationInProgress else { completion?(false); return }
        reformedCalibrationInProgress = true
        let calMgr = CalibrationDataManager.shared
        calMgr.startCalibrationProcess()
    FlexaLog.motion.info("🎯 [AutoCal] Hold phone at shoulder (0°). Capturing in 1.5s…")
        
        func snap(_ angle: CalibrationDataManager.CalibrationAngle, delay: TimeInterval, next: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self, let motion = self.currentDeviceMotion else {
                    FlexaLog.motion.error("❌ [AutoCal] DeviceMotion unavailable during calibration")
                    completion?(false)
                    self?.reformedCalibrationInProgress = false
                    return
                }
                calMgr.captureCalibrationPosition(angle, deviceMotion: motion, gameType: gameType)
                next()
            }
        }
        // Ensure ARKit transform is available
        if !isARKitRunning { 
            let convertedGameType = Universal3DROMEngine.convertGameType(currentGameType)
            universal3DEngine.startDataCollection(gameType: convertedGameType)
            isARKitRunning = true 
        }
        // Sequence: 0°, 90°, 180°
        snap(.zero, delay: 1.5) {
            FlexaLog.motion.info("🎯 [AutoCal] Move to 90°. Capturing in 1.5s…")
            snap(.ninety, delay: 1.5) {
                FlexaLog.motion.info("🎯 [AutoCal] Move to 180°. Capturing in 1.5s…")
                snap(.oneEighty, delay: 1.5) {
                    FlexaLog.motion.info("🎯 [AutoCal] Submitted all captures — waiting for save…")
                    // Allow slight time for validation/save and AR delegate to pick up
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.reformedCalibrationInProgress = false
                        completion?(CalibrationDataManager.shared.currentCalibration?.isCalibrationValid == true)
                    }
                }
            }
        }
    }

    

    

    
    func stop() {
        stopSession()
    }
    

}
