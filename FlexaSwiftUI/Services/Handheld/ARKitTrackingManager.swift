//
//
//  ARKitTrackingManager.swift
//  FlexaSwiftUI
//
//  ARKit tracking with anchor fallback system
//  Priority: World Tracking → Face Tracking → Object Tracking
//

import Foundation
import ARKit
import Combine

/// Manages ARKit tracking with automatic fallback between tracking modes
final class ARKitTrackingManager: NSObject, ObservableObject {
    
    // MARK: - Tracking Modes
    
    enum TrackingMode: String {
        case worldTracking = "World Tracking"
        case faceTracking = "Face Tracking"
        case objectTracking = "Object Tracking"
        case unavailable = "Unavailable"
    }
    
    enum AnchorType {
        case world
        case face
        case object
        case none
    }
    
    // MARK: - Published State
    
    @Published private(set) var currentMode: TrackingMode = .unavailable
    @Published private(set) var currentAnchorType: AnchorType = .none
    @Published private(set) var isTracking: Bool = false
    @Published private(set) var trackingQuality: ARCamera.TrackingState = .notAvailable
    
    // MARK: - Private Properties
    
    private let session = ARSession()
    private var currentConfiguration: ARConfiguration?
    
    // Callbacks
    var onTransformUpdate: ((simd_float4x4, TimeInterval) -> Void)?
    var onTrackingLost: (() -> Void)?
    var onTrackingRecovered: (() -> Void)?
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        session.delegate = self
    }
    
    // MARK: - Public API
    
    /// Start tracking with automatic mode selection
    func startTracking() {
        let mode = selectBestTrackingMode()
        startTracking(mode: mode)
    }
    
    /// Start tracking with specific mode
    func startTracking(mode: TrackingMode) {
        guard let configuration = createConfiguration(for: mode) else {
            FlexaLog.motion.error("❌ [ARKit] Failed to create configuration for \(mode.rawValue)")
            currentMode = .unavailable
            return
        }
        
        currentConfiguration = configuration
        currentMode = mode
        
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        isTracking = true
        
        FlexaLog.motion.info("✅ [ARKit] Started tracking: \(mode.rawValue)")
    }
    
    /// Stop tracking
    func stopTracking() {
        session.pause()
        isTracking = false
        currentMode = .unavailable
        currentAnchorType = .none
        
        FlexaLog.motion.info("⏸️ [ARKit] Stopped tracking")
    }
    
    /// Attempt to recover tracking by falling back to next available mode
    func attemptRecovery() {
        FlexaLog.motion.warning("🔄 [ARKit] Attempting tracking recovery...")
        
        // Try next fallback mode
        let nextMode = getNextFallbackMode(from: currentMode)
        if nextMode != .unavailable {
            startTracking(mode: nextMode)
        } else {
            FlexaLog.motion.error("❌ [ARKit] No fallback modes available")
            onTrackingLost?()
        }
    }
    
    // MARK: - Mode Selection
    
    /// Select best available tracking mode based on device capabilities
    private func selectBestTrackingMode() -> TrackingMode {
        // Priority 1: World Tracking (most accurate for handheld games)
        if ARWorldTrackingConfiguration.isSupported {
            return .worldTracking
        }
        
        // Priority 2: Face Tracking (fallback for devices without world tracking)
        if ARFaceTrackingConfiguration.isSupported {
            return .faceTracking
        }
        
        // Priority 3: Object Tracking (last resort)
        if ARObjectScanningConfiguration.isSupported {
            return .objectTracking
        }
        
        return .unavailable
    }
    
    /// Get next fallback mode if current mode fails
    private func getNextFallbackMode(from currentMode: TrackingMode) -> TrackingMode {
        switch currentMode {
        case .worldTracking:
            // Fallback to face tracking
            if ARFaceTrackingConfiguration.isSupported {
                return .faceTracking
            }
            fallthrough
            
        case .faceTracking:
            // Fallback to object tracking
            if ARObjectScanningConfiguration.isSupported {
                return .objectTracking
            }
            fallthrough
            
        case .objectTracking, .unavailable:
            return .unavailable
        }
    }
    
    // MARK: - Configuration Creation
    
    private func createConfiguration(for mode: TrackingMode) -> ARConfiguration? {
        switch mode {
        case .worldTracking:
            return createWorldTrackingConfiguration()
            
        case .faceTracking:
            return createFaceTrackingConfiguration()
            
        case .objectTracking:
            return createObjectTrackingConfiguration()
            
        case .unavailable:
            return nil
        }
    }
    
    private func createWorldTrackingConfiguration() -> ARWorldTrackingConfiguration? {
        guard ARWorldTrackingConfiguration.isSupported else { return nil }
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.planeDetection = [.horizontal, .vertical]
        
        // Enable additional features if available
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }
        
        currentAnchorType = .world
        return configuration
    }
    
    private func createFaceTrackingConfiguration() -> ARFaceTrackingConfiguration? {
        guard ARFaceTrackingConfiguration.isSupported else { return nil }
        
        let configuration = ARFaceTrackingConfiguration()
        configuration.worldAlignment = .gravity
        
        currentAnchorType = .face
        return configuration
    }
    
    private func createObjectTrackingConfiguration() -> ARObjectScanningConfiguration? {
        guard ARObjectScanningConfiguration.isSupported else { return nil }
        
        let configuration = ARObjectScanningConfiguration()
        
        currentAnchorType = .object
        return configuration
    }
    
    // MARK: - Anchor Management
    
    /// Add anchor based on current tracking mode
    func addAnchor(at transform: simd_float4x4) {
        let anchor: ARAnchor
        
        switch currentAnchorType {
        case .world:
            anchor = ARAnchor(transform: transform)
            
        case .face:
            // Face anchors are automatically added by ARKit
            return
            
        case .object:
            anchor = ARAnchor(transform: transform)
            
        case .none:
            FlexaLog.motion.warning("⚠️ [ARKit] Cannot add anchor - no tracking mode active")
            return
        }
        
        session.add(anchor: anchor)
        FlexaLog.motion.debug("📍 [ARKit] Added \(String(describing: self.currentAnchorType)) anchor")
    }
    
    /// Get current camera transform
    func getCurrentTransform() -> simd_float4x4? {
        return session.currentFrame?.camera.transform
    }
    
    // MARK: - Tracking Quality
    
    private func updateTrackingQuality(_ state: ARCamera.TrackingState) {
        trackingQuality = state
        
        switch state {
        case .normal:
            if !isTracking {
                isTracking = true
                onTrackingRecovered?()
                FlexaLog.motion.info("✅ [ARKit] Tracking recovered")
            }
            
        case .limited(let reason):
            FlexaLog.motion.warning("⚠️ [ARKit] Tracking limited: \(reason.trackingReasonDescription)")
            
        case .notAvailable:
            if isTracking {
                isTracking = false
                FlexaLog.motion.error("❌ [ARKit] Tracking lost")
                attemptRecovery()
            }
        }
    }
}

// MARK: - ARSessionDelegate

extension ARKitTrackingManager: ARSessionDelegate {
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Update tracking quality
        updateTrackingQuality(frame.camera.trackingState)
        
        // Provide transform updates
        let transform = frame.camera.transform
        let timestamp = frame.timestamp
        onTransformUpdate?(transform, timestamp)
    }
    
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            if anchor is ARFaceAnchor {
                FlexaLog.motion.debug("📍 [ARKit] Face anchor added")
            } else {
                FlexaLog.motion.debug("📍 [ARKit] Anchor added: \(type(of: anchor))")
            }
        }
    }
    
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        // Anchors updated - tracking is working
    }
    
    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        FlexaLog.motion.debug("📍 [ARKit] Anchor removed")
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        FlexaLog.motion.error("❌ [ARKit] Session failed: \(error.localizedDescription)")
        attemptRecovery()
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        FlexaLog.motion.warning("⚠️ [ARKit] Session interrupted")
        isTracking = false
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        FlexaLog.motion.info("✅ [ARKit] Session interruption ended")
        // Restart with current mode
        if let config = currentConfiguration {
            session.run(config, options: [.resetTracking])
        }
    }
}

// MARK: - Tracking State Extension

// Avoid declaring conformance of imported types to protocols to prevent
// future ABI/behavioral changes if ARKit later adds these conformances.
// Provide safe computed properties for debugging instead.
extension ARCamera.TrackingState {
    var trackingStateDescription: String {
        switch self {
        case .normal:
            return "Normal"
        case .limited(let reason):
            return "Limited: \(reason.trackingReasonDescription)"
        case .notAvailable:
            return "Not Available"
        }
    }
}

extension ARCamera.TrackingState.Reason {
    var trackingReasonDescription: String {
        switch self {
        case .initializing:
            return "Initializing"
        case .excessiveMotion:
            return "Excessive Motion"
        case .insufficientFeatures:
            return "Insufficient Features"
        case .relocalizing:
            return "Relocalizing"
        @unknown default:
            return "Unknown"
        }
    }
}
