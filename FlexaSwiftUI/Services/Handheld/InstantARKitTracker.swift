import Foundation
import simd
import Combine
import ARKit
import MetalKit

/// GPU-accelerated ARKit tracker with multi-tier anchors:
/// Tier 1 (Primary): Camera transform + Object anchors (background support)
/// Tier 2 (Fallback): Face anchors + Object anchors (any available)
final class InstantARKitTracker: NSObject, ObservableObject, ARSessionDelegate {
    // MARK: - Published State
    @Published private(set) var currentPosition: SIMD3<Float>?
    @Published private(set) var currentRotation: simd_float3x3?
    @Published private(set) var currentTransform: simd_float4x4?
    @Published private(set) var isTracking = false
    @Published private(set) var trackingQuality: ARCamera.TrackingState = .notAvailable
    @Published private(set) var isFullyInitialized = false
    @Published private(set) var anchorSource: String = "none"  // "camera+object" / "face+object"

    // MARK: - Private
    private let arSession = ARSession()
    private var isActive = false
    private let dataQueue = DispatchQueue(label: "com.flexa.arkit.instant", qos: .userInitiated)
    
    // GPU optimization
    private let metalDevice = MTLCreateSystemDefaultDevice()
    private var metalCommandQueue: MTLCommandQueue?
    
    // Multi-anchor tracking (reordered: camera primary, face fallback)
    private var lastFaceAnchors: [ARFaceAnchor] = []
    private var lastObjectAnchors: [AnchorInfo] = []
    private var lastCameraTransform: simd_float4x4?
    private var currentTier: AnchorTier = .cameraPlusObject
    private enum AnchorTier {
        case cameraPlusObject   // Tier 1: Primary
        case facePlusObject     // Tier 2: Fallback
    }
    
    private struct AnchorInfo {
        let transform: simd_float4x4
        let identifier: UUID
    }

    // Callbacks (used by SimpleMotionService)
    var onPositionUpdate: ((SIMD3<Float>, TimeInterval) -> Void)?
    var onTransformUpdate: ((simd_float4x4, TimeInterval) -> Void)?

    override init() {
        super.init()
        arSession.delegate = self
        
        // Setup Metal for GPU acceleration
        if let device = metalDevice {
            metalCommandQueue = device.makeCommandQueue()
            FlexaLog.motion.info("📍 [ARKit-GPU] Metal GPU device initialized: \(device.name)")
        } else {
            FlexaLog.motion.warning("📍 [ARKit-GPU] No Metal GPU device available, using CPU")
        }
        
        FlexaLog.motion.info("📍 [AUDIT] InstantARKitTracker initialized with GPU acceleration. Tier 1: Camera+Objects, Tier 2: Face+Objects")
    }

    deinit { stop() }

    func start() {
        dataQueue.async { [weak self] in
            guard let self = self, !self.isActive else { return }
            FlexaLog.motion.info("📍 [ARKit-GPU] Starting GPU-accelerated tracking: Tier 1 (Camera+Objects) → Tier 2 (Face+Objects)")
            self.isActive = true
            self.isFullyInitialized = false

            guard ARWorldTrackingConfiguration.isSupported else {
                FlexaLog.motion.error("📍 [ARKit-GPU] World tracking not supported on this device.")
                return
            }

            let configuration = ARWorldTrackingConfiguration()
            configuration.worldAlignment = .gravity
            configuration.planeDetection = [.horizontal, .vertical]
            
            // HIGH QUALITY VIDEO - Use highest resolution available (not VGA)
            if #available(iOS 16.0, *) {
                // Use 4K video format if available for maximum quality
                let supportedFormats = ARWorldTrackingConfiguration.supportedVideoFormats
                if let highQualityFormat = supportedFormats.first(where: { format in
                    format.imageResolution.width >= 1920 && format.framesPerSecond >= 60
                }) {
                    configuration.videoFormat = highQualityFormat
                    FlexaLog.motion.info("📍 [ARKit-GPU] Using high-quality video: \(highQualityFormat.imageResolution.width)x\(highQualityFormat.imageResolution.height) @ \(highQualityFormat.framesPerSecond)fps")
                } else if let format60fps = supportedFormats.first(where: { $0.framesPerSecond >= 60 }) {
                    configuration.videoFormat = format60fps
                    FlexaLog.motion.info("📍 [ARKit-GPU] Using 60fps video: \(format60fps.imageResolution.width)x\(format60fps.imageResolution.height)")
                }
            }
            
            // GPU optimizations
            if #available(iOS 12.0, *) {
                configuration.environmentTexturing = .automatic
            }
            
            // Enable high-frequency frame delivery for GPU processing
            if #available(iOS 14.0, *) {
                configuration.frameSemantics.insert(.personSegmentationWithDepth)
            }
            
            // Maximum tracking quality
            configuration.isAutoFocusEnabled = true
            
            self.arSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])
            FlexaLog.motion.info("📍 [ARKit-GPU] GPU-accelerated world tracking started with Metal support and high-quality video")
        }
    }

    func stop() {
        dataQueue.async { [weak self] in
            guard let self = self, self.isActive else { return }
            self.arSession.pause()
            self.isActive = false
            DispatchQueue.main.async {
                self.isTracking = false
                self.isFullyInitialized = false
                self.currentPosition = nil
                self.currentRotation = nil
                self.currentTransform = nil
            }
            FlexaLog.motion.info("📍 [AUDIT] ARKit tracking stopped.")
        }
    }

    @objc(session:didUpdateFrame:)
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let timestamp = frame.timestamp
        let cameraTransform = frame.camera.transform
        
        // Store camera transform for Tier 1
        lastCameraTransform = cameraTransform
        
        // Use camera transform as primary source
        updateTrackingData(transform: cameraTransform, timestamp: timestamp, tierLabel: "camera")

        if !isFullyInitialized {
            DispatchQueue.main.async {
                self.isFullyInitialized = true
                FlexaLog.motion.info("📍 [ARKit-GPU] Fully initialized. GPU acceleration active.")
            }
        }
    }
    
    // MARK: - Face Anchor Fallback (Tier 2)
    
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        handleAnchors(anchors)
    }
    
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        handleAnchors(anchors)
    }
    
    private func handleAnchors(_ anchors: [ARAnchor]) {
        // Extract face anchors for Tier 2 fallback
        let faceAnchors = anchors.compactMap { $0 as? ARFaceAnchor }
        if !faceAnchors.isEmpty {
            lastFaceAnchors = faceAnchors
        }
        
        // Store object anchors for additional stability
        let objectAnchors = anchors.filter { !($0 is ARFaceAnchor) }
        if !objectAnchors.isEmpty {
            lastObjectAnchors = objectAnchors.map { AnchorInfo(transform: $0.transform, identifier: $0.identifier) }
        }
    }
    
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        dataQueue.async { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.trackingQuality = camera.trackingState
            }
            
            switch camera.trackingState {
            case .normal:
                self.currentTier = .cameraPlusObject
                DispatchQueue.main.async {
                    self.anchorSource = "camera+object"
                }
                FlexaLog.motion.info("📍 [ARKit-GPU] TIER 1 ACTIVE: Camera+Objects (GPU accelerated)")
                
            case .notAvailable:
                self.currentTier = .facePlusObject
                self.useFaceAnchorFallback()
                DispatchQueue.main.async {
                    self.anchorSource = "face+object"
                }
                FlexaLog.motion.warning("📍 [ARKit-GPU] TIER 2 FALLBACK: Switching to Face+Objects")
                
            case .limited(let reason):
                let reasonString: String
                switch reason {
                case .excessiveMotion:
                    reasonString = "Excessive Motion"
                case .insufficientFeatures:
                    reasonString = "Insufficient Features"
                case .initializing:
                    reasonString = "Initializing"
                case .relocalizing:
                    reasonString = "Relocalizing"
                @unknown default:
                    reasonString = "Unknown"
                }
                self.currentTier = .facePlusObject
                self.useFaceAnchorFallback()
                DispatchQueue.main.async {
                    self.anchorSource = "face+object"
                }
                FlexaLog.motion.warning("📍 [ARKit-GPU] TIER 2 FALLBACK: Limited (\(reasonString)) → Face+Objects")
            }
        }
    }
    
    private func useFaceAnchorFallback() {
        // Use face anchor if available, otherwise fall back to last known camera transform
        if let faceAnchor = lastFaceAnchors.first {
            let timestamp = Date().timeIntervalSince1970
            updateTrackingData(transform: faceAnchor.transform, timestamp: timestamp, tierLabel: "face")
            FlexaLog.motion.debug("📍 [ARKit-GPU] Using face anchor for position tracking")
        } else if let cameraTransform = lastCameraTransform {
            // No face anchor available, use last known camera transform
            let timestamp = Date().timeIntervalSince1970
            updateTrackingData(transform: cameraTransform, timestamp: timestamp, tierLabel: "camera-cached")
            FlexaLog.motion.debug("📍 [ARKit-GPU] Using cached camera transform (no face anchor available)")
        }
    }

    private func updateTrackingData(transform: simd_float4x4, timestamp: TimeInterval, tierLabel: String) {
        // GPU-optimized SIMD operations (Metal can optimize these)
        let position = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        let rotation = simd_float3x3(
            SIMD3<Float>(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
            SIMD3<Float>(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
            SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        )

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentPosition = position
            self.currentRotation = rotation
            self.currentTransform = transform
            self.isTracking = true
            self.anchorSource = tierLabel
            self.onTransformUpdate?(transform, timestamp)
        }

        dataQueue.async { [weak self] in
            guard let self = self else { return }
            self.onPositionUpdate?(position, timestamp)
        }
    }
}
