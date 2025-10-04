import Foundation
import SwiftUI

/// Service to check if user has completed proper ROM calibration
class CalibrationCheckService: ObservableObject {
    static let shared = CalibrationCheckService()
    
    @Published var isCalibrated: Bool = false
    @Published var shouldShowOnboarding: Bool = false
    
    private let motionService = SimpleMotionService.shared
    
    init() {
        checkCalibrationStatus()
    }
    
    /// Check if user has completed proper ROM calibration
    func checkCalibrationStatus() {
        // Check CalibrationDataManager for stored calibration
        let hasValidCalibration = CalibrationDataManager.shared.isCalibrated &&
                                 (CalibrationDataManager.shared.currentCalibration?.isCalibrationValid ?? false)
        
        // Check if we have arm length data (Keychain or stored calibration)
        let hasArmLengthData = CalibrationDataManager.shared.currentCalibration?.armLength != nil ||
                              (KeychainManager.shared.getString(for: "rom_calibration_arm_length_v1") != nil)
        
        // ARKit engine status
        let isARKitCalibrated = motionService.universal3DEngine.isCalibrated

        // Calibration is valid if we have stored data OR ARKit is calibrated
        isCalibrated = hasValidCalibration || hasArmLengthData || isARKitCalibrated
        shouldShowOnboarding = !isCalibrated

        print("🎯 [CalibrationCheck] Calibrated=\(isCalibrated) (ARKit=\(isARKitCalibrated), Stored=\(hasValidCalibration), ArmLen=\(hasArmLengthData ? "yes" : "none")) | Onboarding=\(shouldShowOnboarding)")
    }
    
    /// Mark calibration as completed
    func markCalibrationCompleted() {
        isCalibrated = true
        shouldShowOnboarding = false
        
        // Set both flags for compatibility
        UserDefaults.standard.set(true, forKey: "hasCompletedROMCalibration")
        
        print("✅ [CalibrationCheck] Calibration marked as completed")
    }
    
    /// Reset calibration status (for testing or recalibration)
    func resetCalibration() {
        isCalibrated = false
        shouldShowOnboarding = true
        
        // Clear both flags
        UserDefaults.standard.removeObject(forKey: "hasCompletedROMCalibration")
        
        print("🔄 [CalibrationCheck] Calibration status reset")
    }
}
