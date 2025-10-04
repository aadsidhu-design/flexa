import Foundation
import CoreMotion
import ARKit
import simd

/// Reformed calibration system using IMU for angles and ARKit for 3D positions/arm length
class CalibrationDataManager: ObservableObject {
    static let shared = CalibrationDataManager()
    
    // MARK: - Calibration Data Structure
    struct AnatomicalCalibrationData: Codable {
        // IMU quaternions for 0°, 90°, 180° angle references
        let zeroQuat: [Float]          // x,y,z,w - IMU quaternion at 0° position
        let ninetyQuat: [Float]        // x,y,z,w - IMU quaternion at 90° position  
        let oneEightyQuat: [Float]     // x,y,z,w - IMU quaternion at 180° position
        
        // ARKit 3D positions for arm length calculation
        let zeroPosition: [Double]     // x,y,z - ARKit position at 0°
        let ninetyPosition: [Double]   // x,y,z - ARKit position at 90°
        let oneEightyPosition: [Double] // x,y,z - ARKit position at 180°
        
        // Calculated arm properties
        let armLength: Double          // Pure arm length from ARKit measurements
        let shoulderPosition: [Double] // x,y,z - Estimated shoulder position
        // Optional manual/estimated measurements
        var forearmLength: Double? = nil
        var gripOffset: Double? = nil
        
        // Calibration metadata
        let calibrationTimestamp: Date
        let gameTypeCalibrated: String?
        let isCalibrationValid: Bool
        let calibrationAccuracy: Double
        
        // Convenience accessors for IMU quaternions
        var zeroQuaternion: simd_quatf {
            simd_quatf(ix: zeroQuat[0], iy: zeroQuat[1], iz: zeroQuat[2], r: zeroQuat[3])
        }
        var ninetyQuaternion: simd_quatf {
            simd_quatf(ix: ninetyQuat[0], iy: ninetyQuat[1], iz: ninetyQuat[2], r: ninetyQuat[3])
        }
        var oneEightyQuaternion: simd_quatf {
            simd_quatf(ix: oneEightyQuat[0], iy: oneEightyQuat[1], iz: oneEightyQuat[2], r: oneEightyQuat[3])
        }
        
        // Convenience accessors for ARKit positions
        var zeroPos3D: SIMD3<Double> {
            SIMD3<Double>(zeroPosition[0], zeroPosition[1], zeroPosition[2])
        }
        var ninetyPos3D: SIMD3<Double> {
            SIMD3<Double>(ninetyPosition[0], ninetyPosition[1], ninetyPosition[2])
        }
        var oneEightyPos3D: SIMD3<Double> {
            SIMD3<Double>(oneEightyPosition[0], oneEightyPosition[1], oneEightyPosition[2])
        }
        var shoulderPos3D: SIMD3<Double> {
            SIMD3<Double>(shoulderPosition[0], shoulderPosition[1], shoulderPosition[2])
        }
        
        init(zeroQuat: simd_quatf,
             ninetyQuat: simd_quatf,
             oneEightyQuat: simd_quatf,
             zeroPos: SIMD3<Double>,
             ninetyPos: SIMD3<Double>,
             oneEightyPos: SIMD3<Double>,
             armLength: Double,
             shoulderPos: SIMD3<Double>,
             calibrationTimestamp: Date,
             gameTypeCalibrated: String?,
             isCalibrationValid: Bool,
             calibrationAccuracy: Double) {
            
            // Store IMU quaternions
            self.zeroQuat = [zeroQuat.imag.x, zeroQuat.imag.y, zeroQuat.imag.z, zeroQuat.real]
            self.ninetyQuat = [ninetyQuat.imag.x, ninetyQuat.imag.y, ninetyQuat.imag.z, ninetyQuat.real]
            self.oneEightyQuat = [oneEightyQuat.imag.x, oneEightyQuat.imag.y, oneEightyQuat.imag.z, oneEightyQuat.real]
            
            // Store ARKit positions
            self.zeroPosition = [zeroPos.x, zeroPos.y, zeroPos.z]
            self.ninetyPosition = [ninetyPos.x, ninetyPos.y, ninetyPos.z]
            self.oneEightyPosition = [oneEightyPos.x, oneEightyPos.y, oneEightyPos.z]
            
            // Store calculated arm properties
            self.armLength = armLength
            self.shoulderPosition = [shoulderPos.x, shoulderPos.y, shoulderPos.z]
            
            // Store metadata
            self.calibrationTimestamp = calibrationTimestamp
            self.gameTypeCalibrated = gameTypeCalibrated
            self.isCalibrationValid = isCalibrationValid
            self.calibrationAccuracy = calibrationAccuracy
        }
    }
    
    @Published private(set) var currentCalibration: AnatomicalCalibrationData?
    @Published private(set) var isCalibrated: Bool = false
    @Published private(set) var calibrationAccuracy: Double = 0.0
    
    private let userDefaults = UserDefaults.standard
    private let calibrationKey = "anatomical_rom_calibration_v2"
    private let oldCalibrationKey = "anatomical_rom_calibration" // v1 key
    private let migrationKey = "calibration_migration_completed"
    private let keychainArmLengthKey = "rom_calibration_arm_length_v1"
    
    // MARK: - Initialization
    init() {
        migrateOldCalibrationData()
        loadStoredCalibration()
        validateCalibrationOnAppOpen()
        
        // Ensure we always have some calibration data available
        if currentCalibration == nil {
            createDefaultCalibration()
        }
    }
    
    // MARK: - Enhanced Calibration Process
    
    func startCalibrationProcess() {
        print("🎯 [CalibrationManager] Starting enhanced anatomical zero calibration process")
        currentCalibration = nil
        isCalibrated = false
        calibrationAccuracy = 0.0
    }
    
    func captureCalibrationPosition(_ angle: CalibrationAngle, deviceMotion: CMDeviceMotion, gameType: String?) {
        let quaternion = simd_quatf(ix: Float(deviceMotion.attitude.quaternion.x),
                                    iy: Float(deviceMotion.attitude.quaternion.y),
                                    iz: Float(deviceMotion.attitude.quaternion.z),
                                    r: Float(deviceMotion.attitude.quaternion.w))
        
        let gravity = simd_float3(
            Float(deviceMotion.gravity.x),
            Float(deviceMotion.gravity.y),
            Float(deviceMotion.gravity.z)
        )
        
        print("🎯 [CalibrationManager] Captured \(angle) position: quat=\(quaternion), gravity=\(gravity)")
        
        storeTemporaryCalibrationData(angle: angle, quaternion: quaternion, gravity: gravity, gameType: gameType)
    }
    
    enum CalibrationAngle {
        case zero, ninety, oneEighty
    }
    // Simple two-point ARKit arm-length capture
    enum QuickArmLengthStage { case chest, reach }
    
    private var tempZeroQuat: simd_quatf?
    private var tempNinetyQuat: simd_quatf?
    private var tempOneEightyQuat: simd_quatf?
    private var tempGravity: simd_float3?
    // Capture ARKit positions and IMU quaternions during calibration
    private var zeroPosition: SIMD3<Double>?
    private var ninetyPosition: SIMD3<Double>?
    private var oneEightyPosition: SIMD3<Double>?
    // Quick arm-length capture positions
    private var quickChestPosition: SIMD3<Double>?
    private var quickReachPosition: SIMD3<Double>?
    
    private func storeTemporaryCalibrationData(angle: CalibrationAngle, quaternion: simd_quatf, gravity: simd_float3, gameType: String?) {
        tempGravity = gravity
        
        // Capture both IMU quaternion and ARKit 3D position
        if let arkitTransform = SimpleMotionService.shared.universal3DEngine.currentTransform {
            let position = SIMD3<Double>(
                Double(arkitTransform.columns.3.x),
                Double(arkitTransform.columns.3.y),
                Double(arkitTransform.columns.3.z)
            )
            
            switch angle {
            case .zero:
                tempZeroQuat = quaternion
                zeroPosition = position
                print("🎯 [Reformed Calibration] Captured 0° - IMU: \(quaternion), Position: \(String(format: "(%.3f,%.3f,%.3f)", position.x, position.y, position.z))")
                
            case .ninety:
                tempNinetyQuat = quaternion
                ninetyPosition = position
                print("🎯 [Reformed Calibration] Captured 90° - IMU: \(quaternion), Position: \(String(format: "(%.3f,%.3f,%.3f)", position.x, position.y, position.z))")
                
            case .oneEighty:
                tempOneEightyQuat = quaternion
                oneEightyPosition = position
                print("🎯 [Reformed Calibration] Captured 180° - IMU: \(quaternion), Position: \(String(format: "(%.3f,%.3f,%.3f)", position.x, position.y, position.z))")
            }
        } else {
            print("⚠️ [Reformed Calibration] ARKit position not available for \(angle) - ensure ARKit is running")
            return
        }
        
        // Validate and create calibration when all three positions are captured
        if let zero = tempZeroQuat, let ninety = tempNinetyQuat, let oneEighty = tempOneEightyQuat,
           let zeroPos = zeroPosition, let ninetyPos = ninetyPosition, let oneEightyPos = oneEightyPosition {
            validateAndCreateReformedCalibration(
                zeroQuat: zero, ninetyQuat: ninety, oneEightyQuat: oneEighty,
                zeroPos: zeroPos, ninetyPos: ninetyPos, oneEightyPos: oneEightyPos,
                gameType: gameType
            )
        }
    }

    // MARK: - ARKit-only calibration capture
    /// Capture calibration pose using ARKit camera transform exclusively (no CoreMotion dependency)
    func captureCalibrationARKit(angle: CalibrationAngle, gameType: String?) {
        guard let tr = SimpleMotionService.shared.universal3DEngine.currentTransform else {
            print("⚠️ [CalibrationManager] ARKit transform unavailable for \(angle) capture. Ensure ARKit session is running.")
            return
        }
        // Orientation quaternion from ARKit rotation (upper-left 3x3)
        let rot = simd_float3x3(
            simd_float3(tr.columns.0.x, tr.columns.0.y, tr.columns.0.z),
            simd_float3(tr.columns.1.x, tr.columns.1.y, tr.columns.1.z),
            simd_float3(tr.columns.2.x, tr.columns.2.y, tr.columns.2.z)
        )
        let q = simd_quatf(rot)
        // Gravity reference: world-aligned up when using .gravity alignment
        let gravity = simd_float3(0, -1, 0)

        // Positions are captured inside storeTemporaryCalibrationData via currentTransform
        storeTemporaryCalibrationData(angle: angle, quaternion: q, gravity: gravity, gameType: gameType)
    }

    // MARK: - Quick Arm Length (Chest ➜ Reach)
    func clearQuickArmLength() {
        quickChestPosition = nil
        quickReachPosition = nil
        print("🧹 [QuickArmLen] Cleared temporary positions")
    }
    /// Capture current ARKit position as either chest or full reach
    func captureQuickArmLength(_ stage: QuickArmLengthStage) {
        guard let tr = SimpleMotionService.shared.universal3DEngine.currentTransform else {
            print("⚠️ [QuickArmLen] ARKit transform unavailable for \(stage) capture.")
            return
        }
        let pos = SIMD3<Double>(
            Double(tr.columns.3.x),
            Double(tr.columns.3.y),
            Double(tr.columns.3.z)
        )
        switch stage {
        case .chest:
            quickChestPosition = pos
            print("🎯 [QuickArmLen] Captured CHEST position: \(String(format: "%.3f,%.3f,%.3f", pos.x, pos.y, pos.z))m")
        case .reach:
            quickReachPosition = pos
            print("🎯 [QuickArmLen] Captured REACH position: \(String(format: "%.3f,%.3f,%.3f", pos.x, pos.y, pos.z))m")
        }
    }
    /// Preview measured arm length if both points captured
    func previewQuickArmLength() -> Double? {
        guard let chest = quickChestPosition, let reach = quickReachPosition else { return nil }
        let armLen = simd_distance(chest, reach)
        return max(0.3, min(1.0, armLen))
    }
    /// Persist measured arm length and shoulder position; returns saved length
    @discardableResult
    func applyQuickArmLength() -> Double? {
        guard let chest = quickChestPosition, let reach = quickReachPosition else {
            print("⚠️ [QuickArmLen] Both CHEST and REACH positions are required before applying")
            return nil
        }
        let armLen = max(0.3, min(1.2, simd_distance(chest, reach)))
        let shoulderPos = chest // treat chest pose as shoulder reference

        if let current = currentCalibration {
            var updated = AnatomicalCalibrationData(
                zeroQuat: current.zeroQuaternion,
                ninetyQuat: current.ninetyQuaternion,
                oneEightyQuat: current.oneEightyQuaternion,
                zeroPos: current.zeroPos3D,
                ninetyPos: current.ninetyPos3D,
                oneEightyPos: current.oneEightyPos3D,
                armLength: armLen,
                shoulderPos: shoulderPos,
                calibrationTimestamp: Date(),
                gameTypeCalibrated: current.gameTypeCalibrated,
                isCalibrationValid: true,
                calibrationAccuracy: max(current.calibrationAccuracy, 0.75)
            )
            updated.forearmLength = current.forearmLength
            updated.gripOffset = current.gripOffset
            saveCalibration(updated)
        } else {
            // Create minimal calibration with measured arm length
            let zeroQuat = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
            let ninetyQuat = simd_quatf(ix: 0, iy: 0.70710678, iz: 0, r: 0.70710678)
            let oneEightyQuat = simd_quatf(ix: 0, iy: 1, iz: 0, r: 0)
            let cal = AnatomicalCalibrationData(
                zeroQuat: zeroQuat,
                ninetyQuat: ninetyQuat,
                oneEightyQuat: oneEightyQuat,
                zeroPos: chest,
                ninetyPos: chest, // placeholders; not used by engine
                oneEightyPos: reach,
                armLength: armLen,
                shoulderPos: shoulderPos,
                calibrationTimestamp: Date(),
                gameTypeCalibrated: nil,
                isCalibrationValid: true,
                calibrationAccuracy: 0.8
            )
            saveCalibration(cal)
        }
        print("✅ [QuickArmLen] Applied measured arm length: \(String(format: "%.3f", armLen))m; shoulder set from CHEST pose")
        return armLen
    }
    
    // Reformed calibration validation using IMU angles and ARKit positions
    private func validateAndCreateReformedCalibration(
        zeroQuat: simd_quatf, ninetyQuat: simd_quatf, oneEightyQuat: simd_quatf,
        zeroPos: SIMD3<Double>, ninetyPos: SIMD3<Double>, oneEightyPos: SIMD3<Double>,
        gameType: String?
    ) {
        // Validate IMU quaternion angles
        let zeroToNinetyAngle = calculateAngleBetweenQuaternions(zeroQuat, ninetyQuat)
        let zeroToOneEightyAngle = calculateAngleBetweenQuaternions(zeroQuat, oneEightyQuat)
        
        let ninetyAccuracy = abs(zeroToNinetyAngle - 90.0) / 90.0
        let oneEightyAccuracy = abs(zeroToOneEightyAngle - 180.0) / 180.0
        let overallAccuracy = 1.0 - max(ninetyAccuracy, oneEightyAccuracy)
        let isValid = overallAccuracy > 0.7  // Slightly more lenient
        
        print("🎯 [Reformed Calibration] IMU Validation: 0°→90° = \(String(format: "%.1f", zeroToNinetyAngle))°, 0°→180° = \(String(format: "%.1f", zeroToOneEightyAngle))°")
        
        if isValid {
            // Calculate arm length from ARKit positions
            let armLength = calculateArmLengthFromPositions(zeroPos: zeroPos, ninetyPos: ninetyPos, oneEightyPos: oneEightyPos)
            let shoulderPos = estimateShoulderPosition(zeroPos: zeroPos, oneEightyPos: oneEightyPos, armLength: armLength)
            
            let calibrationData = AnatomicalCalibrationData(
                zeroQuat: zeroQuat,
                ninetyQuat: ninetyQuat,
                oneEightyQuat: oneEightyQuat,
                zeroPos: zeroPos,
                ninetyPos: ninetyPos,
                oneEightyPos: oneEightyPos,
                armLength: armLength,
                shoulderPos: shoulderPos,
                calibrationTimestamp: Date(),
                gameTypeCalibrated: gameType,
                isCalibrationValid: true,
                calibrationAccuracy: overallAccuracy
            )
            
            saveCalibration(calibrationData)
            clearTemporaryData()
            
            print("✅ [Reformed Calibration] Complete - Arm length: \(String(format: "%.2f", armLength))m, Accuracy: \(String(format: "%.1f", overallAccuracy * 100))%")
        } else {
            print("❌ [Reformed Calibration] Failed validation - accuracy too low: \(String(format: "%.1f", overallAccuracy * 100))%")
            clearTemporaryData()
            NotificationCenter.default.post(name: NSNotification.Name("CalibrationFailed"), object: nil, userInfo: ["reason": "Low accuracy"])
        }
    }
    
    private func calculateArmLengthFromPositions(zeroPos: SIMD3<Double>, ninetyPos: SIMD3<Double>, oneEightyPos: SIMD3<Double>) -> Double {
        // Use the longest distance as arm length (likely 0° to 180°)
        let zeroToNinety = simd_distance(zeroPos, ninetyPos)
        let zeroToOneEighty = simd_distance(zeroPos, oneEightyPos)
        let ninetyToOneEighty = simd_distance(ninetyPos, oneEightyPos)
        
        let maxDistance = max(zeroToNinety, zeroToOneEighty, ninetyToOneEighty)
        
        // For 180° arc, arm length = chord/2; for 90° arc, arm length = chord/√2
        let armLength: Double
        if maxDistance == zeroToOneEighty {
            // 180° arc - chord length = 2R, so R = chord/2
            armLength = maxDistance / 2.0
        } else {
            // 90° arc - chord length = R√2, so R = chord/√2
            armLength = maxDistance / sqrt(2.0)
        }
        
        // Clamp to reasonable arm length range
        return max(0.3, min(1.0, armLength))
    }
    
    private func estimateShoulderPosition(zeroPos: SIMD3<Double>, oneEightyPos: SIMD3<Double>, armLength: Double) -> SIMD3<Double> {
        // Shoulder is at the midpoint of the 0°-180° arc, offset by arm length
        let midpoint = (zeroPos + oneEightyPos) / 2.0
        let direction = simd_normalize(oneEightyPos - zeroPos)
        let perpendicular = SIMD3<Double>(-direction.y, direction.x, direction.z) // Rotate 90° in XY plane
        return midpoint + perpendicular * armLength * 0.5  // Offset towards body
    }
    
    private func clearTemporaryData() {
        tempZeroQuat = nil
        tempNinetyQuat = nil
        tempOneEightyQuat = nil
        tempGravity = nil
        zeroPosition = nil
        ninetyPosition = nil
        oneEightyPosition = nil
    }
    
    // Legacy method - kept for compatibility (no-op now). Use validateAndCreateReformedCalibration instead.
    private func validateAndCreateCalibration(zero: simd_quatf, ninety: simd_quatf, oneEighty: simd_quatf, gravity: simd_float3, gameType: String?) {
        guard let zPos = zeroPosition, let nPos = ninetyPosition, let oPos = oneEightyPosition else {
            print("⚠️ [CalibrationManager] Legacy validate called without ARKit positions. Skipping.")
            return
        }
        validateAndCreateReformedCalibration(
            zeroQuat: zero,
            ninetyQuat: ninety,
            oneEightyQuat: oneEighty,
            zeroPos: zPos,
            ninetyPos: nPos,
            oneEightyPos: oPos,
            gameType: gameType
        )
    }
    
    // MARK: - Anatomical Zero ROM Calculation
    
    func calculateAnatomicalZeroROM(currentMotion: CMDeviceMotion) -> Double {
        guard let calibration = currentCalibration, calibration.isCalibrationValid else {
            if currentCalibration == nil { createDefaultCalibration() }
            return estimateROMWithoutCalibration(currentMotion)
        }
        
        // Calculate ROM relative to calibrated zero position (starts at 0°)
        let currentQuaternion = simd_quatf(ix: Float(currentMotion.attitude.quaternion.x),
                                           iy: Float(currentMotion.attitude.quaternion.y),
                                           iz: Float(currentMotion.attitude.quaternion.z),
                                           r: Float(currentMotion.attitude.quaternion.w))
        
        // Calculate rotation from calibrated zero position
        let zeroQuat = calibration.zeroQuaternion
        let rotationFromZero = currentQuaternion * simd_inverse(zeroQuat)
        
        // Extract angle ensuring it starts at 0° for zero position
        let w = Double(rotationFromZero.real)
        let angle = 2.0 * acos(min(1.0, max(-1.0, abs(w)))) * 180.0 / .pi
        
        return max(0, min(180, angle))
    }
    
    private func applyCalibratedAngleCorrection(phoneAngle: Double, calibration: AnatomicalCalibrationData) -> Double {
        let armLengthFactor = calibration.armLength / 0.6
        let correctedAngle = phoneAngle * armLengthFactor
        return correctedAngle
    }
    
    // MARK: - Utility Methods
    
    private func calculateAngleBetweenQuaternions(_ q1: simd_quatf, _ q2: simd_quatf) -> Double {
        let dotVal: Float = simd_dot(q1, q2)
        let clampedDot = max(-1.0, min(1.0, Double(abs(dotVal))))
        let angleRadians = 2.0 * acos(clampedDot)
        return Double(angleRadians * 180.0 / .pi)
    }
    
    private func createOrientationCalibrationMatrix(zero: simd_quatf, ninety: simd_quatf) -> simd_float3x3 {
        return simd_float3x3(1.0)
    }
    
    private func estimateArmLengthWithPhoneOffset() -> Double {
        return 0.65
    }
    
    private func estimateShoulderToPhoneVector(gravity: simd_float3) -> simd_float3 {
        return simd_normalize(gravity) * 0.65
    }
    
    private func estimateROMWithoutCalibration(_ motion: CMDeviceMotion) -> Double {
        // Use 3D acceleration magnitude for movement detection instead of phone tilt
        let userAccel = motion.userAcceleration
        let totalAcceleration = sqrt(userAccel.x * userAccel.x + userAccel.y * userAccel.y + userAccel.z * userAccel.z)
        
        // Convert acceleration to ROM estimate (scaled for arm movement)
        let accelerationROM = totalAcceleration * 45.0 // Scale factor for arm movement
        
        return max(0, min(180, accelerationROM))
    }
    
    private func createDefaultCalibration() {
        print("🎯 [CalibrationManager] Creating default calibration for basic ROM tracking")
        
        // Use stored arm length from Keychain if available
        var armLen = 0.65
        if let armLenStr = KeychainManager.shared.getString(for: keychainArmLengthKey),
           let storedArmLen = Double(armLenStr), storedArmLen > 0.2, storedArmLen < 1.5 {
            armLen = storedArmLen
            print("🔒 [CalibrationManager] Using stored arm length: \(String(format: "%.2f", armLen))m")
        }
        
        // Create basic default quaternions for a standard arm position
        let zeroQuat = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1) // Identity quaternion
        let ninetyQuat = simd_quatf(ix: 0, iy: 0.707, iz: 0, r: 0.707) // 90 degree rotation
        let oneEightyQuat = simd_quatf(ix: 0, iy: 1, iz: 0, r: 0) // 180 degree rotation
        
        let defaultCalibration = AnatomicalCalibrationData(
            zeroQuat: zeroQuat,
            ninetyQuat: ninetyQuat,
            oneEightyQuat: oneEightyQuat,
            zeroPos: SIMD3<Double>(0, 0, 0),
            ninetyPos: SIMD3<Double>(0, armLen, 0),
            oneEightyPos: SIMD3<Double>(0, armLen * 2.0, 0),
            armLength: armLen,
            shoulderPos: SIMD3<Double>(0, -armLen, 0),
            calibrationTimestamp: Date(),
            gameTypeCalibrated: nil,
            isCalibrationValid: true,
            calibrationAccuracy: 0.7 // Reasonable default accuracy
        )
        
        currentCalibration = defaultCalibration
        isCalibrated = true
        calibrationAccuracy = 0.7
        
        // Don't save this default calibration to avoid overwriting user calibration
        print("✅ [CalibrationManager] Default calibration created for session with arm length: \(String(format: "%.2f", armLen))m")
    }
    
    // MARK: - Persistence
    
    private func saveCalibration(_ data: AnatomicalCalibrationData) {
        do {
            let encodedData = try JSONEncoder().encode(data)
            userDefaults.set(encodedData, forKey: calibrationKey)
            
            DispatchQueue.main.async {
                self.currentCalibration = data
                self.isCalibrated = true
                self.calibrationAccuracy = data.calibrationAccuracy
            }
            
            print("✅ [CalibrationManager] Anatomical calibration saved successfully - accuracy: \(String(format: "%.1f", data.calibrationAccuracy * 100))%")
            
            NotificationCenter.default.post(name: NSNotification.Name("AnatomicalCalibrationComplete"), object: nil, userInfo: ["accuracy": data.calibrationAccuracy])
            
            // Persist arm length in Keychain so it survives app uninstall/reinstall
            let ok = KeychainManager.shared.store(String(format: "%.4f", data.armLength), for: keychainArmLengthKey)
            if ok {
                print("🔒 [CalibrationManager] Arm length saved to Keychain for long-term persistence")
            }
            
        } catch {
            print("❌ [CalibrationManager] Failed to save calibration: \(error)")
        }
    }

    // MARK: - Manual overrides
    /// Override stored segment lengths; AR reference data remains unchanged.
    func overrideManualSegments(armLength: Double?, forearmLength: Double?, gripOffset: Double?) {
        guard let current = currentCalibration else {
            print("⚠️ [CalibrationManager] No calibration to override; ignoring manual segments")
            return
        }
        // Clamp arm length if provided
        let newArmLen = armLength.map { max(0.3, min(1.2, $0)) } ?? current.armLength
        var newCal = AnatomicalCalibrationData(
            zeroQuat: current.zeroQuaternion,
            ninetyQuat: current.ninetyQuaternion,
            oneEightyQuat: current.oneEightyQuaternion,
            zeroPos: current.zeroPos3D,
            ninetyPos: current.ninetyPos3D,
            oneEightyPos: current.oneEightyPos3D,
            armLength: newArmLen,
            shoulderPos: current.shoulderPos3D,
            calibrationTimestamp: Date(),
            gameTypeCalibrated: current.gameTypeCalibrated,
            isCalibrationValid: current.isCalibrationValid,
            calibrationAccuracy: current.calibrationAccuracy
        )
        newCal.forearmLength = forearmLength ?? current.forearmLength
        newCal.gripOffset = gripOffset ?? current.gripOffset
        saveCalibration(newCal)
    }
    
    private func loadStoredCalibration() {
        if let data = userDefaults.data(forKey: calibrationKey) {
            do {
                let calibration = try JSONDecoder().decode(AnatomicalCalibrationData.self, from: data)
                let daysSinceCalibration = Date().timeIntervalSince(calibration.calibrationTimestamp) / (24 * 3600)
                if daysSinceCalibration > 30 {
                    print("⚠️ [CalibrationManager] Stored calibration is \(Int(daysSinceCalibration)) days old - recommending recalibration")
                }
                self.currentCalibration = calibration
                self.isCalibrated = calibration.isCalibrationValid
                self.calibrationAccuracy = calibration.calibrationAccuracy
                print("✅ [CalibrationManager] Loaded stored calibration - accuracy: \(String(format: "%.1f", calibration.calibrationAccuracy * 100))%")
                return
            } catch {
                print("❌ [CalibrationManager] Failed to load calibration: \(error)")
                userDefaults.removeObject(forKey: calibrationKey)
                // Fall through to Keychain fallback
            }
        }
        // Fallback: restore arm length from Keychain (survives uninstall) and create a minimal calibration
        if let armLenStr = KeychainManager.shared.getString(for: keychainArmLengthKey),
           let armLen = Double(armLenStr), armLen > 0.2, armLen < 1.5 {
            let zeroQuat = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
            let ninetyQuat = simd_quatf(ix: 0, iy: 0.70710678, iz: 0, r: 0.70710678)
            let oneEightyQuat = simd_quatf(ix: 0, iy: 1, iz: 0, r: 0)
            let cal = AnatomicalCalibrationData(
                zeroQuat: zeroQuat,
                ninetyQuat: ninetyQuat,
                oneEightyQuat: oneEightyQuat,
                zeroPos: SIMD3<Double>(0, 0, 0),
                ninetyPos: SIMD3<Double>(0, armLen, 0),
                oneEightyPos: SIMD3<Double>(0, armLen * 2.0, 0),
                armLength: armLen,
                shoulderPos: SIMD3<Double>(0, -armLen, 0),
                calibrationTimestamp: Date(),
                gameTypeCalibrated: nil,
                isCalibrationValid: true,
                calibrationAccuracy: 0.6
            )
            self.currentCalibration = cal
            self.isCalibrated = true
            self.calibrationAccuracy = 0.6
            print("🔒 [CalibrationManager] Restored arm length from Keychain (\(String(format: "%.2f", armLen))m); minimal calibration created")
        }
    }
    
    func clearCalibration() {
        userDefaults.removeObject(forKey: calibrationKey)
        currentCalibration = nil
        isCalibrated = false
        calibrationAccuracy = 0.0
        print("🗑️ [CalibrationManager] Calibration data cleared")
    }
    
    func applyGameSpecificCalibration(gameType: String) {
        guard currentCalibration != nil else { return }
        print("🎯 [CalibrationManager] Applying game-specific calibration for \(gameType)")
        switch gameType.lowercased() {
        case "fruitslicer":
            print("🎯 [CalibrationManager] Applied pendulum calibration for Fruit Slicer")
        case "witchbrew":
            print("🎯 [CalibrationManager] Applied circular calibration for Witch Brew")
        case "hammertime":
            print("🎯 [CalibrationManager] Applied side-lying calibration for Hammer Time")
        default:
            print("🎯 [CalibrationManager] Applied standard calibration for \(gameType)")
        }
    }
    
    // MARK: - Migration and Validation
    
    private func migrateOldCalibrationData() {
        // One-time cleanup of legacy calibration blob that no longer matches the model
        guard !userDefaults.bool(forKey: migrationKey) else { return }
        if userDefaults.data(forKey: oldCalibrationKey) != nil {
            userDefaults.removeObject(forKey: oldCalibrationKey)
            print("🧹 [CalibrationManager] Removed legacy calibration blob (format changed)")
        } else {
            print("ℹ️ [CalibrationManager] No old calibration data found")
        }
        userDefaults.set(true, forKey: migrationKey)
    }
    
    private func validateCalibrationOnAppOpen() {
        guard let calibration = currentCalibration else {
            return
        }
        
        // Check if calibration is too old (more than 30 days)
        let daysSinceCalibration = Date().timeIntervalSince(calibration.calibrationTimestamp) / (24 * 3600)
        if daysSinceCalibration > 30 {
            print("⚠️ [CalibrationManager] Calibration is \(Int(daysSinceCalibration)) days old - marking as invalid")
            clearCalibration()
            return
        }
        
        // Check if calibration accuracy is too low
        if calibration.calibrationAccuracy < 0.5 {
            print("⚠️ [CalibrationManager] Calibration accuracy too low (\(String(format: "%.1f", calibration.calibrationAccuracy * 100))%) - marking as invalid")
            clearCalibration()
            return
        }
        
        // Validate quaternion data integrity
        let zeroQuat = calibration.zeroQuaternion
        let ninetyQuat = calibration.ninetyQuaternion
        let oneEightyQuat = calibration.oneEightyQuaternion
        
        // Check for NaN or infinite values
        if zeroQuat.real.isNaN || zeroQuat.real.isInfinite ||
           ninetyQuat.real.isNaN || ninetyQuat.real.isInfinite ||
           oneEightyQuat.real.isNaN || oneEightyQuat.real.isInfinite {
            print("❌ [CalibrationManager] Invalid quaternion data detected - clearing calibration")
            clearCalibration()
            return
        }
        
        // Check if quaternions are normalized (should be close to 1.0)
        let zeroNorm = sqrt(zeroQuat.real * zeroQuat.real + zeroQuat.imag.x * zeroQuat.imag.x + 
                           zeroQuat.imag.y * zeroQuat.imag.y + zeroQuat.imag.z * zeroQuat.imag.z)
        let ninetyNorm = sqrt(ninetyQuat.real * ninetyQuat.real + ninetyQuat.imag.x * ninetyQuat.imag.x + 
                             ninetyQuat.imag.y * ninetyQuat.imag.y + ninetyQuat.imag.z * ninetyQuat.imag.z)
        let oneEightyNorm = sqrt(oneEightyQuat.real * oneEightyQuat.real + oneEightyQuat.imag.x * oneEightyQuat.imag.x + 
                                oneEightyQuat.imag.y * oneEightyQuat.imag.y + oneEightyQuat.imag.z * oneEightyQuat.imag.z)
        
        if abs(zeroNorm - 1.0) > 0.1 || abs(ninetyNorm - 1.0) > 0.1 || abs(oneEightyNorm - 1.0) > 0.1 {
            print("❌ [CalibrationManager] Quaternions not properly normalized - clearing calibration")
            clearCalibration()
            return
        }
        
        print("✅ [CalibrationManager] Calibration validation passed - accuracy: \(String(format: "%.1f", calibration.calibrationAccuracy * 100))%, age: \(Int(daysSinceCalibration)) days")
    }
}

