import Foundation
import ARKit
import simd
import UIKit
import Combine

/// Universal 3D ROM Engine - Clean Background Data Collection
/// Architecture:
/// 1. GAMES: Only collect raw 3D position data (no calculations)
/// 2. ANALYZING SCREEN: Do all ROM calculations in background
/// 3. 3D Phone Tracking: Track phone as 3D object in space
/// 4. Movement Pattern Detection: Line, arc, circle
/// 5. 2D Projection: Transform to 2D plane for angle calculation
/// 6. Per-rep ROM: Calculate ROM for each individual rep
final class Universal3DROMEngine: NSObject, ObservableObject, ARSessionDelegate {
    
    // MARK: - Game Types
    
    enum GameType {
        case constellation    // Circular motion - one circle = one rep
        case fanOutFlame     // Side-to-side swings - one full swing = one rep
        case fruitSlicer     // Forward/backward swings - one full swing = one rep
        case hammerTime      // Up/down motion - one full motion = one rep
        case witchBrew       // Circular stirring - one circle = one rep
        case followCircle    // Follow circle pattern
        case testROM         // Test ROM exercise
        case makeYourOwn     // Make your own exercise
    }
    
    // MARK: - Core Properties
    
    /// ARKit session for 3D tracking
    private let arSession = ARSession()
    
    /// Current phone transform from ARKit
    @Published var currentTransform: simd_float4x4?
    
    /// ARKit tracking state
    @Published var isTracking = false
    
    /// Current game type
    private var currentGameType: GameType = .fruitSlicer
    
    /// Raw 3D position data collected during games (background collection only)
    private var rawPositions: [SIMD3<Double>] = []
    
    /// Timestamps for each position
    private var timestamps: [TimeInterval] = []
    
    /// Session active state
    private var isActive = false
    
    /// Error handler
    private var errorHandler: ROMErrorHandler?
    
    /// SPARC service for smoothness calculation
    private var sparcService: SPARCCalculationService?
    
    /// User's calibrated arm length (meters)
    private var armLength: Double {
        return CalibrationDataManager.shared.currentCalibration?.armLength ?? 0.6
    }
    
    /// Whether we have valid calibration data
    var isCalibrated: Bool {
        return CalibrationDataManager.shared.currentCalibration != nil
    }
    
    /// Live rep count for UI feedback during games (no ROM calculations)
    @Published private(set) var liveRepCount: Int = 0
    
    /// Data collection queue for thread safety
    private let dataCollectionQueue = DispatchQueue(label: "com.flexa.universal3d.data", qos: .userInitiated)
    
    /// Session start time
    private var sessionStartTime: TimeInterval = 0
    
    /// Live rep detection callback - fired when a new rep is detected in real-time
    /// Parameters: (repIndex: Int, repROM: Double)
    var onLiveRepDetected: ((Int, Double) -> Void)?
    
    /// Live rep tracking state for on-the-fly segmentation
    private var liveRepPositions: [SIMD3<Double>] = []
    private var liveRepStartTime: TimeInterval = 0
    private var lastLiveRepEndTime: TimeInterval = 0
    private var liveRepIndex: Int = 0
    
    /// Consecutive ARKit failures
    private var consecutiveFailures = 0
    private let maxConsecutiveFailures = 3
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupARKitDelegate()
    }

    // MARK: - Debugging Helpers
    /// Toggle for enabling verbose segmentation debug logs (useful for on-device tuning)
    var enableSegmentationDebug: Bool = false

    /// Simple debug record for each detected segment
    struct SegmentDebug: Codable {
        let startIndex: Int
        let endIndex: Int
        let startTime: TimeInterval
        let endTime: TimeInterval
        let distance: Double
        let rom: Double
    }

    /// Ring buffer for latest segment debug entries
    private var lastSegmentDebugs: [SegmentDebug] = []
    private let maxSegmentDebugEntries = 64

    /// Public accessor for recent segment debug information
    func getRecentSegmentDebugs() -> [SegmentDebug] {
        return lastSegmentDebugs
    }
    
    private func setupARKitDelegate() {
        arSession.delegate = self
    }
    
    deinit {
        if isActive {
            stop()
        }
        arSession.delegate = nil
        arSession.pause()
        currentTransform = nil
        print("🧹 [Universal3DROMEngine] Cleaned up")
    }
    
    // MARK: - Public Methods
    
    /// Set error handler for recovery support
    func setErrorHandler(_ handler: ROMErrorHandler) {
        self.errorHandler = handler
    }
    
    /// Set the SPARC service for smoothness calculation
    func setSparcService(_ service: SPARCCalculationService) {
        self.sparcService = service
    }
    
    /// Convert SimpleMotionService.GameType to Universal3DROMEngine.GameType
    static func convertGameType(_ simpleGameType: SimpleMotionService.GameType) -> GameType {
        switch simpleGameType {
        case .constellation:
            return .constellation
        case .fanOutFlame:
            return .fanOutFlame
        case .fruitSlicer:
            return .fruitSlicer
        case .followCircle:
            return .followCircle
        case .testROM:
            return .testROM
        case .makeYourOwn:
            return .makeYourOwn
        default:
            return .fruitSlicer // Default fallback
        }
    }
    
    /// Start background data collection for a specific game type
    func startDataCollection(gameType: GameType) {
        currentGameType = gameType
        isActive = true
        sessionStartTime = Date().timeIntervalSince1970
        
        // Clear previous data
        rawPositions.removeAll()
        timestamps.removeAll()
        liveRepCount = 0
        
        // Reset live rep tracking
        liveRepPositions.removeAll()
        liveRepStartTime = sessionStartTime
        lastLiveRepEndTime = sessionStartTime
        liveRepIndex = 0
        
        // Start ARKit tracking
        startARKitTracking()
        
        print("📱 [Universal3D] Started background data collection for \(gameType)")
    }
    
    /// Stop data collection
    func stop() {
        isActive = false
        
        // Properly pause and clean up ARSession
        arSession.pause()
        
        // Clear delegate to prevent callbacks after stop
        arSession.delegate = nil
        
        // Clear current transform
        currentTransform = nil
        
        // Reset tracking state
        isTracking = false
        
        print("🛑 [Universal3D] Stopped data collection")
    }
    
    /// Get collected raw data for analysis (called by analyzing screen)
    func getCollectedData() -> (positions: [SIMD3<Double>], timestamps: [TimeInterval]) {
        return dataCollectionQueue.sync {
            return (rawPositions, timestamps)
        }
    }
    
    /// Clear collected data (called after analysis)
    func clearCollectedData() {
        dataCollectionQueue.async(flags: .barrier) { [weak self] in
            self?.rawPositions.removeAll()
            self?.timestamps.removeAll()
        }
    }
    
    // MARK: - ARKit Setup
    
    private func startARKitTracking() {
        guard ARWorldTrackingConfiguration.isSupported else {
            errorHandler?.handleError(.arkitNotSupported)
            FlexaLog.motion.error("ARKit not supported on this device")
            return
        }
        
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity
        config.isAutoFocusEnabled = true
        config.isLightEstimationEnabled = false
        
        // Optimize for position tracking only
        config.planeDetection = []
        config.environmentTexturing = .none
        if #available(iOS 13.0, *) {
            config.frameSemantics = []
        }
        
        arSession.delegate = self
        arSession.run(config, options: [.resetTracking, .removeExistingAnchors])
        
        consecutiveFailures = 0
        FlexaLog.motion.info("ARKit tracking started for background data collection")
    }
    
    // MARK: - ARSessionDelegate
    
    /// Receive ARKit frame updates - only collect position data
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let cameraTransform = frame.camera.transform
        
        // Update transform for UI (main thread)
        DispatchQueue.main.async { [weak self] in
            self?.currentTransform = cameraTransform
        }
        
        // Collect position data in background (no calculations)
        dataCollectionQueue.async { [weak self] in
            guard let self = self, self.isActive else { return }
            
            let currentPosition = SIMD3<Double>(
                Double(cameraTransform.columns.3.x),
                Double(cameraTransform.columns.3.y),
                Double(cameraTransform.columns.3.z)
            )
            
            self.rawPositions.append(currentPosition)
            let currentTime = Date().timeIntervalSince1970
            self.timestamps.append(currentTime)
            
            // Feed position data to SPARC service for smoothness calculation
            if let sparcService = self.sparcService {
                let position = SIMD3<Float>(Float(currentPosition.x), Float(currentPosition.y), Float(currentPosition.z))
                sparcService.addARKitPositionData(timestamp: currentTime, position: position)
            }
            
            // Live rep detection - segment positions on-the-fly
            self.detectLiveRep(position: currentPosition, timestamp: currentTime)
            
            // Prevent memory issues by limiting data size
            if self.rawPositions.count > 5000 {
                // Remove oldest 1000 points
                self.rawPositions.removeFirst(1000)
                self.timestamps.removeFirst(1000)
            }
        }
    }
    
    /// Detect live reps on-the-fly during data collection
    private func detectLiveRep(position: SIMD3<Double>, timestamp: TimeInterval) {
        // Add position to current rep segment
        liveRepPositions.append(position)
        
        // Require minimum points and time between reps
        let minRepLength = 20 // minimum samples per rep (increased for stricter detection)
        let minTimeBetweenReps: TimeInterval = 0.5 // seconds (increased to prevent false positives)
        let minDistance = max(0.25, armLength * 0.25) // ~25cm or scaled to arm length (MUCH stricter for circular motions)
        
        guard liveRepPositions.count >= minRepLength else { return }
        
        // Check if movement exceeds threshold for rep detection
        let startPos = liveRepPositions.first!
        let currentPos = liveRepPositions.last!
        let distance = simd_length(currentPos - startPos)
        
        // Check time constraint
        guard timestamp - lastLiveRepEndTime >= minTimeBetweenReps else { return }
        
        // If distance exceeds threshold, we detected a rep
        if distance >= minDistance {
            // Calculate ROM for this rep
            let pattern = detectMovementPattern(liveRepPositions)
            let repROM = calculateROMForSegment(liveRepPositions, pattern: pattern)
            
            // Increment rep index and fire callback
            self.liveRepIndex += 1
            self.liveRepCount = self.liveRepIndex
            
            FlexaLog.motion.debug("🎯 [Universal3D Live] Rep #\(self.liveRepIndex) detected — distance=\(String(format: "%.3f", distance))m ROM=\(String(format: "%.1f", repROM))°")
            
            // Fire callback on main thread
            if let callback = self.onLiveRepDetected {
                let capturedRepIndex = self.liveRepIndex
                DispatchQueue.main.async {
                    callback(capturedRepIndex, repROM)
                }
            }
            
            // Reset for next rep
            self.liveRepPositions.removeAll()
            self.lastLiveRepEndTime = timestamp
            self.liveRepStartTime = timestamp
        } else if liveRepPositions.count > (minRepLength * 4) {
            // Prevent unbounded growth - slide window forward
            liveRepPositions.removeFirst(minRepLength)
        }
    }
    
    /// Handle ARKit session failures
    func session(_ session: ARSession, didFailWithError error: Error) {
        consecutiveFailures += 1
        FlexaLog.motion.error("ARKit session failed: \(error.localizedDescription)")
        
        if consecutiveFailures >= maxConsecutiveFailures {
            errorHandler?.handleError(.criticalSystemError(error))
        } else {
            errorHandler?.handleError(.arkitSessionFailed(error))
        }
    }
    
    /// Handle ARKit tracking state changes
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        switch camera.trackingState {
        case .normal:
            isTracking = true
            consecutiveFailures = 0
            FlexaLog.motion.info("ARKit Tracking: NORMAL - Full 6DOF tracking")
        case .notAvailable:
            isTracking = false
            consecutiveFailures += 1
            FlexaLog.motion.error("ARKit Tracking: NOT AVAILABLE - Camera access denied or hardware issue")
            
            if consecutiveFailures >= maxConsecutiveFailures {
                errorHandler?.handleError(.criticalSystemError(NSError(domain: "ARKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "Tracking not available"])))
            }
        case .limited(let reason):
            isTracking = false
            let reasonText: String
            let errorType: ROMErrorHandler.ROMError
            
            switch reason {
            case .excessiveMotion:
                reasonText = "EXCESSIVE MOTION - Move device slower"
                errorType = .arkitTrackingLost(reason)
            case .insufficientFeatures:
                reasonText = "INSUFFICIENT FEATURES - Point at textured surfaces"
                errorType = .arkitTrackingLost(reason)
            case .initializing:
                reasonText = "INITIALIZING - Keep moving device slowly"
                FlexaLog.motion.info("ARKit Tracking: LIMITED - \(reasonText)")
                return
            case .relocalizing:
                reasonText = "RELOCALIZING - Return to previous area"
                errorType = .arkitTrackingLost(reason)
            @unknown default:
                reasonText = "UNKNOWN TRACKING ISSUE"
                errorType = .arkitTrackingLost(reason)
            }
            
            FlexaLog.motion.warning("ARKit Tracking: LIMITED - \(reasonText)")
            errorHandler?.handleError(errorType)
        }
    }
}

// MARK: - ROM Analysis Engine (Called by Analyzing Screen)

extension Universal3DROMEngine {
    
    /// Analyze collected data and calculate ROM (called by analyzing screen)
    func analyzeMovementPattern() -> MovementAnalysisResult {
        let data = getCollectedData()
        let positions = data.positions
        let timestamps = data.timestamps
        
        guard positions.count >= 10 else {
            return MovementAnalysisResult(
                pattern: .unknown,
                romPerRep: [],
                repTimestamps: [],
                totalReps: 0,
                avgROM: 0.0,
                maxROM: 0.0
            )
        }
        
        // Detect movement pattern
        let pattern = detectMovementPattern(positions)
        
        // Calculate ROM for each rep and collect timestamps per rep
        let (romPerRep, repTimestamps) = calculateROMPerRepWithTimestamps(positions: positions, timestamps: timestamps, pattern: pattern)

        let totalReps = romPerRep.count
        let avgROM = romPerRep.isEmpty ? 0.0 : romPerRep.reduce(0, +) / Double(romPerRep.count)
        let maxROM = romPerRep.max() ?? 0.0

        return MovementAnalysisResult(
            pattern: pattern,
            romPerRep: romPerRep,
            repTimestamps: repTimestamps,
            totalReps: totalReps,
            avgROM: avgROM,
            maxROM: maxROM
        )
    }
    
    /// Detect movement pattern (line, arc, circle)
    private func detectMovementPattern(_ positions: [SIMD3<Double>]) -> MovementPattern {
        guard positions.count >= 3 else { return .unknown }
        
        // Calculate linearity score (how well points fit a line)
        let linearityScore = calculateLinearityScore(positions)
        
        // Calculate circularity score (how well points fit a circle)
        let circularityScore = calculateCircularityScore(positions)
        
        // Thresholds for pattern detection
        if linearityScore > 0.9 {
            return .line
        } else if circularityScore > 0.8 {
            return .circle
        } else if linearityScore > 0.6 || circularityScore > 0.5 {
            return .arc
        } else {
            return .unknown
        }
    }
    
    /// Calculate how linear the path is (0-1, 1 = perfect line)
    private func calculateLinearityScore(_ positions: [SIMD3<Double>]) -> Double {
        guard positions.count >= 3 else { return 1.0 }
        
        let start = positions.first!
        let end = positions.last!
        let lineVector = end - start
        let lineLength = simd_length(lineVector)
        
        guard lineLength > 0.01 else { return 0.0 }
        
        let lineDirection = lineVector / lineLength
        var totalDeviation = 0.0
        
        for pos in positions {
            let toPoint = pos - start
            let projection = simd_dot(toPoint, lineDirection)
            let pointOnLine = start + lineDirection * projection
            let deviation = simd_length(pos - pointOnLine)
            totalDeviation += deviation
        }
        
        let avgDeviation = totalDeviation / Double(positions.count)
        return max(0.0, 1.0 - (avgDeviation / lineLength))
    }
    
    /// Calculate how circular the path is (0-1, 1 = perfect circle)
    private func calculateCircularityScore(_ positions: [SIMD3<Double>]) -> Double {
        guard positions.count >= 4 else { return 0.0 }
        
        // Find center by averaging all points
        var center = SIMD3<Double>(0, 0, 0)
        for pos in positions {
            center += pos
        }
        center /= Double(positions.count)
        
        // Calculate average radius
        var totalRadius = 0.0
        for pos in positions {
            totalRadius += simd_length(pos - center)
        }
        let avgRadius = totalRadius / Double(positions.count)
        
        guard avgRadius > 0.01 else { return 0.0 }
        
        // Calculate deviation from perfect circle
        var totalDeviation = 0.0
        for pos in positions {
            let radius = simd_length(pos - center)
            let deviation = abs(radius - avgRadius)
            totalDeviation += deviation
        }
        
        let avgDeviation = totalDeviation / Double(positions.count)
        return max(0.0, 1.0 - (avgDeviation / avgRadius))
    }
    
    /// Calculate ROM for each rep based on detected pattern
    private func calculateROMPerRep(positions: [SIMD3<Double>], timestamps: [TimeInterval], pattern: MovementPattern) -> [Double] {
        // Deprecated wrapper - prefer calculateROMPerRepWithTimestamps
        return calculateROMPerRepWithTimestamps(positions: positions, timestamps: timestamps, pattern: pattern).0
    }

    /// Calculate ROM per rep and also return a timestamp for each rep (median time)
    private func calculateROMPerRepWithTimestamps(positions: [SIMD3<Double>], timestamps: [TimeInterval], pattern: MovementPattern) -> ([Double], [TimeInterval]) {
        // Split positions into reps based on movement pattern
        let repSegments = segmentIntoRepsWithTimestamps(positions: positions, timestamps: timestamps, pattern: pattern)

        var romPerRep: [Double] = []
        var repTimestamps: [TimeInterval] = []

        for segment in repSegments {
            let rom = calculateROMForSegment(segment.positions, pattern: pattern)
            romPerRep.append(rom)

            // pick median timestamp for the segment as rep timestamp
            if !segment.timestamps.isEmpty {
                let sortedTs = segment.timestamps.sorted()
                let mid = sortedTs[sortedTs.count / 2]
                repTimestamps.append(mid)
            } else {
                repTimestamps.append(Date().timeIntervalSince1970)
            }
        }

    return (romPerRep, repTimestamps)
    }

    /// Segment into reps with timestamps preserved
    private func segmentIntoRepsWithTimestamps(positions: [SIMD3<Double>], timestamps: [TimeInterval], pattern: MovementPattern) -> [(positions: [SIMD3<Double>], timestamps: [TimeInterval])] {
        // Reuse existing segmentation logic but return timestamps in parallel
        guard positions.count >= 10 else { return [] }

        let processedPositions = positions
        var segments: [(positions: [SIMD3<Double>], timestamps: [TimeInterval])] = []
        var currentPosSeg: [SIMD3<Double>] = []
        var currentTsSeg: [TimeInterval] = []
        var lastRepEndTime: TimeInterval = 0
        let minRepLength = 15
        let minTimeBetweenReps: TimeInterval = 0.35
        let minDistance = max(0.12, armLength * 0.12)

        for i in 0..<processedPositions.count {
            currentPosSeg.append(processedPositions[i])
            let ts = (i < timestamps.count) ? timestamps[i] : Date().timeIntervalSince1970
            currentTsSeg.append(ts)

            if currentPosSeg.count >= minRepLength {
                let startPos = currentPosSeg.first!
                let currentPos = currentPosSeg.last!
                let distance = simd_length(currentPos - startPos)
                let currentTime = ts

                if distance >= minDistance && (currentTime - lastRepEndTime) >= minTimeBetweenReps {
                    // compute ROM for the segment for debug purposes
                    let segRom = calculateROMForSegment(currentPosSeg, pattern: pattern)
                    segments.append((positions: currentPosSeg, timestamps: currentTsSeg))

                    // Add debug entry
                    let debug = SegmentDebug(
                        startIndex: max(0, i - currentPosSeg.count + 1),
                        endIndex: i,
                        startTime: currentTsSeg.first ?? 0,
                        endTime: currentTsSeg.last ?? currentTime,
                        distance: distance,
                        rom: segRom
                    )
                    lastSegmentDebugs.append(debug)
                    if lastSegmentDebugs.count > maxSegmentDebugEntries {
                        lastSegmentDebugs.removeFirst(lastSegmentDebugs.count - maxSegmentDebugEntries)
                    }
                    if enableSegmentationDebug {
                        print("🔍 [Universal3D] Segment detected: startIdx=\(debug.startIndex) endIdx=\(debug.endIndex) distance=\(String(format: "%.3f", debug.distance))m rom=\(String(format: "%.1f", debug.rom))° start=\(debug.startTime) end=\(debug.endTime)")
                    }
                    currentPosSeg = []
                    currentTsSeg = []
                    lastRepEndTime = currentTime
                } else if currentPosSeg.count > (minRepLength * 4) {
                    currentPosSeg.removeFirst(minRepLength)
                    currentTsSeg.removeFirst(minRepLength)
                }
            }
        }

        if currentPosSeg.count >= minRepLength {
            let startPos = currentPosSeg.first!
            let endPos = currentPosSeg.last!
            let distance = simd_length(endPos - startPos)
            if distance >= minDistance {
                let segRom = calculateROMForSegment(currentPosSeg, pattern: pattern)
                segments.append((positions: currentPosSeg, timestamps: currentTsSeg))

                let debug = SegmentDebug(
                    startIndex: max(0, processedPositions.count - currentPosSeg.count),
                    endIndex: processedPositions.count - 1,
                    startTime: currentTsSeg.first ?? 0,
                    endTime: currentTsSeg.last ?? Date().timeIntervalSince1970,
                    distance: distance,
                    rom: segRom
                )
                lastSegmentDebugs.append(debug)
                if lastSegmentDebugs.count > maxSegmentDebugEntries {
                    lastSegmentDebugs.removeFirst(lastSegmentDebugs.count - maxSegmentDebugEntries)
                }
                if enableSegmentationDebug {
                    print("🔍 [Universal3D] Final segment detected: startIdx=\(debug.startIndex) endIdx=\(debug.endIndex) distance=\(String(format: "%.3f", debug.distance))m rom=\(String(format: "%.1f", debug.rom))° start=\(debug.startTime) end=\(debug.endTime)")
                }
            }
        }

        return segments
    }

    /// Segment movement into individual reps
    private func segmentIntoReps(positions: [SIMD3<Double>], timestamps: [TimeInterval], pattern: MovementPattern) -> [[SIMD3<Double>]] {
        // Simple rep detection based on movement direction changes
        // This is a basic implementation - can be improved with more sophisticated algorithms
        
        guard positions.count >= 10 else { return [] }
        // Improved segmentation:
        // - Smooth positions with a short moving-average to reduce jitter
        // - Require a minimum number of points and minimum spatial displacement scaled by arm length
        // - Require a minimum time between rep segment endpoints to avoid over-segmentation

        var repSegments: [[SIMD3<Double>]] = []

        let processedPositions = positions
        var currentRep: [SIMD3<Double>] = []
        var lastRepEndTime: TimeInterval = 0
        let minRepLength = 15 // require more samples per rep to avoid tiny noise segments
        let minTimeBetweenReps: TimeInterval = 0.35 // seconds
        let minDistance = max(0.12, armLength * 0.12) // at least ~12cm or scaled to arm length

        for i in 0..<processedPositions.count {
            currentRep.append(processedPositions[i])

            if currentRep.count >= minRepLength {
                let startPos = currentRep.first!
                let currentPos = currentRep.last!
                let distance = simd_length(currentPos - startPos)
                let currentTime = (i < timestamps.count) ? timestamps[i] : Date().timeIntervalSince1970

                if distance >= minDistance && (currentTime - lastRepEndTime) >= minTimeBetweenReps {
                    repSegments.append(currentRep)
                    currentRep = []
                    lastRepEndTime = currentTime
                } else if currentRep.count > (minRepLength * 4) {
                    // Prevent runaway long segments: flush if too long without satisfying distance
                    currentRep.removeFirst(minRepLength)
                }
            }
        }

        // Add last segment only if it meets the minimum distance/time criteria
        if currentRep.count >= minRepLength {
            let startPos = currentRep.first!
            let endPos = currentRep.last!
            let distance = simd_length(endPos - startPos)
            if distance >= minDistance {
                repSegments.append(currentRep)
            }
        }

        return repSegments
    }
    
    /// Calculate ROM for a single movement segment
    private func calculateROMForSegment(_ segment: [SIMD3<Double>], pattern: MovementPattern) -> Double {
        guard segment.count >= 2 else { return 0.0 }
        
        // Find the best 2D projection plane
        let bestPlane = findOptimalProjectionPlane(segment)
        
        // Project to 2D plane
        let projectedSegment = segment.map { projectPointTo2DPlane($0, plane: bestPlane) }
        
        // Calculate ROM from projected movement
        return calculateROMFromProjectedMovement(projectedSegment, armLength: armLength)
    }
    
    /// Find the optimal 2D projection plane using PCA
    private func findOptimalProjectionPlane(_ points: [SIMD3<Double>]) -> MovementPlane {
        guard points.count >= 3 else { return .xy }
        
        // Calculate centroid
        var centroid = SIMD3<Double>(0, 0, 0)
        for point in points {
            centroid += point
        }
        centroid /= Double(points.count)
        
        // Build covariance matrix
        var covXX = 0.0, covYY = 0.0, covZZ = 0.0
        
        for point in points {
            let diff = point - centroid
            covXX += diff.x * diff.x
            covYY += diff.y * diff.y
            covZZ += diff.z * diff.z
        }
        
        let n = Double(points.count)
        covXX /= n; covYY /= n; covZZ /= n
        
        // Choose plane based on which axis has least variance
        if covZZ <= covXX && covZZ <= covYY {
            return .xy // Movement mainly in XY plane
        } else if covYY <= covXX && covYY <= covZZ {
            return .xz // Movement mainly in XZ plane
        } else {
            return .yz // Movement mainly in YZ plane
        }
    }
    
    /// Project a 3D point to the selected 2D plane
    private func projectPointTo2DPlane(_ point: SIMD3<Double>, plane: MovementPlane) -> SIMD2<Double> {
        switch plane {
        case .xy:
            return SIMD2<Double>(point.x, point.y)
        case .xz:
            return SIMD2<Double>(point.x, point.z)
        case .yz:
            return SIMD2<Double>(point.y, point.z)
        }
    }
    
    /// Calculate ROM from projected 2D movement
    private func calculateROMFromProjectedMovement(_ projectedPath: [SIMD2<Double>], armLength: Double) -> Double {
        guard projectedPath.count >= 2 else { return 0.0 }
        
        // Find maximum distance from starting point
        let startPoint = projectedPath.first!
        var maxDistance = 0.0
        
        for point in projectedPath {
            let distance = simd_length(point - startPoint)
            maxDistance = max(maxDistance, distance)
        }
        
        // Calculate ROM using arc length formula
        let ratio = min(1.0, maxDistance / (2.0 * armLength))
        let angleRadians = 2.0 * asin(ratio)
        let angleDegrees = angleRadians * 180.0 / Double.pi
        
        return max(0.0, min(180.0, angleDegrees))
    }
}

// MARK: - Supporting Types

enum MovementPattern {
    case line
    case arc
    case circle
    case unknown
}

enum MovementPlane {
    case xy, xz, yz
    
    var description: String {
        switch self {
        case .xy: return "Horizontal (XY)"
        case .xz: return "Forward/Back (XZ)"
        case .yz: return "Vertical (YZ)"
        }
    }
}

struct MovementAnalysisResult {
    let pattern: MovementPattern
    let romPerRep: [Double]
    let repTimestamps: [TimeInterval]
    let totalReps: Int
    let avgROM: Double
    let maxROM: Double
}
