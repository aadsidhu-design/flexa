import Foundation
import ARKit
import Vision
import CoreMotion
import os

/// Comprehensive error handling and recovery system for ROM calculations
/// Provides graceful degradation, session recovery, and resource monitoring
final class ROMErrorHandler: ObservableObject {
    
    // MARK: - Error Types
    
    enum ROMError: Error, LocalizedError {
        case arkitNotSupported
        case arkitSessionFailed(Error)
        case arkitTrackingLost(ARCamera.TrackingState.Reason)
        case visionProcessingFailed(Error)
        case visionPoseNotDetected
        case cameraAccessDenied
        case cameraSessionFailed(Error)
        case motionDataUnavailable
        case calibrationDataMissing
        case memoryPressureHigh
        case resourceExhaustion
        case sessionCorrupted
        case criticalSystemError(Error)
        
        var errorDescription: String? {
            switch self {
            case .arkitNotSupported:
                return "ARKit is not supported on this device"
            case .arkitSessionFailed(let error):
                return "ARKit session failed: \(error.localizedDescription)"
            case .arkitTrackingLost(let reason):
                return "ARKit tracking lost: \(reason.localizedDescription)"
            case .visionProcessingFailed(let error):
                return "Vision processing failed: \(error.localizedDescription)"
            case .visionPoseNotDetected:
                return "No pose detected in camera feed"
            case .cameraAccessDenied:
                return "Camera access denied"
            case .cameraSessionFailed(let error):
                return "Camera session failed: \(error.localizedDescription)"
            case .motionDataUnavailable:
                return "Motion sensor data unavailable"
            case .calibrationDataMissing:
                return "Calibration data missing"
            case .memoryPressureHigh:
                return "High memory pressure detected"
            case .resourceExhaustion:
                return "System resources exhausted"
            case .sessionCorrupted:
                return "Session data corrupted"
            case .criticalSystemError(let error):
                return "Critical system error: \(error.localizedDescription)"
            }
        }
        
        var recoverySuggestion: String? {
            switch self {
            case .arkitNotSupported:
                return "Use Vision-based ROM calculation instead"
            case .arkitSessionFailed, .arkitTrackingLost:
                return "Restart ARKit session or switch to Vision mode"
            case .visionProcessingFailed, .visionPoseNotDetected:
                return "Improve lighting or switch to ARKit mode"
            case .cameraAccessDenied:
                return "Grant camera permission in Settings"
            case .cameraSessionFailed:
                return "Restart camera session"
            case .motionDataUnavailable:
                return "Check device motion permissions"
            case .calibrationDataMissing:
                return "Complete device calibration"
            case .memoryPressureHigh, .resourceExhaustion:
                return "Close other apps and restart session"
            case .sessionCorrupted:
                return "Start a new exercise session"
            case .criticalSystemError:
                return "Restart the application"
            }
        }
    }
    
    enum RecoveryStrategy: CustomStringConvertible {
        case retry
        case fallbackToARKit
        case restartSession
        case gracefulDegradation
        case criticalFailure
        
        var description: String {
            switch self {
            case .retry: return "retry"
            case .fallbackToARKit: return "fallbackToARKit"
            case .restartSession: return "restartSession"
            case .gracefulDegradation: return "gracefulDegradation"
            case .criticalFailure: return "criticalFailure"
            }
        }
    }
    
    enum SystemHealth {
        case healthy
        case degraded
        case critical
        case failed
    }
    
    // MARK: - Published Properties
    
    @Published var currentError: ROMError?
    @Published var systemHealth: SystemHealth = .healthy
    @Published var isRecovering: Bool = false
    @Published var recoveryAttempts: Int = 0
    @Published var lastRecoveryTime: Date?
    
    // MARK: - Private Properties
    
    private let maxRecoveryAttempts = 3
    private let recoveryTimeout: TimeInterval = 30.0
    private var recoveryTimer: Timer?
    private var resourceMonitorTimer: Timer?
    private var errorHistory: [ROMError] = []
    private let maxErrorHistory = 50
    
    // Resource monitoring
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var lastMemoryWarning: Date?
    private let memoryWarningCooldown: TimeInterval = 60.0
    
    // Recovery callbacks
    var onRecoveryRequired: ((ROMError, RecoveryStrategy) -> Void)?
    var onSystemHealthChanged: ((SystemHealth) -> Void)?
    var onCriticalError: ((ROMError) -> Void)?
    
    // MARK: - Initialization
    
    init() {
        setupResourceMonitoring()
        setupMemoryPressureMonitoring()
        FlexaLog.motion.info("ROMErrorHandler initialized with comprehensive monitoring")
    }
    
    deinit {
        cleanup()
        FlexaLog.motion.info("ROMErrorHandler deinitialized and cleaned up")
    }
    
    // MARK: - Error Handling
    
    /// Handle ROM-related errors with automatic recovery strategies
    func handleError(_ error: ROMError) {
        FlexaLog.motion.error("ROM Error occurred: \(error.localizedDescription)")
        
        // Add to error history
        errorHistory.append(error)
        if errorHistory.count > maxErrorHistory {
            errorHistory.removeFirst()
        }
        
        // Update current error
        DispatchQueue.main.async {
            self.currentError = error
        }
        
        // Determine recovery strategy
        let strategy = determineRecoveryStrategy(for: error)
        
        // Update system health
        updateSystemHealth(for: error)
        
        // Execute recovery if possible
        if strategy != .criticalFailure {
            executeRecovery(for: error, strategy: strategy)
        } else {
            handleCriticalFailure(error)
        }
    }
    
    /// Determine the appropriate recovery strategy for an error
    private func determineRecoveryStrategy(for error: ROMError) -> RecoveryStrategy {
        // Check if we've exceeded recovery attempts
        if recoveryAttempts >= maxRecoveryAttempts {
            return .criticalFailure
        }
        
        // Check for recent similar errors (pattern detection)
        let recentSimilarErrors = errorHistory.suffix(5).filter { type(of: $0) == type(of: error) }
        if recentSimilarErrors.count >= 3 {
            return .criticalFailure
        }
        
        switch error {
        case .arkitNotSupported, .arkitSessionFailed, .arkitTrackingLost:
            return .retry // Just retry ARKit, no Vision fallback
        case .visionProcessingFailed, .visionPoseNotDetected:
            return .fallbackToARKit
        case .cameraAccessDenied, .cameraSessionFailed:
            return .fallbackToARKit
        case .motionDataUnavailable:
            return .retry // Just retry, no Vision fallback
        case .calibrationDataMissing:
            return .gracefulDegradation
        case .memoryPressureHigh:
            return .gracefulDegradation // Try cleanup first
        case .resourceExhaustion:
            return .restartSession // Force restart for critical memory issues
        case .sessionCorrupted:
            return .restartSession
        case .criticalSystemError:
            return .criticalFailure
        }
    }
    
    /// Execute recovery strategy
    private func executeRecovery(for error: ROMError, strategy: RecoveryStrategy) {
        guard !isRecovering else { return }
        
        DispatchQueue.main.async {
            self.isRecovering = true
            self.recoveryAttempts += 1
            self.lastRecoveryTime = Date()
        }
        
        FlexaLog.motion.info("Executing recovery strategy: \(strategy) for error: \(error.localizedDescription)")
        
        // Start recovery timeout
        startRecoveryTimeout()
        
        // Execute strategy
        onRecoveryRequired?(error, strategy)
        
        // Complete recovery after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.completeRecovery()
        }
    }
    
    /// Complete recovery process
    private func completeRecovery() {
        DispatchQueue.main.async {
            self.isRecovering = false
            self.currentError = nil
        }
        
        stopRecoveryTimeout()
        FlexaLog.motion.info("Recovery completed successfully")
    }
    
    /// Handle critical failures that cannot be recovered
    private func handleCriticalFailure(_ error: ROMError) {
        DispatchQueue.main.async {
            self.systemHealth = .failed
        }
        
        FlexaLog.motion.critical("Critical ROM system failure: \(error.localizedDescription)")
        onCriticalError?(error)
    }
    
    /// Update system health based on error severity
    private func updateSystemHealth(for error: ROMError) {
        let newHealth: SystemHealth
        
        switch error {
        case .arkitNotSupported, .calibrationDataMissing:
            newHealth = .degraded
        case .arkitSessionFailed, .visionProcessingFailed, .cameraSessionFailed:
            newHealth = recoveryAttempts < 2 ? .degraded : .critical
        case .memoryPressureHigh, .resourceExhaustion:
            newHealth = .critical
        case .criticalSystemError, .sessionCorrupted:
            newHealth = .failed
        default:
            newHealth = .degraded
        }
        
        DispatchQueue.main.async {
            if newHealth.rawValue > self.systemHealth.rawValue {
                self.systemHealth = newHealth
                self.onSystemHealthChanged?(newHealth)
            }
        }
    }
    
    // MARK: - Resource Monitoring
    
    /// Setup comprehensive resource monitoring
    private func setupResourceMonitoring() {
        resourceMonitorTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkSystemResources()
        }
    }
    
    /// Setup memory pressure monitoring
    private func setupMemoryPressureMonitoring() {
        memoryPressureSource = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        
        memoryPressureSource?.setEventHandler { [weak self] in
            guard let self = self else { return }
            
            let now = Date()
            if let lastWarning = self.lastMemoryWarning,
               now.timeIntervalSince(lastWarning) < self.memoryWarningCooldown {
                return // Avoid spam
            }
            
            self.lastMemoryWarning = now
            self.handleError(.memoryPressureHigh)
        }
        
        memoryPressureSource?.resume()
    }
    
    /// Check system resources periodically
    private func checkSystemResources() {
        // Use MemoryManager for consistent memory monitoring
        let memoryUsage = MemoryManager.shared.getCurrentMemoryUsage()
        
        // Memory restrictions removed - allow unlimited memory usage for accurate calculations
        FlexaLog.motion.info("Memory usage: \(String(format: "%.1f", memoryUsage))MB - no restrictions applied")
        
        // Check if system health should be restored
        if systemHealth != .healthy && recoveryAttempts == 0 && currentError == nil {
            DispatchQueue.main.async {
                self.systemHealth = .healthy
            }
        }
    }
    
    // MARK: - Recovery Timeout
    
    private func startRecoveryTimeout() {
        recoveryTimer = Timer.scheduledTimer(withTimeInterval: recoveryTimeout, repeats: false) { [weak self] _ in
            self?.handleRecoveryTimeout()
        }
    }
    
    private func stopRecoveryTimeout() {
        recoveryTimer?.invalidate()
        recoveryTimer = nil
    }
    
    private func handleRecoveryTimeout() {
        FlexaLog.motion.error("Recovery timeout exceeded")
        
        DispatchQueue.main.async {
            self.isRecovering = false
        }
        
        if currentError != nil {
            handleError(.criticalSystemError(NSError(domain: "ROMErrorHandler", code: -1, userInfo: [NSLocalizedDescriptionKey: "Recovery timeout"])))
        }
    }
    
    // MARK: - Session Management
    
    /// Reset error handler for new session
    func resetForNewSession() {
        DispatchQueue.main.async {
            self.currentError = nil
            self.isRecovering = false
            self.recoveryAttempts = 0
            self.systemHealth = .healthy
            self.lastRecoveryTime = nil
        }
        
        stopRecoveryTimeout()
        FlexaLog.motion.info("Error handler reset for new session")
    }
    
    /// Check if system is ready for new session
    func isSystemReady() -> Bool {
        return systemHealth != .failed && !isRecovering
    }
    
    /// Get system status summary
    func getSystemStatus() -> (health: SystemHealth, errorCount: Int, lastError: ROMError?) {
        return (systemHealth, errorHistory.count, errorHistory.last)
    }
    
    // MARK: - Cleanup
    
    private func cleanup() {
        resourceMonitorTimer?.invalidate()
        resourceMonitorTimer = nil
        
        recoveryTimer?.invalidate()
        recoveryTimer = nil
        
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
        
        onRecoveryRequired = nil
        onSystemHealthChanged = nil
        onCriticalError = nil
    }
}

// MARK: - SystemHealth Raw Value Extension

extension ROMErrorHandler.SystemHealth: Comparable {
    var rawValue: Int {
        switch self {
        case .healthy: return 0
        case .degraded: return 1
        case .critical: return 2
        case .failed: return 3
        }
    }
    
    static func < (lhs: ROMErrorHandler.SystemHealth, rhs: ROMErrorHandler.SystemHealth) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

// MARK: - ARCamera.TrackingState.Reason Extension

extension ARCamera.TrackingState.Reason {
    var localizedDescription: String {
        switch self {
        case .excessiveMotion:
            return "Excessive motion detected"
        case .insufficientFeatures:
            return "Insufficient visual features"
        case .initializing:
            return "ARKit initializing"
        case .relocalizing:
            return "ARKit relocalizing"
        @unknown default:
            return "Unknown tracking issue"
        }
    }
}