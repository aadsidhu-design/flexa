#if canImport(ARKit)
import ARKit
#endif
#if canImport(AVFoundation)
import AVFoundation
#endif
import Combine
#if canImport(CoreMotion)
import CoreMotion
#endif
import Foundation
#if canImport(UIKit)
import UIKit
#endif


struct HandheldSPARCAnalysisResult {
    let perRep: [Double]
    let average: Double
    let timeline: [SPARCPoint]
}

struct CameraSmoothnessExportResult {
    let jsonURL: URL
    let csvURL: URL
    let sampleCount: Int
    let latestSPARC: Double
    let averageSPARC: Double
    let averageVelocity: Double
    let peakVelocity: Double
}

final class SimpleMotionService: NSObject, ObservableObject,
    AVCaptureVideoDataOutputSampleBufferDelegate
{


    /// Backwards-compatible wrapper used in Views which still call recordVisionRepCompletion
    func recordVisionRepCompletion(rom: Double) {
        recordCameraRepCompletion(rom: rom)
    }

    static let shared = SimpleMotionService()
    private static let defaultFastMovementReason = "Move more smoothly for better tracking"

    // MARK: - Published Session State
    @Published var isSessionActive: Bool = false
    @Published var currentROM: Double = 0
    @Published var maxROM: Double = 0
    @Published var currentReps: Int = 0
    @Published var romTrackingMode: String = "Idle"
    @Published private(set) var providerHUD: String = "Idle"
    @Published private(set) var isARKitRunning: Bool = false
    @Published private(set) var poseKeypoints: SimplifiedPoseKeypoints?
    @Published private(set) var currentPoseKeypoints: SimplifiedPoseKeypoints?
    @Published private(set) var isCameraObstructed: Bool = false
    @Published private(set) var cameraObstructionReason: String?
    @Published private var preferredCameraJointRawValue: String = "armpit"
    @Published private(set) var currentDeviceMotion: CMDeviceMotion?
    @Published private(set) var currentARKitTransform: simd_float4x4?
    @Published private(set) var latestARKitDiagnostics: InstantARKitTracker.DiagnosticsSample?
    // ARKit readiness gate — only start ROM/rep processing once ARKit reports stable tracking
    private var arkitReady: Bool = false
    private var arkitReadySince: TimeInterval? = nil
    @Published private(set) var lastRepROM: Double = 0
    @Published private(set) var isMovementTooFast: Bool = false
    @Published private(set) var fastMovementReason: String = SimpleMotionService
        .defaultFastMovementReason
    @Published private(set) var detectedCameraArm: BodySide?
    @Published private(set) var activeCameraArm: BodySide = .right
    @Published private(set) var lastCameraSmoothnessExport: CameraSmoothnessExportResult?
    @Published var manualCameraArmOverride: BodySide? = nil {
        didSet {
            refreshActiveCameraArm()
        }
    }

    @nonobjc var preferredCameraJoint: CameraJointPreference {
        get { CameraJointPreference(rawValue: preferredCameraJointRawValue) ?? .armpit }
        set {
            let rawValue = newValue.rawValue
            if preferredCameraJointRawValue != rawValue {
                preferredCameraJointRawValue = rawValue
            }
        }
    }

    // MARK: - Custom Exercise Coordination

    func configureCustomExerciseSession(exercise: CustomExercise, detector: CustomRepDetector) {
        customExerciseConfig = exercise
        customExerciseRepDetector = detector

        applyCustomExerciseArmOverrideIfNeeded(for: exercise)

        detector.onRepDetected = { [weak self] reps, rom, timestamp, duration in
            self?.handleCustomRep(reps: reps, rom: rom, timestamp: timestamp, duration: duration)
        }

        FlexaLog.motion.info(
            "🎯 [CustomRep] Service configured for '\(exercise.name)' — mode=\(exercise.trackingMode.rawValue)"
        )
    }

    func startCustomExerciseHandheldSession() {
        guard let exercise = customExerciseConfig else {
            FlexaLog.motion.error(
                "🎯 [CustomRep] startCustomExerciseHandheldSession called without configuration")
            startGameSession(gameType: .fruitSlicer)
            return
        }

        let fallbackGame = fallbackHandheldGameType(for: exercise)
        FlexaLog.motion.info(
            "🎯 [CustomRep] Starting custom handheld session using fallback game type: \(fallbackGame.displayName, privacy: .public)"
        )
        startGameSession(gameType: fallbackGame)
    }

    func clearCustomExerciseSessionContext() {
        let clearBlock = {
            self.resetCustomExerciseArmOverrideIfNeeded()
            self.customExerciseRepDetector?.onRepDetected = nil
            self.customExerciseRepDetector?.stopSession()
            self.customExerciseRepDetector = nil
            self.customExerciseConfig = nil
            FlexaLog.motion.info("🧹 [CustomRep] Cleared custom exercise session context")
        }

        if Thread.isMainThread {
            clearBlock()
        } else {
            DispatchQueue.main.async(execute: clearBlock)
        }
    }

    private func handleCustomRep(reps: Int, rom: Double, timestamp: TimeInterval, duration: Double)
    {
        guard isSessionActive else {
            FlexaLog.motion.debug("🎯 [CustomRep] Ignoring rep — session inactive")
            return
        }

        let sanitizedROM = validateAndNormalizeROM(rom)
        let repTimestamp = timestamp > 0 ? timestamp : Date().timeIntervalSince1970

        if isCustomHandheldSession {
            handheldROMCalculator.completeRep(timestamp: repTimestamp)
        }

        DispatchQueue.main.async {
            self.currentReps = reps
            self.lastRepROM = sanitizedROM
            self.currentROM = sanitizedROM
            if sanitizedROM > self.maxROM {
                self.maxROM = sanitizedROM
            }

            if self.isCustomCameraSession {
                self.romPerRep.append(sanitizedROM)
                self.romPerRepTimestamps.append(repTimestamp)
                self.romHistory.append(sanitizedROM)
                self.romSamples.removeAll()
                self.repPeakROM = 0
            }
        }

        if isCustomHandheldSession {
            // 📊 SPARC calculation deferred to analyzing screen for custom exercises
            FlexaLog.motion.debug(
                "📊 [CustomRep] SPARC will be calculated post-session from trajectory data")
        } else if isCustomCameraSession {
            let sparc = sparcService.getCurrentSPARC()
            DispatchQueue.main.async {
                self.sparcHistory.append(sparc)
            }
        }

        FlexaLog.motion.info(
            "🎯 [CustomRep] Rep #\(reps) captured — ROM=\(String(format: "%.1f", sanitizedROM))° duration=\(String(format: "%.2f", duration))s"
        )
    }

    func getFullSessionData(
        overrideExerciseType: String? = nil,
        overrideTimestamp: Date? = nil,
        overrideDuration: TimeInterval? = nil,
        overrideScore: Int? = nil
    ) -> ExerciseSessionData {
        let baseData: ExerciseSessionData
        if let cached = lastSessionData, !isSessionActive {
            baseData = cached
        } else {
            baseData = createSessionDataSnapshot()
        }

        lastSessionData = baseData

        return ExerciseSessionData(
            id: baseData.id,
            exerciseType: overrideExerciseType ?? baseData.exerciseType,
            score: overrideScore ?? baseData.score,
            reps: baseData.reps,
            maxROM: baseData.maxROM,
            averageROM: baseData.averageROM,
            duration: overrideDuration ?? baseData.duration,
            timestamp: overrideTimestamp ?? baseData.timestamp,
            romHistory: baseData.romHistory,
            repTimestamps: baseData.repTimestamps,
            sparcHistory: baseData.sparcHistory,
            romData: baseData.romData,
            sparcData: baseData.sparcData,
            aiScore: baseData.aiScore,
            painPre: baseData.painPre,
            painPost: baseData.painPost,
            sparcScore: baseData.sparcScore,
            formScore: baseData.formScore,
            consistency: baseData.consistency,
            peakVelocity: baseData.peakVelocity,
            motionSmoothnessScore: baseData.motionSmoothnessScore,
            accelAvgMagnitude: baseData.accelAvgMagnitude,
            accelPeakMagnitude: baseData.accelPeakMagnitude,
            gyroAvgMagnitude: baseData.gyroAvgMagnitude,
            gyroPeakMagnitude: baseData.gyroPeakMagnitude,
            aiFeedback: baseData.aiFeedback,
            goalsAfter: baseData.goalsAfter
        )
    }

    func exportRecentARKitDiagnostics(limit: Int = 60) -> [InstantARKitTracker.DiagnosticsSample] {
        guard limit > 0 else { return [] }
        return arkitDiagnosticsHistory.suffix(limit)
    }

    // MARK: - Post-Session Analysis (for Analyzing Screen)

    private func calibratedHandheldArmLength() -> Double {
        let calibrationArmLength =
            CalibrationDataManager.shared.currentCalibration?.armLength ?? 0.58
        return max(0.35, min(Double(calibrationArmLength), 0.9))
    }

    private func exportCameraSmoothnessDiagnostics(commandPayload: [String: Any]?) {
        guard let snapshot = cameraSmoothnessAnalyzer.exportRecentTrajectory(maxSamples: 900) else {
            FlexaLog.motion.warning(
                "🛠️ [DevCommand] No camera trajectory samples available to export")
            return
        }

        let sampleCount = snapshot.timestamps.count
        guard sampleCount > 0 else {
            FlexaLog.motion.warning(
                "🛠️ [DevCommand] Camera trajectory buffer empty — skipping export")
            return
        }

        let velocities = Array(snapshot.velocities.prefix(sampleCount))
        let averageVelocity =
            velocities.isEmpty ? 0 : velocities.reduce(0, +) / Double(velocities.count)
        let peakVelocity = velocities.max() ?? 0

        let sparcPoints = sparcService.getSPARCDataPoints()
        let lastThirtySPARC = Array(sparcPoints.suffix(30))
        let now = Date()
        let baseFilename = "camera_smoothness_" + exportFilenameFormatter.string(from: now)

        do {
            let exportDirectory = try developerExportDirectory()
            let jsonURL = exportDirectory.appendingPathComponent("\(baseFilename).json")
            let csvURL = exportDirectory.appendingPathComponent("\(baseFilename).csv")

            let metadata = buildCameraSmoothnessMetadata(
                snapshot: snapshot,
                velocities: velocities,
                sparcPoints: lastThirtySPARC,
                generatedAt: now,
                jsonFilename: jsonURL.lastPathComponent,
                csvFilename: csvURL.lastPathComponent,
                commandPayload: commandPayload
            )

            let jsonData = try JSONSerialization.data(
                withJSONObject: metadata, options: [.prettyPrinted])
            try jsonData.write(to: jsonURL, options: .atomic)

            let csvData = try buildCameraSmoothnessCSV(snapshot: snapshot, velocities: velocities)
            try csvData.write(to: csvURL, options: .atomic)

            let exportResult = CameraSmoothnessExportResult(
                jsonURL: jsonURL,
                csvURL: csvURL,
                sampleCount: sampleCount,
                latestSPARC: sparcService.getCurrentSPARC(),
                averageSPARC: sparcService.getAverageSPARC(),
                averageVelocity: averageVelocity,
                peakVelocity: peakVelocity
            )

            DispatchQueue.main.async {
                self.lastCameraSmoothnessExport = exportResult
            }

            FlexaLog.motion.info(
                "🛠️ [DevCommand] Camera smoothness export saved → JSON: \(jsonURL.lastPathComponent), CSV: \(csvURL.lastPathComponent)"
            )
        } catch {
            FlexaLog.motion.error(
                "🛠️ [DevCommand] Failed to export camera smoothness diagnostics: \(error.localizedDescription)"
            )
        }
    }

    private func buildCameraSmoothnessMetadata(
        snapshot: CameraSmoothnessAnalyzer.TrajectorySnapshot,
        velocities: [Double],
        sparcPoints: [SPARCDataPoint],
        generatedAt: Date,
        jsonFilename: String,
        csvFilename: String,
        commandPayload: [String: Any]?
    ) -> [String: Any] {
        let sampleCount = snapshot.timestamps.count
        let averageVelocity =
            velocities.isEmpty ? 0 : velocities.reduce(0, +) / Double(velocities.count)
        let peakVelocity = velocities.max() ?? 0
        let windowSummaries = buildVelocityWindowSummary(
            velocities: velocities, timestamps: snapshot.timestamps)

        let sparcSummary = sparcPoints.map { point -> [String: Any] in
            [
                "timestamp": point.timestamp.timeIntervalSince1970,
                "timestampISO": exportISOFormatter.string(from: point.timestamp),
                "value": point.sparcValue,
                "confidence": point.confidence,
                "source": point.dataSource.rawValue,
            ]
        }

        var metadata: [String: Any] = [
            "generatedAt": exportISOFormatter.string(from: generatedAt),
            "gameType": currentGameType.rawValue,
            "isCameraExercise": isCameraExercise,
            "sampleCount": sampleCount,
            "latestSPARC": sparcService.getCurrentSPARC(),
            "averageSPARC": sparcService.getAverageSPARC(),
            "averageVelocity": averageVelocity,
            "peakVelocity": peakVelocity,
            "windowVelocitySummary": windowSummaries,
            "lastThirtySPARC": sparcSummary,
            "exportFiles": [
                "json": jsonFilename,
                "csv": csvFilename,
            ],
        ]

        if let payload = commandPayload {
            metadata["commandPayload"] = payload
        }

        return metadata
    }

    private func buildVelocityWindowSummary(velocities: [Double], timestamps: [TimeInterval])
        -> [[String: Any]]
    {
        guard !velocities.isEmpty else { return [] }
        let count = min(velocities.count, timestamps.count)
        guard count > 0 else { return [] }

        var summaries: [[String: Any]] = []
        let windowSize = 100
        var index = 0

        while index < count {
            let endIndex = min(index + windowSize, count)
            let slice = velocities[index..<endIndex]
            guard !slice.isEmpty else { break }
            let average = slice.reduce(0, +) / Double(slice.count)
            let startTimestamp = timestamps[index]
            let endTimestamp = timestamps[endIndex - 1]
            var entry: [String: Any] = [
                "startIndex": index,
                "endIndex": endIndex - 1,
                "averageVelocity": average,
                "startTimestamp": startTimestamp,
                "endTimestamp": endTimestamp,
            ]

            if let startISO = isoStringIfAbsolute(startTimestamp) {
                entry["startISO"] = startISO
            }
            if let endISO = isoStringIfAbsolute(endTimestamp) {
                entry["endISO"] = endISO
            }

            summaries.append(entry)
            index = endIndex
        }

        return summaries
    }

    private func buildCameraSmoothnessCSV(
        snapshot: CameraSmoothnessAnalyzer.TrajectorySnapshot,
        velocities: [Double]
    ) throws -> Data {
        var lines: [String] = ["timestamp,rawX,rawY,filteredX,filteredY,velocity,source"]
        let count = snapshot.timestamps.count
        let velocityCount = min(velocities.count, count)

        for index in 0..<count {
            let timestamp = snapshot.timestamps[index]
            let rawPoint = snapshot.rawPositions[index]
            let filteredPoint = snapshot.filteredPositions[index]
            let velocity = index < velocityCount ? velocities[index] : 0

            let timestampString = String(format: "%.6f", timestamp)
            let rawLine = [
                timestampString,
                formatCoordinate(rawPoint.x),
                formatCoordinate(rawPoint.y),
                "",
                "",
                String(format: "%.6f", velocity),
                "raw",
            ].joined(separator: ",")

            let filteredLine = [
                timestampString,
                "",
                "",
                formatCoordinate(filteredPoint.x),
                formatCoordinate(filteredPoint.y),
                String(format: "%.6f", velocity),
                "filtered",
            ].joined(separator: ",")

            lines.append(rawLine)
            lines.append(filteredLine)
        }

        guard let data = lines.joined(separator: "\n").data(using: .utf8) else {
            throw NSError(
                domain: "SimpleMotionService", code: -42,
                userInfo: [NSLocalizedDescriptionKey: "Failed to encode CSV data"])
        }
        return data
    }

    private func developerExportDirectory() throws -> URL {
        let baseDirectory =
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let exportDirectory = baseDirectory.appendingPathComponent(
            developerExportsDirectoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: exportDirectory.path) {
            try FileManager.default.createDirectory(
                at: exportDirectory, withIntermediateDirectories: true)
        }
        return exportDirectory
    }

    private func isoStringIfAbsolute(_ timestamp: TimeInterval) -> String? {
        // Empirically, MediaPipe timestamps are relative seconds (< 10^8). Only flag as absolute if clearly epoch-based.
        guard timestamp > 1_000_000_000 else { return nil }
        return exportISOFormatter.string(from: Date(timeIntervalSince1970: timestamp))
    }

    private func formatCoordinate(_ value: CGFloat) -> String {
        String(format: "%.5f", value)
    }

    /// Get ARKit position trajectory for SPARC calculation
    func getARKitPositionTrajectory() -> (positions: [SIMD3<Float>], timestamps: [TimeInterval]) {
        let positions = arkitPositionHistory.allElements
        let timestamps = arkitPositionTimestamps.allElements

        if positions.isEmpty {
            // Return cached data from last session if current is empty
            return (lastArkitPositionsCache, lastArkitTimestampCache)
        }

        return (positions, timestamps)
    }

    // MARK: - Session Tracking (Memory Optimized)
    private var sparcHistory = BoundedArray<Double>(maxSize: 1000)  // Reduced for memory optimization
    private var romPerRep = BoundedArray<Double>(maxSize: 500)  // Reduced for memory optimization
    private var romPerRepTimestamps = BoundedArray<TimeInterval>(maxSize: 500)

    // ARKit position history for new SPARC calculation (handheld games only)
    private var arkitPositionHistory = BoundedArray<SIMD3<Float>>(maxSize: 3000)  // ~50s at 60fps (reduced from 5000)
    private var arkitPositionTimestamps = BoundedArray<TimeInterval>(maxSize: 3000)
    private var lastArkitPositionsCache: [SIMD3<Float>] = []
    private var arkitDiagnosticsHistory = BoundedArray<InstantARKitTracker.DiagnosticsSample>(
        maxSize: 300)  // Reduced from 600
    private var lastArkitTimestampCache: [TimeInterval] = []

    private var offlineHandheldSparcPerRep: [Double] = []
    private var offlineHandheldSparcTimeline: [SPARCPoint] = []
    private var offlineHandheldSparcAverage: Double = 0

    // Enhanced position caching for SPARC
    private var positionCacheForSPARC: [SIMD3<Float>] = []
    private var timestampCacheForSPARC: [TimeInterval] = []
    private var lastSessionData: ExerciseSessionData?
    private var cancellables = Set<AnyCancellable>()  // For Combine observation
    private let cameraRepMinimumInterval: TimeInterval = 0.65  // Seconds between camera reps to prevent double-counting
    private let fastMovementAccelerationThreshold: Double = 1.8
    private let fastMovementCooldown: TimeInterval = 0.75
    private var lastFastMovementTimestamp: TimeInterval = 0

    // Custom exercise coordination
    private weak var customExerciseRepDetector: CustomRepDetector?
    private var customExerciseConfig: CustomExercise?
    private var customExerciseManualOverrideSnapshot: BodySide?
    private var customExerciseAutoArmOverride: BodySide?

    private var isCustomExerciseActive: Bool {
        customExerciseRepDetector != nil && customExerciseConfig != nil
    }

    private var isCustomHandheldSession: Bool {
        guard isCustomExerciseActive else { return false }
        return customExerciseConfig?.trackingMode == .handheld
    }

    private var isCustomCameraSession: Bool {
        guard isCustomExerciseActive else { return false }
        return customExerciseConfig?.trackingMode == .camera
    }

    private func applyCustomExerciseArmOverrideIfNeeded(for exercise: CustomExercise) {
        guard exercise.trackingMode == .camera else {
            resetCustomExerciseArmOverrideIfNeeded()
            return
        }

        guard let inferredSide = exercise.inferredCameraArm else {
            resetCustomExerciseArmOverrideIfNeeded()
            return
        }

        if customExerciseAutoArmOverride == nil {
            customExerciseManualOverrideSnapshot = manualCameraArmOverride
        }

        customExerciseAutoArmOverride = inferredSide

        if manualCameraArmOverride != inferredSide {
            FlexaLog.motion.info(
                "🫱 [CameraArm] Custom exercise '\(exercise.name)' inferred \(inferredSide.rawValue.capitalized) arm — applying override"
            )
        }

        overrideCameraArm(inferredSide)
    }

    private func resetCustomExerciseArmOverrideIfNeeded() {
        guard customExerciseAutoArmOverride != nil else { return }

        let restoreSide = customExerciseManualOverrideSnapshot

        customExerciseAutoArmOverride = nil
        customExerciseManualOverrideSnapshot = nil

        if manualCameraArmOverride != restoreSide {
            FlexaLog.motion.info(
                "🫱 [CameraArm] Restoring manual override → \(restoreSide?.rawValue.capitalized ?? "Auto")"
            )
        }

        overrideCameraArm(restoreSide)
    }

    /// Public accessor for rep timestamps as Date objects
    var romPerRepTimestampsDates: [Date] {
        return romPerRepTimestamps.allElements.map { Date(timeIntervalSince1970: $0) }
    }
    // Legacy callback removed - games now observe @Published properties via Combine

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

    /// Get maximum ROM from romPerRep
    var maxRomPerRep: Double? {
        let elements = romPerRep.allElements
        return elements.isEmpty ? nil : elements.max()
    }

    /// Get ARKit position history for SPARC calculation (handheld games only)
    var arkitPositions: [SIMD3<Float>] {
        let activePositions = arkitPositionHistory.allElements
        return activePositions.isEmpty ? lastArkitPositionsCache : activePositions
    }

    /// Get ARKit position timestamps
    var arkitPositionTimestampsDates: [Date] {
        let activeTimestamps = arkitPositionTimestamps.allElements
        let source = activeTimestamps.isEmpty ? lastArkitTimestampCache : activeTimestamps
        return source.map { Date(timeIntervalSince1970: $0) }
    }

    // MARK: - External ARKit Control

    /// Allow external flows (e.g., calibration, debug tools) to start the Instant ARKit tracker
    /// without bypassing the `isARKitRunning` state managed by this service.
    func activateInstantARKitTracking(source: String = "external") {
        DispatchQueue.main.async {
            guard !self.isARKitRunning else {
                FlexaLog.motion.debug(
                    "📍 [InstantARKit] Start request from \(source) ignored — tracker already running"
                )
                return
            }

            if self.isCameraExercise {
                FlexaLog.motion.warning(
                    "📍 [InstantARKit] Starting while a camera game is active — concurrent camera usage may impact performance"
                )
            }

            do {
                try self.startARKitWithErrorHandling()
                FlexaLog.motion.info("📍 [InstantARKit] Tracker started via \(source)")
            } catch {
                FlexaLog.motion.error(
                    "📍 [InstantARKit] Failed to start via \(source): \(error.localizedDescription)")
            }
        }
    }

    /// Stop the Instant ARKit tracker and update state so camera games can safely claim the camera feed.
    func deactivateInstantARKitTracking(source: String = "external") {
        DispatchQueue.main.async {
            self.arkitTracker.stop()
            if self.isARKitRunning {
                self.isARKitRunning = false
            }
            self.refreshProviderHUD(force: true)
            FlexaLog.motion.info("📍 [InstantARKit] Tracker stopped via \(source)")
        }
    }

    // MARK: - Camera Arm Management

    var isCameraArmOverridden: Bool {
        return manualCameraArmOverride != nil
    }

    func overrideCameraArm(_ side: BodySide?) {
        DispatchQueue.main.async {
            guard self.manualCameraArmOverride != side else { return }
            self.manualCameraArmOverride = side

            if let side {
                FlexaLog.motion.info(
                    "🫱 [CameraArm] Manual override applied: \(side.rawValue.capitalized)")
            } else {
                FlexaLog.motion.info(
                    "🫱 [CameraArm] Manual override cleared — reverting to detection")
            }
        }
    }

    private func refreshActiveCameraArm(with keypoints: SimplifiedPoseKeypoints? = nil) {
        let resolvedDetected: BodySide?

        if let keypoints {
            resolvedDetected = keypoints.phoneArm
        } else if let current = poseKeypoints {
            resolvedDetected = current.phoneArm
        } else {
            resolvedDetected = detectedCameraArm
        }

        if let detected = resolvedDetected, detectedCameraArm != detected {
            detectedCameraArm = detected
        }

        let fallback = resolvedDetected ?? detectedCameraArm ?? .right
        let resolvedActive = manualCameraArmOverride ?? fallback

        if activeCameraArm != resolvedActive {
            activeCameraArm = resolvedActive
            FlexaLog.motion.debug(
                "🫱 [CameraArm] Active arm updated → \(resolvedActive.rawValue.capitalized)")
        }
    }

    func updateCameraPreviewSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        if cameraPreviewSize != size {
            cameraPreviewSize = size
            cameraSmoothnessAnalyzer.updatePreviewSize(size)
            FlexaLog.motion.debug(
                "🎥 [Camera] Preview size updated → \(Int(size.width))×\(Int(size.height))")
        }
    }

    /// Add ROM value to romPerRep (for game views) - DEPRECATED
    /// Games should no longer call this directly - data is handled automatically
    func addRomPerRep(_ value: Double) {
        // No longer append - this causes duplicate data
        // Rep detection automatically handles ROM tracking
        FlexaLog.motion.warning(
            "[DEPRECATED] addRomPerRep called — game view attempted direct ROM injection")
    }

    /// Add SPARC value to sparcHistory (for game views) - DEPRECATED
    /// Games should no longer call this directly - data is handled automatically
    func addSparcHistory(_ value: Double) {
        // No longer append - this causes duplicate data
        // Rep detection automatically handles SPARC tracking
        FlexaLog.motion.warning(
            "[DEPRECATED] addSparcHistory called — game view attempted direct SPARC injection")
    }

    // MARK: - ROM Consistency and Validation

    /// Standardized ROM validation - ensures consistent units and ranges across all games
    /// All ROM values should be in degrees (0-180°) regardless of calculation method
    func validateAndNormalizeROM(_ rom: Double) -> Double {
        // Ensure ROM is within valid physiological range (0-180 degrees)
        let normalizedROM = max(0.0, min(180.0, rom))

        return normalizedROM
    }

    // Simple exponential smoother for ROM to reduce jitter (alpha between 0..1)
    private var romSmoothingAlpha: Double = 0.25
    private var smoothedROM: Double = 0

    /// Standardized ROM threshold for rep detection per game.
    /// Shoulder-driven camera games (Wall Climbers, Constellation) expect meaningful armpit
    /// elevation before counting a rep, while Balloon Pop requires near-full elbow extension.
    func getMinimumROMThreshold(for gameType: GameType) -> Double {
        switch gameType {
        case .balloonPop:
            return 25.0
        case .wallClimbers, .constellation:
            return 20.0
        default:
            return 0.0
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

    private func updateFastMovementState(with motion: CMDeviceMotion) {
        let accel = motion.userAcceleration
        let magnitude = sqrt(accel.x * accel.x + accel.y * accel.y + accel.z * accel.z)

        if magnitude > fastMovementAccelerationThreshold {
            lastFastMovementTimestamp = motion.timestamp
            let warning =
                "Slow down! Rapid swings (~\(String(format: "%.1f", magnitude))g) reduce tracking accuracy."

            DispatchQueue.main.async {
                if self.fastMovementReason != warning {
                    self.fastMovementReason = warning
                }
                if !self.isMovementTooFast {
                    self.isMovementTooFast = true
                }
            }
        } else if isMovementTooFast {
            let elapsed = motion.timestamp - lastFastMovementTimestamp
            if elapsed > fastMovementCooldown {
                DispatchQueue.main.async {
                    self.isMovementTooFast = false
                    self.fastMovementReason = SimpleMotionService.defaultFastMovementReason
                }
            }
        }
    }

    // MARK: - Provider HUD State

    private func refreshProviderHUD(force: Bool = false) {
        DispatchQueue.main.async {
            let provider: String

            if !self.isSessionActive {
                provider = "Idle"
            } else if self.isCameraExercise {
                if self.motionManager?.isDeviceMotionActive == true
                    || self.currentDeviceMotion != nil
                {
                    provider = "Camera+IMU"
                } else {
                    provider = "Camera"
                }
            } else {
                if self.isARKitRunning {
                    provider = "AR World"
                } else if self.motionManager?.isDeviceMotionActive == true
                    || self.currentDeviceMotion != nil
                {
                    provider = "IMU"
                } else {
                    provider = "Idle"
                }
            }

            if force || self.providerHUD != provider {
                self.providerHUD = provider
                FlexaLog.motion.debug(
                    "🎛️ [ProviderHUD] Active provider: \(provider, privacy: .public)")
            }
        }
    }

    // MARK: - Private Properties
    var motionManager: CMMotionManager?

    // 🎯 NEW INSTANT ARKIT SYSTEM FOR HANDHELD GAMES
    let arkitTracker = InstantARKitTracker()  // Public for calibration access
    private let handheldRepDetector = HandheldRepDetector()
    private let imuDirectionRepDetector = IMUDirectionRepDetector()  // Simple IMU-based rep detection
    private let handheldROMCalculator = HandheldROMCalculator()

    // MIGRATED: Using MediaPipe BlazePose for robust camera pose detection
    private var poseProvider = BlazePosePoseProvider()
    private let cameraROMCalculator = CameraROMCalculator()
    private var cameraPreviewSize: CGSize = UIScreen.main.bounds.size
    private lazy var cameraRepDetector = CameraRepDetector(
        minimumInterval: cameraRepMinimumInterval)
    private lazy var cameraSmoothnessAnalyzer: CameraSmoothnessAnalyzer = {
        CameraSmoothnessAnalyzer(
            sparcService: self.sparcService, previewSize: self.cameraPreviewSize)
    }()
    private var _sparcService = SPARCCalculationService()
    var sparcService: SPARCCalculationService {
        return _sparcService
    }

    // Handheld rep detection/ROM handled by InstantARKitTracker + HandheldRepDetector/HandheldROMCalculator.
    private var lastSmoothedPose: SimplifiedPoseKeypoints?
    private var poseDropoutCache: [PoseJoint: PoseCacheEntry] = [:]
    private let poseDropoutGracePeriod: TimeInterval = 0.18
    private var cameraObstructionTimer: Timer?
    private var lastPoseDetectionTimestamp: TimeInterval = 0
    private let cameraObstructionGracePeriod: TimeInterval = 1.5

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

    // MARK: - Session Data (Memory Optimized)
    var sessionStartTime: TimeInterval = 0
    private var romHistory = BoundedArray<Double>(maxSize: 1000)  // Reduced for memory optimization
    private var romSamples = BoundedArray<Double>(maxSize: 150)  // Reduced for memory optimization
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
            case .makeYourOwn: return "Custom Exercise"
            }
        }
    }

    private func defaultCameraJoint(for gameType: GameType) -> CameraJointPreference {
        switch gameType {
        case .balloonPop:
            return .elbow
        case .wallClimbers, .constellation, .camera:
            return .armpit
        default:
            return .armpit
        }
    }

    enum ROMTrackingMode {
        case arkit
        case cameraPose
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

    // Developer export configuration
    private let developerExportsDirectoryName = "FlexaSmoothnessExports"
    private lazy var exportFilenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.timeZone = TimeZone.current
        return formatter
    }()
    private lazy var exportISOFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    // Memory pressure handling
    enum MemoryPressureLevel { case normal, warning, critical }
    @Published var memoryPressureLevel: MemoryPressureLevel = .normal
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var memoryRecoveryWorkItem: DispatchWorkItem?

    // Camera pose frame throttling (skip frames when under pressure)
    private var lastCameraProcessTime: CFAbsoluteTime = 0
    private let minCameraFrameIntervalNormal: CFAbsoluteTime = 1.0 / 30.0
    private let minCameraFrameIntervalThrottled: CFAbsoluteTime = 1.0 / 10.0

    // ADD: Non-critical data collection frequency knob (seconds). Default 0.5s = twice per second.
    private var dataCollectionFrequency: TimeInterval = 0.5

    override init() {
        super.init()
        setupServices()
        setupErrorHandling()
        setupMemoryMonitoring()
        setupDeveloperCommandHandling()

        // Observe calibration completion to enable ARKit path mid-session
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AnatomicalCalibrationComplete"), object: nil, queue: .main
        ) { [weak self] _ in
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

        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.stopCamera(tearDownCompletely: true)
        }

        refreshProviderHUD(force: true)
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
        if !romPerRep.isEmpty || currentReps > 0 || lastSessionData == nil {
            lastSessionData = createSessionDataSnapshot()
        }

        motionManager = nil

        cameraObstructionTimer?.invalidate()
        cameraObstructionTimer = nil

        // Ensure camera is stopped
        stopCamera(tearDownCompletely: true)

        // Clear callbacks to prevent retain cycles
        // onRepDetected callback removed - using Combine publishers

        FlexaLog.motion.info("SimpleMotionService deinitializing and cleaning up all resources")
    }

    private func setupServices() {
        // Setup pose provider with error handling (for camera games)
        poseProvider.onPoseDetected = { [weak self] keypoints in
            self?.processPoseKeypointsInternal(keypoints)
        }

        // 🎯 Setup new instant ARKit system for handheld games
        setupHandheldTracking()

        // Connect error handlers to services
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
                FlexaLog.motion.critical(
                    "Critical ROM system failure: \(error.localizedDescription)")
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

    private func setupDeveloperCommandHandling() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeveloperCommandNotification(_:)),
            name: .developerCommandIssued,
            object: nil
        )
    }

    @objc private func handleDeveloperCommandNotification(_ notification: Notification) {
        guard let command = notification.userInfo?["command"] as? String else { return }
        let payload = notification.userInfo?["payload"] as? [String: Any]
        if handleDeveloperCommand(command: command, payload: payload) {
            FlexaLog.motion.info("🛠️ [DevCommand] Handled command '\(command)'")
        }
    }

    @discardableResult
    private func handleDeveloperCommand(command: String, payload: [String: Any]?) -> Bool {
        switch command.lowercased() {
        case "export-camera-smoothness":
            exportCameraSmoothnessDiagnostics(commandPayload: payload)
            return true
        default:
            return false
        }
    }

    private func resetPoseSmoothingState() {
        lastSmoothedPose = nil
        poseDropoutCache.removeAll()
    }

    private func startCameraObstructionMonitoring() {
        DispatchQueue.main.async {
            self.cameraObstructionTimer?.invalidate()
            self.lastPoseDetectionTimestamp = Date().timeIntervalSince1970
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.evaluateCameraObstruction()
            }
            self.cameraObstructionTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func stopCameraObstructionMonitoring(resetState: Bool = true) {
        DispatchQueue.main.async {
            self.cameraObstructionTimer?.invalidate()
            self.cameraObstructionTimer = nil
            self.lastPoseDetectionTimestamp = 0
            if resetState {
                self.setCameraObstructionState(obstructed: false, reason: nil)
            }
        }
    }

    private func evaluateCameraObstruction() {
        let now = Date().timeIntervalSince1970
        guard isSessionActive, isCameraExercise else {
            setCameraObstructionState(obstructed: false, reason: nil)
            return
        }

        let elapsed = now - lastPoseDetectionTimestamp
        if elapsed >= cameraObstructionGracePeriod {
            let hint: String
            if elapsed >= cameraObstructionGracePeriod * 2 {
                hint = "Step closer and keep your entire upper body in view"
            } else {
                hint = "Stay centered — we lost your shoulder briefly"
            }
            setCameraObstructionState(obstructed: true, reason: hint)
        } else {
            setCameraObstructionState(obstructed: false, reason: nil)
        }
    }

    private func setCameraObstructionState(obstructed: Bool, reason: String?) {
        let update = {
            if self.isCameraObstructed != obstructed || self.cameraObstructionReason != reason {
                self.isCameraObstructed = obstructed
                self.cameraObstructionReason = reason
            }
        }

        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }

    // 🎯 Setup Instant ARKit Tracking for Handheld Games
    private func setupHandheldTracking() {
        // Wire ARKit position updates to rep detector and ROM calculator
        arkitTracker.onPositionUpdate = { [weak self] position, timestamp in
            guard let self = self, !self.isCameraExercise else { return }

            // Don't process rep/ROM until ARKit is deemed ready
            guard self.arkitReady else {
                // Optionally collect minimal samples for diagnostics but skip ROM/rep processing
                return
            }

            if self.isCustomHandheldSession {
                self.customExerciseRepDetector?.processHandheldPosition(
                    position, timestamp: timestamp)
            } else {
                // Feed to default rep detector
                self.handheldRepDetector.processPosition(position, timestamp: timestamp)
            }

            // Feed to ROM calculator
            self.handheldROMCalculator.processPosition(position, timestamp: timestamp)

            // Stream ARKit position data into SPARC pipeline for trajectory analysis
            if self.isSessionActive {
                self._sparcService.addARKitPositionData(timestamp: timestamp, position: position)
            }
        }

        arkitTracker.onTransformUpdate = { [weak self] transform, timestamp in
            guard let self else { return }

            // Only update transform-related session state once ARKit is ready
            guard self.arkitReady else {
                self.currentARKitTransform = transform
                return
            }
            self.currentARKitTransform = transform

            // Record position history for SPARC calculation (handheld games only)
            if !self.isCameraExercise && self.isSessionActive {
                let position = SIMD3<Float>(
                    transform.columns.3.x,
                    transform.columns.3.y,
                    transform.columns.3.z
                )
                self.arkitPositionHistory.append(position)
                self.arkitPositionTimestamps.append(timestamp)
            }
        }

        arkitTracker.onDiagnosticsUpdate = { [weak self] sample in
            guard let self else { return }

            // Append diagnostics for later inspection
            self.arkitDiagnosticsHistory.append(sample)

            // Update published sample for UI
            DispatchQueue.main.async {
                self.latestARKitDiagnostics = sample
            }

            // Evaluate readiness: require a short period of `normal` tracking to avoid flapping
            let now = Date().timeIntervalSince1970
            switch sample.trackingStateDescription {
            case "Normal": 
                if let since = self.arkitReadySince {
                    // If we've already been in Normal for >= 0.5s, mark ready
                    if now - since >= 0.5, !self.arkitReady {
                        self.arkitReady = true
                        FlexaLog.motion.info("📍 [InstantARKit] ARKit ready — enabling handheld ROM/rep processing")
                        // Auto-capture reference position when ARKit becomes ready
                        self.arkitTracker.setReferencePosition()
                    }
                } else {
                    self.arkitReadySince = now
                }
            default:
                // Not Normal — reset readiness timer and mark not ready
                self.arkitReadySince = nil
                if self.arkitReady {
                    self.arkitReady = false
                    FlexaLog.motion.info("📍 [InstantARKit] ARKit no longer ready — pausing handheld ROM/rep processing")
                }
            }
        }

        // Handle rep detection
        handheldRepDetector.onRepDetected = { [weak self] reps, timestamp in
            guard let self = self, !self.isCustomExerciseActive else { return }

            DispatchQueue.main.async {
                self.currentReps = reps
            }

            self.handheldROMCalculator.completeRep(timestamp: timestamp)

            if self.currentGameType != .fruitSlicer && !self.isCustomCameraSession {
                HapticFeedbackService.shared.successHaptic()
            }

            // 📊 SPARC calculation deferred to analyzing screen - no live logs during gameplay
            FlexaLog.motion.debug(
                "� [HandheldRep] Rep #\(reps) completed at \(String(format: "%.2f", timestamp))s")
        }

        // HandheldROMCalculator compatibility: provides (Double, [SIMD3<Float>]) -> Void
        handheldROMCalculator.onRepROMComputed = { [weak self] romDegrees, positions in
            guard let self = self else { return }

            let repTimestamp = Date().timeIntervalSince1970

            let maxLoggedSamples = 30
            let sampleCount = positions.count
            let samplesToLog = min(sampleCount, maxLoggedSamples)
            let baseTimestamp = repTimestamp

            var positionEntries: [String] = []
            positionEntries.reserveCapacity(samplesToLog + 1)

            for idx in 0..<samplesToLog {
                let position = positions[idx]
                // HandheldROMCalculator does not provide per-sample timestamps in the compatibility API
                let timestamp = repTimestamp
                let relativeTime = timestamp - baseTimestamp
                let entry = String(
                    format: "p%d=(%.3f, %.3f, %.3f)@%.3fs",
                    idx,
                    Double(position.x),
                    Double(position.y),
                    Double(position.z),
                    relativeTime
                )
                positionEntries.append(entry)
            }

            if sampleCount > samplesToLog {
                positionEntries.append("… +\(sampleCount - samplesToLog) more samples")
            }

            let positionsLog = positionEntries.joined(separator: ", ")

            FlexaLog.motion.info(
                "📐 [HandheldROM] Live rep ROM=\(String(format: "%.1f", romDegrees))° positions=[\(positionsLog)]"
            )

            DispatchQueue.main.async {
                // Always save ROM per rep - don't check isSessionActive
                // The rep was valid when detected, so we must record it even if session ends immediately after
                self.lastRepROM = romDegrees
                self.currentROM = romDegrees
                if romDegrees > self.maxROM {
                    self.maxROM = romDegrees
                }
                self.romPerRep.append(romDegrees)
                self.romPerRepTimestamps.append(repTimestamp)
                self.romHistory.append(romDegrees)

                FlexaLog.motion.info(
                    "📊 [HandheldROM] ✅ Saved rep ROM=\(String(format: "%.1f", romDegrees))° to session (total: \(self.romPerRep.count) reps)"
                )
            }
        }

        // Live ROM updates provided via onRepROMComputed callback

        FlexaLog.motion.info("🎯 [Handheld] Instant ARKit tracking system initialized")
    }

    // MARK: - Error Recovery Implementation

    private func executeRecoveryStrategy(
        error: ROMErrorHandler.ROMError, strategy: ROMErrorHandler.RecoveryStrategy
    ) {
        FlexaLog.motion.info(
            "Executing recovery strategy: \(strategy) for error: \(error.localizedDescription)")

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
            setROMTrackingMode(.arkit)
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
        FlexaLog.motion.info(
            "Executing graceful degradation for error: \(error.localizedDescription)")

        switch error {
        case .calibrationDataMissing:
            // Continue with default calibration values
            FlexaLog.motion.info("Using default calibration values")
        case .memoryPressureHigh, .resourceExhaustion:
            // Reduce data collection frequency
            reduceDataCollectionFrequency()
        case .visionPoseNotDetected:
            // Continue with last known pose or use simplified tracking
            FlexaLog.motion.info("Using simplified camera pose tracking")
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
                    device.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: 15)  // Reduce to 15 FPS
                    device.activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: 15)
                }
                device.unlockForConfiguration()
                FlexaLog.motion.info("Reduced camera frame rate to 15 FPS due to memory pressure")
            } catch {
                FlexaLog.motion.warning(
                    "Failed to reduce camera frame rate: \(error.localizedDescription)")
            }
        }

        // Reduce data collection frequency knob (non-critical paths)
        self.dataCollectionFrequency = 0.5  // Collect data twice per second under memory pressure
        FlexaLog.motion.info(
            "Reduced non-critical data collection frequency to \(self.dataCollectionFrequency)s")
    }

    private func isCameraRunning() -> Bool {
        return captureSession?.isRunning == true
    }

    // MARK: - Memory Pressure Handling
    private func setupMemoryMonitoring() {
        // iOS memory warning
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.handleMemoryPressure(
                .critical, reason: "UIApplication.didReceiveMemoryWarningNotification")
        }
        // Dispatch memory pressure signals
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical], queue: .global(qos: .utility))
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            let event = source.data
            let level: MemoryPressureLevel = event.contains(.critical) ? .critical : .warning
            self.handleMemoryPressure(
                level, reason: "DispatchSourceMemoryPressure(\(event.rawValue))")
        }
        memoryPressureSource = source
        source.resume()
    }

    private func handleMemoryPressure(_ level: MemoryPressureLevel, reason: String) {
        DispatchQueue.main.async {
            self.memoryPressureLevel = level
        }
        FlexaLog.motion.warning(
            "⚠️ Memory pressure: \(String(describing: level)) — reason=\(reason)")
        clearNonCriticalCaches()
        adjustCameraFrameRate(for: level)

        // Pause camera processing at critical pressure; resume when back to normal
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
            self.romPerRep.removeAll()
            self.romPerRepTimestamps.removeAll()
            self.sparcHistory.removeAll()
            self.romSamples.removeAll()
            self.repPeakROM = 0
            self.lastRepROM = 0
            self.smoothedROM = 0
            self.cameraRepDetector.reset()
            self.lastArkitPositionsCache.removeAll()
            self.lastArkitTimestampCache.removeAll()

            if self.isCameraExercise {
                let joint = self.defaultCameraJoint(for: gameType)
                if self.preferredCameraJoint != joint {
                    self.preferredCameraJoint = joint
                    FlexaLog.motion.debug(
                        "🎥 [Camera] Preferred joint set to \(joint.rawValue, privacy: .public) for \(gameType.displayName)"
                    )
                }
            }

            // 🎯 Start handheld tracking if not camera game
            if !self.isCameraExercise {
                self.startHandheldSession(gameType: gameType)
            }

            // Start performance monitoring
            self.performanceMonitor.startMonitoring()

            FlexaLog.motion.info(
                "🎮 Starting game session for \(gameType.displayName, privacy: .public)")
            if gameType == .followCircle {
                FlexaLog.motion.info(
                    "🎯 [FollowCircle] Motion session activated — resetting metrics and monitors")
            }

            self.refreshProviderHUD()
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
            FlexaLog.motion.info(
                "📊 [Pain] Pre-exercise pain level set to: \(level, privacy: .public)")
        }
    }

    func setPostPainLevel(_ level: Int) {
        DispatchQueue.main.async {
            self.postPainLevel = level
            FlexaLog.motion.info(
                "📊 [Pain] Post-exercise pain level set to: \(level, privacy: .public)")
        }
    }

    private func updateIsARKitRunning(_ running: Bool) {
        if Thread.isMainThread {
            self.isARKitRunning = running
        } else {
            DispatchQueue.main.async {
                self.isARKitRunning = running
            }
        }
    }

    // ROM tracking mode control - automatically determined by game type
    private func setROMTrackingMode(_ mode: ROMTrackingMode) {
        switch mode {
        case .arkit:
            DispatchQueue.main.async {
                self.romTrackingMode = "ARKit"
                self.updateIsARKitRunning(true)
                self.refreshProviderHUD()
            }
            // Start instant ARKit tracking for handheld games
            if !isCameraExercise {
                if !self.isARKitRunning {
                    arkitTracker.start()
                    FlexaLog.motion.info(
                        "📍 [InstantARKit] Tracker started for \(self.currentGameType.displayName)")
                } else {
                    FlexaLog.motion.debug(
                        "📍 [InstantARKit] Tracker already active for \(self.currentGameType.displayName)"
                    )
                }
            }
        case .cameraPose:
            DispatchQueue.main.async {
                self.romTrackingMode = "Camera (BlazePose)"
                self.updateIsARKitRunning(false)
                self.refreshProviderHUD()
            }
            poseProvider.startPoseTracking()
        }
        FlexaLog.motion.info(
            "🎯 ROM tracking mode set to \(String(describing: mode), privacy: .public) for \(self.currentGameType.displayName, privacy: .public)"
        )
    }

    func processPoseKeypoints(_ keypoints: SimplifiedPoseKeypoints) {
        processPoseKeypointsInternal(keypoints)
    }

    /// Called by camera-driven games when a rep is completed via BlazePose detection.
    func recordCameraRepCompletion(rom: Double) {
        let timestamp = Date().timeIntervalSince1970
        let validatedROM = validateAndNormalizeROM(rom)

        DispatchQueue.main.async {
            guard self.isSessionActive else {
                FlexaLog.motion.warning("🎥 [CameraRep] Ignoring rep — session is not active")
                return
            }

            guard self.isCameraExercise else {
                FlexaLog.motion.warning(
                    "🎥 [CameraRep] Ignoring rep — current game is not camera-based")
                return
            }

            let minimumThreshold = self.getMinimumROMThreshold(for: self.currentGameType)

            switch self.cameraRepDetector.evaluateRepCandidate(
                rom: validatedROM,
                threshold: minimumThreshold,
                timestamp: timestamp
            ) {
            case .accept:
                break
            case .belowThreshold:
                FlexaLog.motion.debug(
                    "🎥 [CameraRep] Skipping rep — ROM \(String(format: "%.1f", validatedROM))° below threshold \(String(format: "%.1f", minimumThreshold))°"
                )
                return
            case .cooldown(let elapsed, let required):
                FlexaLog.motion.debug(
                    "🎥 [CameraRep] Skipping rep — cooldown not met (Δ=\(String(format: "%.2f", elapsed))s, min=\(String(format: "%.2f", required))s)"
                )
                return
            }

            self.currentReps += 1
            self.lastRepROM = validatedROM
            self.currentROM = validatedROM

            if validatedROM > self.maxROM {
                self.maxROM = validatedROM
            }

            self.romPerRep.append(validatedROM)
            self.romPerRepTimestamps.append(timestamp)

            let sparc = self.sparcService.getCurrentSPARC()
            self.sparcHistory.append(sparc)

            let romText = String(format: "%.1f", validatedROM)
            let sparcText = String(format: "%.1f", sparc)

            if self.currentGameType != .fruitSlicer {
                HapticFeedbackService.shared.successHaptic()
            }

            self.romSamples.removeAll()
            self.repPeakROM = 0

            FlexaLog.motion.info(
                "🎥 [CameraRep] Recorded camera rep #\(self.currentReps) ROM=\(romText)° SPARC=\(sparcText)"
            )
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

        manager.deviceMotionUpdateInterval = 1.0 / 60.0  // 60 Hz
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

            let wasNil = self.currentDeviceMotion == nil
            self.currentDeviceMotion = motion
            if wasNil {
                self.refreshProviderHUD()
            }
            self.updateFastMovementState(with: motion)

            // Use motion data for SPARC analysis - rep detection handled by HandheldRepDetector via InstantARKit updates
            if !self.isCameraExercise {
                // Add motion sensor data to SPARC service for smoothness analysis
                self._sparcService.addIMUData(
                    timestamp: motion.timestamp,
                    acceleration: [
                        Double(motion.userAcceleration.x), Double(motion.userAcceleration.y),
                        Double(motion.userAcceleration.z),
                    ],
                    velocity: nil
                )

                // 🎯 Feed gyroscope data to IMU direction-change rep detector (Fruit Slicer, Fan Out Flame)
                if self.useIMURepDetection {
                    self.imuDirectionRepDetector.processGyro(motion.rotationRate, timestamp: motion.timestamp)
                }

                // 🎯 New system: InstantARKitTracker position updates drive rep/ROM via callbacks
                // IMU data feeds SPARC only; handheld pipelines rely on tracker callbacks

                // Sample ROM for tracking (actual rep detection done by callbacks)
                self.appendRepSampleIfReady(self.currentROM)
            }
        }
    }

    // MARK: - Deprecated - Unified service handles game type mapping automatically

    func getCurrentSPARC() -> Double {
        return sparcService.getCurrentSPARC()
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

        if isCameraExercise {
            romPerRep.append(repROM)
            romPerRepTimestamps.append(repTimestamp.timeIntervalSince1970)
            lastRepROM = repROM

            let sparc = sparcService.getCurrentSPARC()
            sparcHistory.append(sparc)
        } else {
            // Handheld games record rep ROM via HandheldROMCalculator callbacks
            lastRepROM = repROM
            let formattedROM = String(format: "%.1f", repROM)
            FlexaLog.motion.info(
                "🎯 [HandheldROM] Using peak ROM for rep #\(self.currentReps): \(formattedROM)°")
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
        // Notify via @Published properties (no callback needed - Combine publishes automatically)
        FlexaLog.motion.debug(
            "♻️ [RepRange] #\(self.currentReps) min=\(String(format: "%.1f", repMin))° max=\(String(format: "%.1f", repMax))° range=\(String(format: "%.1f", rangeROM))° peak=\(String(format: "%.1f", repROM))°"
        )

        return repROM
    }

    func startGameSession(gameType: GameType) {
        FlexaLog.motion.info(
            "🎮 [SESSION-START] startGameSession called for: \(gameType.displayName)")
        // Reset error handler for new session (state updates published on main)
        errorHandler.resetForNewSession()
        FlexaLog.motion.info("🎮 [SESSION-START] Error handler reset complete")
        lastFastMovementTimestamp = 0
        DispatchQueue.main.async {
            self.isMovementTooFast = false
            self.fastMovementReason = SimpleMotionService.defaultFastMovementReason
        }
        // Defer readiness check to next main runloop tick to avoid race with above reset
        DispatchQueue.main.async { [weak self] in
            FlexaLog.motion.info("🎮 [SESSION-START] Main queue async block executing")
            guard let self = self else {
                FlexaLog.motion.error("🎮 [SESSION-START] ❌ self is nil, aborting")
                return
            }
            FlexaLog.motion.info(
                "🎮 [SESSION-START] Checking system health: \(String(describing: self.errorHandler.systemHealth))"
            )
            // Allow starting unless system health is FAILED; ignore transient isRecovering during reset
            guard self.errorHandler.systemHealth != .failed else {
                FlexaLog.motion.error(
                    "🎮 [SESSION-START] ❌ Cannot start session - system health failed")
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

            // 🎯 Handheld stack auto-wires rep detection/ROM (no manual flags)

            FlexaLog.motion.info(
                "🎮 [SESSION-START] Game type: \(gameType.displayName), isCameraExercise: \(self.isCameraExercise)"
            )
            // Automatically determine ROM tracking mode based on game type with error handling
            do {
                if self.isCameraExercise {
                    FlexaLog.motion.info("🎮 [SESSION-START] → Calling startCameraGameSession")
                    try self.startCameraGameSession(gameType: gameType)
                } else {
                    FlexaLog.motion.info("🎮 [SESSION-START] → Calling startHandheldGameSession")
                    try self.startHandheldGameSession(gameType: gameType)
                }

                // 🎯 Legacy rep detection services removed - Instant ARKit pipeline initialized in startSession()
                FlexaLog.motion.info(
                    "🎮 [SESSION-START] Handheld rep/ROM pipeline already initialized")

                FlexaLog.motion.info(
                    "🎮 [SESSION-START] ✅ Game session started successfully: \(gameType.displayName)"
                )
                self.refreshProviderHUD()
            } catch {
                FlexaLog.motion.error(
                    "🎮 [SESSION-START] ❌ Exception caught: \(error.localizedDescription)")
                self.errorHandler.handleError(.sessionCorrupted)
            }
        }
    }

    private func startCameraGameSession(gameType: GameType) throws {
        FlexaLog.motion.info(
            "📹 [CAMERA-GAME] Starting camera game session for \(gameType.displayName)")
        sparcService.endHandheldSession()
        resetPoseSmoothingState()
        cameraSmoothnessAnalyzer.updatePreviewSize(cameraPreviewSize)

        // Camera games ONLY use BlazePose camera pose detection
        // Ensure ARKit is not running
        if isARKitRunning {
            FlexaLog.motion.info("📹 [CAMERA-GAME] Stopping ARKit for camera-only mode")
        }
        arkitTracker.stop()
        updateIsARKitRunning(false)
        refreshProviderHUD(force: true)
        currentARKitTransform = nil

        FlexaLog.motion.info("📹 [CAMERA-GAME] Setting ROM tracking mode to Camera (BlazePose)")
        setROMTrackingMode(.cameraPose)

        // Wire camera pose callbacks to this service
        FlexaLog.motion.info("📹 [CAMERA-GAME] Wiring BlazePose pose detection callbacks")
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
                self?.errorHandler.handleError(
                    .cameraSessionFailed(
                        NSError(
                            domain: "SimpleMotionService", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Failed to start camera"])))
            }
        }

        FlexaLog.motion.info("📹 [CAMERA-GAME] Starting pose provider")
        poseProvider.start()
        startCameraObstructionMonitoring()
        setCameraObstructionState(obstructed: false, reason: nil)
        FlexaLog.motion.info(
            "Camera game '\(gameType.displayName)' using BlazePose-only ROM calculation")
        refreshProviderHUD()
    }

    private func startHandheldGameSession(gameType: GameType) throws {
        let startTime = Date().timeIntervalSince1970

        // Handheld games use instant ARKit-based ROM calculation for 3D tracking
        resetPoseSmoothingState()

        // Stop camera pipeline since not needed for handheld games
        stopCamera(tearDownCompletely: true)
        poseProvider.stop()
        stopCameraObstructionMonitoring()
        currentARKitTransform = nil

        // Ensure old ARKit is not running
        if isARKitRunning {
            arkitTracker.stop()
            updateIsARKitRunning(false)
        }

        // Setup CoreMotion with error handling (for SPARC only)
        if motionManager == nil {
            setupCoreMotion()
        }

        guard motionManager?.isDeviceMotionAvailable == true else {
            throw ROMErrorHandler.ROMError.motionDataUnavailable
        }

        // Ensure device motion updates are running for SPARC calculation
        startDeviceMotionUpdatesLoop()

        // Enable instant ARKit tracking with error handling (optimized for <0.2s)
        try startARKitWithErrorHandling()

        // 🎯 CRITICAL: Start handheld tracking session (ROM + rep detection)
        startHandheldSession(gameType: gameType)

        let calibrated = CalibrationDataManager.shared.isCalibrated
        FlexaLog.motion.info(
            "📍 [Handheld] Calibration status: \(calibrated ? "CALIBRATED" : "NOT CALIBRATED")")

        if calibrated {
            FlexaLog.motion.info("📍 [Handheld] Using existing calibration for ROM calculation")
        } else {
            FlexaLog.motion.warning("📍 [Handheld] No calibration data - using default arm length")
        }

        let elapsedMs = (Date().timeIntervalSince1970 - startTime) * 1000
        FlexaLog.motion.info(
            "📍 [Handheld] Game '\(gameType.displayName)' using instant ARKit ROM calculation — initialized in \(String(format: "%.0f", elapsedMs))ms"
        )
        refreshProviderHUD()
    }

    // 🎯 Initialize handheld tracking session
    private func startHandheldSession(gameType: GameType) {
        if isCustomHandheldSession, let exercise = customExerciseConfig {
            let profiles = customHandheldProfiles(for: exercise)
            FlexaLog.motion.info(
                "🎯 [Handheld] Custom exercise session — motionProfile=\(String(describing: profiles.motion)) sparcProfile=\(String(describing: profiles.sparc))"
            )
            handheldROMCalculator.startSession(profile: profiles.motion)
            sparcService.startHandheldSession(profile: profiles.sparc)
            wireHandheldCallbacks()
            return
        }

        // Use IMU direction-based rep detection for Fruit Slicer and Fan Out Flame
        let useIMURepDetection = (gameType == .fruitSlicer || gameType == .fanOutFlame)
        
        if useIMURepDetection {
            // Reset IMU rep detector
            imuDirectionRepDetector.reset()
            FlexaLog.motion.info("🔄 [Handheld] Using IMU direction-based rep detection for \(gameType.displayName)")
        } else {
            // Use position-based rep detector for Follow Circle
            let detectorGameType: HandheldRepDetector.GameType = .followCircle
            handheldRepDetector.startSession(gameType: detectorGameType)
            FlexaLog.motion.info("🔄 [Handheld] Using position-based rep detection for \(gameType.displayName)")
        }

        // Determine motion profiles for ROM/SPARC pipelines
        let motionProfile: HandheldROMCalculator.MotionProfile
        let sparcProfile: SPARCCalculationService.HandheldProfile
        switch gameType {
        case .fruitSlicer, .fanOutFlame:
            motionProfile = .pendulum
            sparcProfile = .pendulum
        case .followCircle:
            motionProfile = .circular
            sparcProfile = .circular
        default:
            motionProfile = .pendulum
            sparcProfile = .pendulum
        }

        handheldROMCalculator.startSession(profile: motionProfile)
        sparcService.startHandheldSession(profile: sparcProfile)

        // 🎯 Wire up ARKit callbacks to feed ROM calculator and rep detector
        wireHandheldCallbacks()

        FlexaLog.motion.info("🎯 [Handheld] Session started for \(gameType.displayName)")
    }

    // 🎯 Wire ARKit tracker callbacks to ROM calculator, rep detector, and SPARC service
    private func wireHandheldCallbacks() {
        let useIMURepDetection = (currentGameType == .fruitSlicer || currentGameType == .fanOutFlame)
        
        // Feed ARKit positions to ROM calculator
        arkitTracker.onPositionUpdate = { [weak self] position, timestamp in
            guard let self = self else { return }
            self.handheldROMCalculator.processPosition(position, timestamp: timestamp)
            
            // Only feed position-based rep detector for Follow Circle
            if !useIMURepDetection {
                self.handheldRepDetector.processPosition(position, timestamp: timestamp)
            }
            
            self.sparcService.addARKitPositionData(timestamp: timestamp, position: position)
            
            // Update published transform for game views
            DispatchQueue.main.async {
                if let transform = self.arkitTracker.currentTransform {
                    self.currentARKitTransform = transform
                }
            }
        }

        // Wire ROM calculator callbacks
        handheldROMCalculator.onROMUpdated = { [weak self] rom in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.currentROM = rom
                if rom > self.maxROM {
                    self.maxROM = rom
                }
            }
        }

        handheldROMCalculator.onRepROMRecorded = { [weak self] rom in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.lastRepROM = rom
                self.romPerRep.append(rom)
                self.romPerRepTimestamps.append(Date().timeIntervalSince1970)
                self.romHistory.append(rom)
                FlexaLog.motion.info("📐 [Handheld] Rep ROM recorded: \(String(format: "%.1f", rom))°")
            }
        }

        if useIMURepDetection {
            // Wire IMU direction-based rep detector (Fruit Slicer, Fan Out Flame)
            imuDirectionRepDetector.onRepDetected = { [weak self] reps, timestamp in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.currentReps = reps
                    FlexaLog.motion.info("🔄 [IMU-Rep] Direction change #\(reps) detected")
                    
                    // Trigger ROM calculation for this rep
                    self.handheldROMCalculator.completeRep(timestamp: timestamp)
                    
                    // Trigger SPARC calculation for this rep
                    self.sparcService.finalizeHandheldRep(at: timestamp) { sparc in
                        if let sparc = sparc {
                            DispatchQueue.main.async {
                                self.sparcHistory.append(sparc)
                                FlexaLog.motion.info("📊 [Handheld] Rep SPARC: \(String(format: "%.1f", sparc))")
                            }
                        }
                    }
                }
            }
        } else {
            // Wire position-based rep detector (Follow Circle)
            handheldRepDetector.onRepDetected = { [weak self] reps, timestamp in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.currentReps = reps
                    FlexaLog.motion.info("🎯 [Handheld] Rep #\(reps) detected")
                    
                    // Trigger ROM calculation for this rep
                    self.handheldROMCalculator.completeRep(timestamp: timestamp)
                    
                    // Trigger SPARC calculation for this rep
                    self.sparcService.finalizeHandheldRep(at: timestamp) { sparc in
                        if let sparc = sparc {
                            DispatchQueue.main.async {
                                self.sparcHistory.append(sparc)
                                FlexaLog.motion.info("📊 [Handheld] Rep SPARC: \(String(format: "%.1f", sparc))")
                            }
                        }
                    }
                }
            }
        }

        FlexaLog.motion.info("🔌 [Handheld] Callbacks wired - IMU rep detection: \(useIMURepDetection)")
    }

    private func fallbackHandheldGameType(for exercise: CustomExercise) -> GameType {
        switch exercise.repParameters.movementType {
        case .circular:
            return .followCircle
        case .pendulum:
            return .fruitSlicer
        case .horizontal:
            return .fanOutFlame
        case .vertical, .straightening:
            return .fruitSlicer
        case .mixed:
            return .fruitSlicer
        }
    }

    private func customHandheldProfiles(for exercise: CustomExercise) -> (
        motion: HandheldROMCalculator.MotionProfile, sparc: SPARCCalculationService.HandheldProfile
    ) {
        switch exercise.repParameters.movementType {
        case .circular:
            return (.circular, .circular)
        case .pendulum:
            return (.pendulum, .pendulum)
        case .horizontal:
            return (.freeform, .freeform)
        case .vertical, .straightening:
            return (.pendulum, .pendulum)
        case .mixed:
            return (.freeform, .freeform)
        }
    }

    private func startARKitWithErrorHandling() throws {
        guard ARWorldTrackingConfiguration.isSupported else {
            throw ROMErrorHandler.ROMError.arkitNotSupported
        }

        // Start instant ARKit tracker
        arkitTracker.start()
        updateIsARKitRunning(true)
        refreshProviderHUD()

        FlexaLog.motion.info("📍 [InstantARKit] Tracker started successfully")
    }

    func stopSession() {
        let endedGame = currentGameType
        if endedGame == .followCircle {
            let romCount = self.romPerRep.count
            let sparcCount = self.sparcHistory.count
            FlexaLog.motion.info(
                "🎯 [FollowCircle] Preparing to stop session — reps=\(self.currentReps, privacy: .public) maxROM=\(String(format: "%.1f", self.maxROM), privacy: .public) romEntries=\(romCount, privacy: .public) sparcEntries=\(sparcCount, privacy: .public)"
            )
        }

        handheldROMCalculator.onRepROMComputed = nil

        // Stop pose provider and clear callbacks
        poseProvider.stop()
        poseProvider.onPoseDetected = nil
        resetPoseSmoothingState()

        // Stop camera session with COMPLETE teardown (prevents battery drain)
        if isCameraExercise || captureSession != nil {
            stopCamera(tearDownCompletely: true)
            FlexaLog.motion.info(
                "📹 [Camera] Complete teardown for ended game '\(endedGame.displayName)' — capture session released"
            )
        }

        // Stop CoreMotion updates and clear motion manager
        motionManager?.stopDeviceMotionUpdates()
        lastSessionData = createSessionDataSnapshot()
        motionManager = nil

        // Preserve latest ARKit samples for post-session analysis before clearing buffers
        lastArkitPositionsCache = arkitPositionHistory.allElements
        lastArkitTimestampCache = arkitPositionTimestamps.allElements

        // 🎯 Stop new instant ARKit tracking system
        arkitTracker.stop()

        // End SPARC service session
        sparcService.endHandheldSession()
        _ = sparcService.endSession()  // ignore result

        // Stop performance monitoring and log results
        performanceMonitor.stopMonitoring()

        // Log performance summary
        if let avgMetrics = performanceMonitor.averageMetrics {
            FlexaLog.motion.info(
                "Session Performance Summary: Memory=\(String(format: "%.1f", avgMetrics.memoryUsageMB))MB, CPU=\(String(format: "%.1f", avgMetrics.cpuUsagePercent))%, FPS=\(String(format: "%.1f", avgMetrics.frameRate))"
            )
        }

        lastFastMovementTimestamp = 0
        // Clear session state and data on main thread
        DispatchQueue.main.async {
            self.isSessionActive = false
            self.isARKitRunning = false

            // Clear accumulated session data to prevent contamination between games
            self.romPerRep.removeAll()
            self.sparcHistory.removeAll()
            self.romHistory.removeAll()
            self.romSamples.removeAll()

            // Clear ARKit position history
            self.arkitPositionHistory.removeAll()
            self.arkitPositionTimestamps.removeAll()
            self.arkitDiagnosticsHistory.removeAll()
            self.latestARKitDiagnostics = nil

            self.offlineHandheldSparcPerRep.removeAll()
            self.offlineHandheldSparcTimeline.removeAll()
            self.offlineHandheldSparcAverage = 0

            // Reset counters and measurements
            self.currentReps = 0
            self.currentROM = 0
            self.maxROM = 0
            self.lastRepROM = 0
            self.repPeakROM = 0
            self.smoothedROM = 0
            self.currentDeviceMotion = nil
            self.currentARKitTransform = nil
            self.isMovementTooFast = false
            self.fastMovementReason = SimpleMotionService.defaultFastMovementReason
            self.preferredCameraJoint = .armpit

            FlexaLog.motion.info("🧹 [Motion] Session data cleared — ready for new game")
            self.refreshProviderHUD(force: true)
        }

        FlexaLog.motion.info("📍 [Handheld] All services stopped and resources cleaned up")

        clearCustomExerciseSessionContext()
    }

    // MARK: - Error Recovery Methods

    private func fallbackToARKitMode() {
        guard !isCameraExercise else {
            FlexaLog.motion.warning("Cannot fallback to ARKit mode for camera game")
            return
        }

        // Stop camera pose pipeline if running
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
        if !CalibrationDataManager.shared.isCalibrated {
            FlexaLog.motion.warning("Using default calibration values for graceful degradation")
        }
    }

    private func retryCurrentOperation() {
        // Retry the last failed operation
        if isCameraExercise {
            startCamera { [weak self] success in
                if !success {
                    self?.errorHandler.handleError(
                        .cameraSessionFailed(
                            NSError(
                                domain: "SimpleMotionService", code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "Retry failed"])))
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
            "isSessionActive": isSessionActive,
        ]

        saveSessionFile()
        return sessionData
    }

    private func createSessionDataSnapshot() -> ExerciseSessionData {
        let duration = Date().timeIntervalSince1970 - sessionStartTime

        // 🎯 SPARC CALCULATION STRATEGY:
        // - Handheld games: DEFER to analyzing screen (avoid gameplay lag)
        // - Camera games: Calculate now from wrist trajectory
        let finalSPARC: Double
        if isCameraExercise {
            // Camera games: Calculate wrist tracking smoothness now
            let (wristPositions, wristTimestamps) = sparcService.exportCameraTrajectory()
            if let cameraSPARC = sparcService.computeCameraWristSPARC(
                wristPositions: wristPositions,
                timestamps: wristTimestamps
            ) {
                finalSPARC = cameraSPARC
                FlexaLog.motion.info(
                    "📊 [Camera] Wrist smoothness: \(String(format: "%.1f", cameraSPARC)) from \(wristPositions.count) samples"
                )
            } else {
                finalSPARC = sparcService.getCurrentSPARC()
                FlexaLog.motion.warning("📊 [Camera] Falling back to real-time SPARC")
            }
        } else {
            // Handheld games: Use average from SPARC history if available
            // Otherwise defer to analyzing screen calculation
            let sparcValues = sparcHistory.allElements.filter { $0.isFinite && $0 > 0 }
            if !sparcValues.isEmpty {
                finalSPARC = sparcValues.reduce(0, +) / Double(sparcValues.count)
                FlexaLog.motion.info(
                    "📊 [Handheld] Using average SPARC: \(String(format: "%.1f", finalSPARC)) from \(sparcValues.count) samples"
                )
            } else {
                finalSPARC = 0.0
                FlexaLog.motion.info(
                    "📊 [Handheld] SPARC deferred to analyzing screen (ARKit positions: \(self.arkitPositionHistory.count) samples cached)"
                )
            }
        }

        // Clean and validate all metrics
        let sanitizedMaxROM = maxROM.isFinite ? maxROM : 0
        let perRepROM = romPerRep.allElements.filter { $0.isFinite }
        let avgROM = perRepROM.isEmpty ? 0 : perRepROM.reduce(0, +) / Double(perRepROM.count)

        // ENHANCED SPARC DATA COLLECTION
        let sparcHistoryValues: [Double]
        let sparcDataWithTimestamps: [SPARCPoint]

        if !offlineHandheldSparcPerRep.isEmpty {
            // Use offline computed SPARC data
            sparcHistoryValues = offlineHandheldSparcPerRep
            sparcDataWithTimestamps = offlineHandheldSparcTimeline
            FlexaLog.motion.info(
                "📊 [SessionData] Using offline SPARC: \(sparcHistoryValues.count) values, \(sparcDataWithTimestamps.count) timeline points"
            )
        } else {
            // Use live SPARC data with timeline creation
            sparcHistoryValues = sparcHistory.allElements.filter { $0.isFinite }
            let sparcDataPoints = sparcService.getSPARCDataPoints()
            sparcDataWithTimestamps = sparcDataPoints.map {
                SPARCPoint(sparc: $0.sparcValue, timestamp: $0.timestamp)
            }
            FlexaLog.motion.info(
                "📊 [SessionData] Using live SPARC: \(sparcHistoryValues.count) values, \(sparcDataWithTimestamps.count) timeline points"
            )
        }

        let sparcPoints: [SPARCPoint]
        if !offlineHandheldSparcTimeline.isEmpty {
            sparcPoints = offlineHandheldSparcTimeline
        } else {
            sparcPoints = sparcService.getSPARCDataPoints()
                .filter { $0.sparcValue.isFinite }
                .map { dataPoint in
                    SPARCPoint(sparc: dataPoint.sparcValue, timestamp: dataPoint.timestamp)
                }
        }

        let sanitizedSPARCScore = finalSPARC.isFinite ? finalSPARC : 0
        let calculatedAIScore = calculateAIScore()
        let resolvedConsistency = Double(calculateConsistencyScore())
        let generatedAIFeedback = generateAIFeedback()
        let resolvedAIFeedback: String? = generatedAIFeedback.isEmpty ? nil : generatedAIFeedback

        // Log comprehensive metrics for debugging
        FlexaLog.motion.info(
            "📊 [SessionData] Final metrics — reps=\(self.currentReps) maxROM=\(String(format: "%.1f", sanitizedMaxROM))° avgROM=\(String(format: "%.1f", avgROM))° SPARC=\(String(format: "%.1f", sanitizedSPARCScore)) source=\(self.isCameraExercise ? "camera-wrist" : "deferred-to-analyzing"))"
        )

        return ExerciseSessionData(
            exerciseType: currentGameType.displayName,
            score: currentReps * 10,
            reps: currentReps,
            maxROM: sanitizedMaxROM,
            averageROM: avgROM,
            duration: duration,
            timestamp: Date(),
            romHistory: perRepROM,
            repTimestamps: romPerRepTimestampsDates,
            sparcHistory: sparcHistoryValues,
            romData: [],
            sparcData: sparcPoints,
            aiScore: calculatedAIScore,
            painPre: prePainLevel,
            painPost: postPainLevel,
            sparcScore: sanitizedSPARCScore,
            formScore: resolvedConsistency,
            consistency: resolvedConsistency,
            peakVelocity: 0,
            motionSmoothnessScore: sanitizedSPARCScore,
            accelAvgMagnitude: nil,
            accelPeakMagnitude: nil,
            gyroAvgMagnitude: nil,
            gyroPeakMagnitude: nil,
            aiFeedback: resolvedAIFeedback,
            goalsAfter: LocalDataManager.shared.getCachedGoals()
        )
    }

    func computeHandheldSPARCAnalysis() -> HandheldSPARCAnalysisResult? {
        guard !isCameraExercise else { return nil }

        if !offlineHandheldSparcPerRep.isEmpty {
            FlexaLog.motion.info(
                "📊 [SPARC-Analysis] Using cached offline SPARC: \(self.offlineHandheldSparcPerRep.count) per-rep values"
            )
            return HandheldSPARCAnalysisResult(
                perRep: offlineHandheldSparcPerRep,
                average: offlineHandheldSparcAverage,
                timeline: offlineHandheldSparcTimeline
            )
        }

        // ENHANCED: Get position data from multiple sources
        var rawPositions: [SIMD3<Float>] = []
        var rawTimestamps: [TimeInterval] = []

        // Source 1: ARKit tracker positions (InstantARKitTracker is a concrete instance)
        let (positions, timestamps) = self.arkitTracker.getPositionHistory()
        if !positions.isEmpty {
            rawPositions.append(contentsOf: positions)
            rawTimestamps.append(contentsOf: timestamps)
            FlexaLog.motion.info(
                "📊 [SPARC-Analysis] Got \(positions.count) positions from ARKit tracker")
        }

        // Source 2: If no ARKit data, use cached positions
        if rawPositions.isEmpty {
            rawPositions = self.lastArkitPositionsCache
            rawTimestamps = self.lastArkitTimestampCache
            FlexaLog.motion.info("📊 [SPARC-Analysis] Using cached positions: \(rawPositions.count)")
        }

        let positionSamplesRaw = arkitPositionHistory.allElements
        let timestampSamplesRaw = arkitPositionTimestamps.allElements
        FlexaLog.motion.info(
            "📊 [SPARC-Analysis] Raw data: \(positionSamplesRaw.count) positions, \(timestampSamplesRaw.count) timestamps"
        )

        let resolvedPositions =
            positionSamplesRaw.isEmpty ? lastArkitPositionsCache : positionSamplesRaw
        let resolvedTimestamps =
            timestampSamplesRaw.isEmpty ? lastArkitTimestampCache : timestampSamplesRaw
        FlexaLog.motion.info(
            "📊 [SPARC-Analysis] Resolved data: \(resolvedPositions.count) positions, \(resolvedTimestamps.count) timestamps (from \(positionSamplesRaw.isEmpty ? "cache" : "live arrays"))"
        )

        var timelinePoints: [SPARCPoint] = []

        if !resolvedPositions.isEmpty,
            resolvedPositions.count == resolvedTimestamps.count
        {
            FlexaLog.motion.info(
                "📊 [SPARC-Analysis] Calling computeHandheldTimeline with \(resolvedPositions.count) samples..."
            )
            let (trajectoryValues, trajectoryTimestamps) = sparcService.computeHandheldTimeline(
                trajectory: resolvedPositions,
                timestamps: resolvedTimestamps
            )
            // compatibility: convert returned tuple into expected SPARC timeline points
            let additionalPoints: [SPARCPoint] = zip(trajectoryValues, trajectoryTimestamps).map { (value, timestamp) in
                SPARCPoint(sparc: value, timestamp: Date(timeIntervalSince1970: timestamp))
            }
            FlexaLog.motion.info(
                "📊 [SPARC-Analysis] Timeline computation returned \(additionalPoints.count) points"
            )

            if !additionalPoints.isEmpty {

                timelinePoints.append(contentsOf: additionalPoints)
                timelinePoints.sort { $0.timestamp < $1.timestamp }

                var deduped: [SPARCPoint] = []
                var lastTimestamp: Date?
                for point in timelinePoints {
                    if let last = lastTimestamp,
                        abs(point.timestamp.timeIntervalSince(last)) < 0.05
                    {
                        continue
                    }
                    deduped.append(point)
                    lastTimestamp = point.timestamp
                }
                timelinePoints = deduped
                FlexaLog.motion.info(
                    "📊 [SPARC-Analysis] After deduplication: \(timelinePoints.count) points")
            }
        } else {
            FlexaLog.motion.warning(
                "📊 [SPARC-Analysis] Cannot compute timeline: positions=\(resolvedPositions.count) timestamps=\(resolvedTimestamps.count) match=\(resolvedPositions.count == resolvedTimestamps.count)"
            )
        }

        let averageScore: Double
        if timelinePoints.isEmpty {
            averageScore = 0.0
            FlexaLog.motion.warning("📊 [SPARC-Analysis] No timeline points - returning 0.0 average")
        } else {
            let total = timelinePoints.reduce(0.0) { $0 + $1.sparc }
            averageScore = total / Double(timelinePoints.count)
            FlexaLog.motion.info(
                "📊 [SPARC-Analysis] Computed average: \(String(format: "%.1f", averageScore)) from \(timelinePoints.count) points"
            )
        }

        offlineHandheldSparcPerRep = []
        offlineHandheldSparcAverage = averageScore
        offlineHandheldSparcTimeline = timelinePoints

        sparcHistory.removeAll()
        timelinePoints.forEach { sparcHistory.append($0.sparc) }

        DispatchQueue.main.async { [weak self] in
            self?._sparcService.currentSPARC = averageScore
            self?._sparcService.averageSPARC = averageScore
        }

        return HandheldSPARCAnalysisResult(
            perRep: [],
            average: averageScore,
            timeline: timelinePoints
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
            "repTimestamps": data.repTimestamps.map { $0.timeIntervalSince1970 },
        ]

        if !data.sparcData.isEmpty {
            let sparcTimeline = data.sparcData.map { point in
                [
                    "timestamp": point.timestamp.timeIntervalSince1970,
                    "sparc": point.sparc,
                ]
            }
            userInfo["sparcDataPoints"] = sparcTimeline
        }

        if !data.romData.isEmpty {
            let romTimeline = data.romData.map { point in
                [
                    "timestamp": point.timestamp.timeIntervalSince1970,
                    "angle": point.angle,
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

    // InstantARKitTracker + HandheldROMCalculator now update ROM via setupHandheldTracking() callbacks
    func updateROMFromARKit(_ rom: Double) {
        // No-op - kept for compatibility with old code paths
        // New system: ROM updated directly in setupHandheldTracking() callbacks
        FlexaLog.motion.debug(
            "[DEPRECATED] updateROMFromARKit called - new system uses direct callbacks")
    }

    private func saveSessionFile() {
        let sparcTimeline: [SPARCPoint]
        if !offlineHandheldSparcTimeline.isEmpty {
            sparcTimeline = offlineHandheldSparcTimeline
        } else {
            sparcTimeline =
                sparcService
                .getSPARCDataPoints()
                .filter { $0.sparcValue.isFinite }
                .map { dataPoint in
                    SPARCPoint(sparc: dataPoint.sparcValue, timestamp: dataPoint.timestamp)
                }
        }

        let sessionFile = SessionFile(
            exerciseType: currentGameType.rawValue,
            timestamp: Date(timeIntervalSince1970: sessionStartTime),
            userId: BackendService().currentUserId,
            sessionNumber: LocalDataManager.shared.nextSessionNumber(),
            duration: Date().timeIntervalSince1970 - sessionStartTime,
            romPerRep: romPerRep.allElements,
            sparcHistory: sparcHistory.allElements,
            romHistory: romHistory.allElements,
            maxROM: maxROM,
            reps: currentReps,
            sparcDataPoints: sparcTimeline,
            painPre: prePainLevel,
            painPost: postPainLevel
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

        // 🎯 SPARC CALCULATION FOR COMPREHENSIVE DATA
        // Handheld: Deferred to analyzing screen; Camera: Calculate now
        let finalSPARC: Double
        if isCameraExercise {
            let (wristPositions, wristTimestamps) = sparcService.exportCameraTrajectory()
            if let cameraSPARC = sparcService.computeCameraWristSPARC(
                wristPositions: wristPositions,
                timestamps: wristTimestamps
            ) {
                finalSPARC = cameraSPARC
            } else {
                finalSPARC = sparcService.getCurrentSPARC()
            }
        } else {
            // Handheld: Defer to analyzing screen
            finalSPARC = 0.0
        }

        // Create performance data from current session
        // Convert TimeInterval timestamps to Date for the performance payload
        let repDates = romPerRepTimestamps.allElements.map { Date(timeIntervalSince1970: $0) }
        let sparcHistoryValues: [Double]
        if !offlineHandheldSparcPerRep.isEmpty {
            sparcHistoryValues = offlineHandheldSparcPerRep
        } else {
            sparcHistoryValues = sparcHistory.allElements.filter { $0.isFinite }
        }

        let sparcTimeline: [SPARCDataPoint]
        if !offlineHandheldSparcTimeline.isEmpty {
            var temp: [SPARCDataPoint] = []
            let fixer = SPARCDataCollectionFixes(sessionStartTime: Date())
            for point in offlineHandheldSparcTimeline {
                // SPARCDataCollectionFixes.createValidatedSPARCDataPoint expects (timestamp:value:confidence:source:)
                let validated = fixer.createValidatedSPARCDataPoint(
                    timestamp: point.timestamp,
                    value: point.sparc,
                    confidence: 0.4,
                    source: .imu
                )
                temp.append(validated)
            }
            sparcTimeline = temp
        } else {
            sparcTimeline =
                sparcService
                .getSPARCDataPoints()
                .filter { $0.sparcValue.isFinite }
        }

        let performanceData = ExercisePerformanceData(
            score: currentReps * 10,  // Base score calculation
            reps: currentReps,
            duration: duration,
            romData: romHistory.allElements,
            romPerRep: romPerRep.allElements,
            repTimestamps: repDates,
            sparcDataPoints: sparcTimeline,
            movementQualityScores: sparcHistoryValues,  // Use SPARC as quality proxy
            aiScore: calculateAIScore(),
            aiFeedback: generateAIFeedback(),
            sparcScore: finalSPARC.isFinite ? finalSPARC : 0,
            gameSpecificData: currentGameType.rawValue,
            accelAvg: nil,  // Could be enhanced with motion sensor aggregates
            accelPeak: nil,
            gyroAvg: nil,
            gyroPeak: nil
        )

        let sessionNumber = LocalDataManager.shared.nextSessionNumber()

        return ComprehensiveSessionData(
            userID: "anonymous",  // Using anonymous auth
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

        FlexaLog.motion.info(
            "💾 [Session] Saved comprehensive session data with ROM: \(self.maxROM, privacy: .public)° reps: \(self.currentReps)"
        )
    }

    private func calculateAIScore() -> Int {
        // Simple AI score calculation based on ROM and consistency
        let romScore = min(100, Int(maxROM * 1.2))  // ROM contributes to score
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
            FlexaLog.motion.info(
                "📹 [PREVIEW] Updating preview session to: \(session?.debugDescription ?? "nil") on main thread"
            )
            previewSession = session
            FlexaLog.motion.info(
                "📹 [PREVIEW] Preview session updated successfully - isRunning: \(session?.isRunning ?? false)"
            )
        } else {
            DispatchQueue.main.async { [weak self] in
                FlexaLog.motion.info(
                    "📹 [PREVIEW] Updating preview session to: \(session?.debugDescription ?? "nil") async on main thread"
                )
                self?.previewSession = session
                FlexaLog.motion.info(
                    "📹 [PREVIEW] Preview session updated successfully async - isRunning: \(session?.isRunning ?? false)"
                )
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
        FlexaLog.motion.info(
            "📹 [CAMERA] Current thread: \(Thread.current.isMainThread ? "MAIN" : "BACKGROUND")")

        cameraStartupLock.lock()
        let alreadyStarting = isStartingCamera
        let existingSession = captureSession
        cameraStartupLock.unlock()

        FlexaLog.motion.info(
            "📹 [CAMERA] Status check: isStartingCamera=\(alreadyStarting), existingSession=\(existingSession != nil ? "YES" : "NO")"
        )

        // Check if camera startup is already in progress
        if alreadyStarting {
            FlexaLog.motion.info(
                "📹 [CAMERA] Camera startup already in progress - waiting and retrying in 0.1s")
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
            FlexaLog.motion.info(
                "📹 [CAMERA] ✅ Found existing session - isRunning: \(existingSession.isRunning)")
            if existingSession.isRunning {
                FlexaLog.motion.info(
                    "📹 [CAMERA] ✅ Existing session already running - updating preview and completing"
                )
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

    private func resumeExistingSession(
        _ session: AVCaptureSession, completion: @escaping (Bool) -> Void
    ) {
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
                    NotificationCenter.default.post(
                        name: .SharedCaptureSessionReady, object: session)
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
        FlexaLog.motion.info(
            "📹 [CAMERA-STARTUP] ========== performCameraStartup ENTERED ==========")
        let startupStartTime = Date()
        FlexaLog.motion.info(
            "📹 [CAMERA-STARTUP] Phase 0: Starting camera initialization at \(startupStartTime)")

        guard captureSession == nil else {
            FlexaLog.motion.info(
                "📹 [CAMERA-STARTUP] ⚠️ captureSession already exists (race condition?) - using existing"
            )
            updatePreviewSession(captureSession)
            completion(true)
            return
        }

        FlexaLog.motion.info(
            "📹 [CAMERA-STARTUP] captureSession is nil - proceeding with fresh initialization")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async {
                    self?.isStartingCamera = false
                    completion(false)
                }
                return
            }

            do {
                FlexaLog.motion.info(
                    "📹 [CAMERA-STARTUP] Phase 1: Checking permissions... (\(String(format: "%.3f", Date().timeIntervalSince(startupStartTime)))s)"
                )

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

                FlexaLog.motion.info(
                    "📹 [CAMERA-STARTUP] Phase 2: Creating AVCaptureSession... (\(String(format: "%.3f", Date().timeIntervalSince(startupStartTime)))s)"
                )
                let session = AVCaptureSession()

                // Small delay to allow XPC communication to stabilize (prevents FigCapture errors)
                Thread.sleep(forTimeInterval: 0.05)

                // Begin configuration to prevent XPC race conditions
                FlexaLog.motion.info(
                    "📹 [CAMERA-STARTUP] Phase 3: Beginning session configuration... (\(String(format: "%.3f", Date().timeIntervalSince(startupStartTime)))s)"
                )
                session.beginConfiguration()
                session.sessionPreset = .vga640x480  // Prefer 640x480 for BlazePose camera tracking
                FlexaLog.motion.info(
                    "📹 [CAMERA-STARTUP] Phase 4: Session preset set to VGA 640x480 (\(String(format: "%.3f", Date().timeIntervalSince(startupStartTime)))s)"
                )

                // Try to get front camera first, then fallback to any available camera (for simulator support)
                var camera: AVCaptureDevice?
                camera = AVCaptureDevice.default(
                    .builtInWideAngleCamera, for: .video, position: .front)

                if camera != nil {
                    FlexaLog.motion.debug("✅ [Camera] Selected front-facing device for capture")
                } else {
                    FlexaLog.motion.warning(
                        "⚠️ [Camera] Front camera unavailable — attempting fallback selection")
                    // Fallback for simulator or devices without front camera
                    camera = AVCaptureDevice.default(for: .video)
                    if let fallbackDevice = camera {
                        FlexaLog.motion.info(
                            "✅ [Camera] Using fallback video device: \(fallbackDevice.localizedName, privacy: .public)"
                        )
                    }
                }

                guard let captureDevice = camera else {
                    FlexaLog.motion.error(
                        "❌ [Camera] No capture device available — simulator or hardware issue suspected"
                    )
                    // Use AVCaptureDeviceDiscoverySession for iOS 10+
                    let discoverySession = AVCaptureDevice.DiscoverySession(
                        deviceTypes: [.builtInWideAngleCamera], mediaType: .video,
                        position: .unspecified)
                    FlexaLog.motion.debug(
                        "📱 [Camera] Discovery session devices: \(discoverySession.devices.map { $0.localizedName }, privacy: .public)"
                    )
                    throw ROMErrorHandler.ROMError.cameraAccessDenied
                }

                // Configure camera format before creating input
                do {
                    try captureDevice.lockForConfiguration()

                    // Find a compatible format for the session preset
                    let formats = captureDevice.formats.filter { format in
                        let dimensions = CMVideoFormatDescriptionGetDimensions(
                            format.formatDescription)
                        return dimensions.width >= 640 && dimensions.height >= 480
                    }

                    if let compatibleFormat = formats.first {
                        captureDevice.activeFormat = compatibleFormat
                        FlexaLog.motion.info("Set camera format: \(compatibleFormat)")
                    }

                    // Set frame rate after format is set
                    if #available(iOS 15.0, *) {
                        captureDevice.activeVideoMinFrameDuration = CMTimeMake(
                            value: 1, timescale: 30)
                        captureDevice.activeVideoMaxFrameDuration = CMTimeMake(
                            value: 1, timescale: 30)
                    }

                    captureDevice.unlockForConfiguration()
                } catch {
                    FlexaLog.motion.warning(
                        "Failed to configure camera format: \(error.localizedDescription)")
                    // Continue with default format
                }

                let input = try AVCaptureDeviceInput(device: captureDevice)
                self.captureDevice = captureDevice

                let output = AVCaptureVideoDataOutput()
                // Deliver BGRA frames for MediaPipe BlazePose compatibility
                output.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                output.alwaysDiscardsLateVideoFrames = true
                output.setSampleBufferDelegate(self, queue: self.cameraQueue)

                guard session.canAddInput(input) && session.canAddOutput(output) else {
                    throw ROMErrorHandler.ROMError.cameraSessionFailed(
                        NSError(
                            domain: "SimpleMotionService", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Cannot add camera input/output"])
                    )
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
                        FlexaLog.motion.debug(
                            "🎥 [Camera] Video mirroring set to: \(connection.isVideoMirrored) position: \(captureDevice.position.rawValue)"
                        )
                    }
                }

                // Commit configuration before storing references and starting
                FlexaLog.motion.info(
                    "📹 [CAMERA-STARTUP] Phase 7: Committing session configuration... (\(String(format: "%.3f", Date().timeIntervalSince(startupStartTime)))s)"
                )
                session.commitConfiguration()
                FlexaLog.motion.info(
                    "📹 [CAMERA-STARTUP] Phase 8: Session configuration committed (\(String(format: "%.3f", Date().timeIntervalSince(startupStartTime)))s)"
                )

                // Small delay after commit to ensure configuration is fully applied
                Thread.sleep(forTimeInterval: 0.05)

                self.captureSession = session
                self.videoOutput = output

                FlexaLog.motion.info(
                    "📹 [CAMERA-STARTUP] Phase 9: Starting session.startRunning()... (\(String(format: "%.3f", Date().timeIntervalSince(startupStartTime)))s)"
                )
                session.startRunning()
                FlexaLog.motion.info(
                    "📹 [CAMERA-STARTUP] Phase 10: session.startRunning() returned (\(String(format: "%.3f", Date().timeIntervalSince(startupStartTime)))s)"
                )

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
                    NotificationCenter.default.post(
                        name: .SharedCaptureSessionReady, object: session)
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
        stopCameraObstructionMonitoring()
        cameraTeardownWorkItem?.cancel()
        cameraTeardownWorkItem = nil

        guard let session = captureSession else {
            if tearDownCompletely {
                updatePreviewSession(nil)
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: Notification.Name("SharedCaptureSessionStopped"), object: nil)
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
            NotificationCenter.default.post(
                name: Notification.Name("SharedCaptureSessionStopped"), object: nil)
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
                    NotificationCenter.default.post(
                        name: Notification.Name("SharedCaptureSessionStopped"), object: nil)
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
                    FlexaLog.motion.info(
                        "✅ [Camera] Session fully stopped after \(attempts) attempts")
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
                    NotificationCenter.default.post(
                        name: Notification.Name("SharedCaptureSessionStopped"), object: nil)
                }
            }
        }
    }

    // Frame counting for debugging
    private var captureFrameCount: Int = 0

    @objc func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        captureFrameCount += 1

        // Log every 30th frame to avoid spam
        if captureFrameCount % 30 == 0 {
            FlexaLog.motion.debug(
                "📹 [CAPTURE] Frame #\(self.captureFrameCount) received - session active: \(self.isSessionActive)"
            )
        }

        guard isSessionActive else {
            if captureFrameCount % 30 == 0 {
                FlexaLog.motion.warning(
                    "📹 [CAPTURE] Frame received but session not active - dropping")
            }
            return
        }

        // Throttle camera processing under memory pressure and drain autorelease pool per frame
        let now = CFAbsoluteTimeGetCurrent()
        let minInterval =
            (memoryPressureLevel == .normal)
            ? minCameraFrameIntervalNormal : minCameraFrameIntervalThrottled
        if now - lastCameraProcessTime < minInterval {
            return
        }
        lastCameraProcessTime = now

        if captureFrameCount % 30 == 0 {
            FlexaLog.motion.debug(
                "📹 [CAPTURE] Processing frame #\(self.captureFrameCount) through BlazePose pipeline"
            )
        }

        autoreleasepool {
            // Process camera frame for pose detection
            poseProvider.processFrame(sampleBuffer)
        }
    }

    private func smoothPoseKeypoints(_ keypoints: SimplifiedPoseKeypoints)
        -> SimplifiedPoseKeypoints
    {
        let previous = lastSmoothedPose
        let deltaTime = max(
            1.0 / 120.0, keypoints.timestamp - (previous?.timestamp ?? keypoints.timestamp))

        func smooth(_ joint: PoseJoint, newPoint: CGPoint?) -> CGPoint? {
            let previousPoint = point(from: previous, joint: joint)
            return smoothPoint(
                for: joint,
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
            leftWristConfidence: keypoints.leftWristConfidence,
            rightWristConfidence: keypoints.rightWristConfidence,
            noseConfidence: keypoints.noseConfidence,
            neckConfidence: keypoints.neckConfidence
        )

        lastSmoothedPose = smoothed
        return smoothed
    }

    private func smoothPoint(
        for joint: PoseJoint,
        newPoint: CGPoint?,
        previous: CGPoint?,
        timestamp: TimeInterval,
        deltaTime: TimeInterval
    ) -> CGPoint? {
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

        poseDropoutCache[joint] = PoseCacheEntry(
            point: smoothed, expiry: timestamp + poseDropoutGracePeriod)
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
        // CRITICAL: Filter out zero/invalid poses that contaminate ROM calculations
        guard isValidCameraPose(keypoints) else {
            FlexaLog.motion.debug(
                "🚫 [ZERO-FILTER] Filtered invalid camera pose - likely initialization artifact")
            return
        }

        let smoothedKeypoints = smoothPoseKeypoints(keypoints)
        let timestamp = Date().timeIntervalSince1970
        let romActiveSideOverride = manualCameraArmOverride
        let rawCameraROM = cameraROMCalculator.calculateROM(
            from: smoothedKeypoints,
            jointPreference: preferredCameraJoint,
            activeSide: romActiveSideOverride
        )

        DispatchQueue.main.async {
            self.poseKeypoints = smoothedKeypoints
            self.currentPoseKeypoints = smoothedKeypoints
            self.lastPoseDetectionTimestamp = timestamp
            self.setCameraObstructionState(obstructed: false, reason: nil)
            self.refreshActiveCameraArm(with: smoothedKeypoints)

            guard self.isCameraExercise else { return }

            // CRITICAL: Additional ROM validation to prevent contamination
            guard rawCameraROM > 0.1 && rawCameraROM.isFinite else {
                FlexaLog.motion.debug("🚫 [ROM-FILTER] Filtered invalid ROM: \(rawCameraROM)°")
                return
            }

            let validatedROM = self.validateAndNormalizeROM(rawCameraROM)
            self.currentROM = validatedROM

            if validatedROM > self.maxROM {
                self.maxROM = validatedROM
            }

            self.romHistory.append(validatedROM)
            self.cameraSmoothnessAnalyzer.processPose(
                smoothedKeypoints,
                timestamp: timestamp,
                activeSide: self.activeCameraArm
            )

            // 🎯 Feed wrist position to SPARC for smoothness tracking with ZERO FILTERING
            if self.isSessionActive {
                let activeSide = self.activeCameraArm
                if activeSide == .right {
                    if let wrist = smoothedKeypoints.rightWrist, self.isValidWristPosition(wrist) {
                        self.sparcService.addVisionMovement(timestamp: timestamp, position: wrist)
                        FlexaLog.motion.debug(
                            "📊 [CameraSPARC] Wrist tracked: right at (\(String(format: "%.0f", wrist.x)), \(String(format: "%.0f", wrist.y)))"
                        )
                    } else {
                        FlexaLog.motion.debug(
                            "📊 [CameraSPARC] Skipped sample: right wrist invalid/nil")
                    }
                } else {
                    if let wrist = smoothedKeypoints.leftWrist, self.isValidWristPosition(wrist) {
                        self.sparcService.addVisionMovement(timestamp: timestamp, position: wrist)
                        FlexaLog.motion.debug(
                            "📊 [CameraSPARC] Wrist tracked: left at (\(String(format: "%.0f", wrist.x)), \(String(format: "%.0f", wrist.y)))"
                        )
                    } else {
                        FlexaLog.motion.debug(
                            "📊 [CameraSPARC] Skipped sample: left wrist invalid/nil")
                    }
                }
            }

            if self.isCustomCameraSession {
                self.customExerciseRepDetector?.processCameraKeypoints(
                    smoothedKeypoints,
                    timestamp: timestamp
                )
            }

            FlexaLog.motion.debug(
                "📐 [ROM Consistency] Camera ROM raw=\(String(format: "%.1f", rawCameraROM))° validated=\(String(format: "%.1f", validatedROM))°"
            )
        }
    }

    // MARK: - Calibration Methods
    private var reformedCalibrationInProgress = false

    /// Automatic reformed calibration flow: captures 0°, 90°, 180° using ARKit
    func runReformedCalibrationFlow(gameType: String? = nil, completion: ((Bool) -> Void)? = nil) {
        guard !reformedCalibrationInProgress else {
            completion?(false)
            return
        }
        reformedCalibrationInProgress = true
        let calMgr = CalibrationDataManager.shared
        calMgr.startCalibrationProcess()
        FlexaLog.motion.info("🎯 [AutoCal] Hold phone at shoulder (0°). Capturing in 1.5s…")

        func snap(
            _ angle: CalibrationDataManager.CalibrationAngle, delay: TimeInterval,
            next: @escaping () -> Void
        ) {
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
        // Ensure ARKit tracker is available for calibration
        if !isARKitRunning {
            arkitTracker.start()
            updateIsARKitRunning(true)
            FlexaLog.motion.info("📍 [AutoCal] Started ARKit tracker for calibration")
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
                        completion?(
                            CalibrationDataManager.shared.currentCalibration?.isCalibrationValid
                                == true)
                    }
                }
            }
        }
    }

    // MARK: - Zero Position Filtering (Critical for ROM accuracy)

    /// Validates camera pose to filter out zero/invalid positions during initialization
    /// This prevents massive ROM spikes caused by (0,0,0) positions contaminating calculations
    private func isValidCameraPose(_ keypoints: SimplifiedPoseKeypoints) -> Bool {
        // Check if critical landmarks are present and non-zero
        let activeSide = activeCameraArm

        if activeSide == .right {
            // For right arm tracking, need right shoulder, elbow, wrist
            guard let shoulder = keypoints.rightShoulder,
                let elbow = keypoints.rightElbow,
                let wrist = keypoints.rightWrist
            else {
                FlexaLog.motion.debug("🚫 [ZERO-FILTER] Missing right arm landmarks")
                return false
            }

            // Check for zero positions (initialization artifacts)
            if shoulder == .zero || elbow == .zero || wrist == .zero {
                FlexaLog.motion.debug("🚫 [ZERO-FILTER] Zero position detected in right arm")
                return false
            }

            // Edge filter removed - landmarks at screen edges are valid positions!

        } else {
            // For left arm tracking, need left shoulder, elbow, wrist
            guard let shoulder = keypoints.leftShoulder,
                let elbow = keypoints.leftElbow,
                let wrist = keypoints.leftWrist
            else {
                FlexaLog.motion.debug("🚫 [ZERO-FILTER] Missing left arm landmarks")
                return false
            }

            // Check for zero positions
            if shoulder == .zero || elbow == .zero || wrist == .zero {
                FlexaLog.motion.debug("🚫 [ZERO-FILTER] Zero position detected in left arm")
                return false
            }

            // Edge filter removed - landmarks at screen edges are valid positions!
        }

        // Additional confidence check
        let minConfidence: Float = 0.3
        if activeSide == .right {
            if keypoints.rightShoulderConfidence < minConfidence
                || keypoints.rightElbowConfidence < minConfidence
            {
                FlexaLog.motion.debug("🚫 [ZERO-FILTER] Low confidence on right arm landmarks")
                return false
            }
        } else {
            if keypoints.leftShoulderConfidence < minConfidence
                || keypoints.leftElbowConfidence < minConfidence
            {
                FlexaLog.motion.debug("🚫 [ZERO-FILTER] Low confidence on left arm landmarks")
                return false
            }
        }

        return true
    }

    /// Validates wrist position for SPARC tracking to prevent zero contamination
    private func isValidWristPosition(_ position: CGPoint) -> Bool {
        // Filter out zero positions
        if position == .zero {
            return false
        }

        // Filter out positions too close to zero
        if abs(position.x) < 5.0 || abs(position.y) < 5.0 {
            return false
        }

        // Filter out positions at image edges (likely tracking errors)
        if position.x < 10 || position.x > 470 || position.y < 10 || position.y > 630 {
            return false
        }

        // Filter out non-finite values
        if !position.x.isFinite || !position.y.isFinite {
            return false
        }

        return true
    }

    func stop() {
        stopSession()
    }

}
