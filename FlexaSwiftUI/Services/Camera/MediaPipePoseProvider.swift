import AVFoundation
import UIKit
import MediaPipeTasksVision
import Combine
import simd

/// High-performance pose detection using Google MediaPipe BlazePose model
/// Replaces Apple Vision with more robust tracking and lower confidence thresholds
class MediaPipePoseProvider: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    @Published var currentKeypoints: SimplifiedPoseKeypoints?
    @Published var rawConfidence: Float = 0.0
    
    // Callback matching VisionPoseProvider interface
    var onPoseDetected: ((SimplifiedPoseKeypoints) -> Void)?
    var onCameraResolutionChanged: ((CGSize) -> Void)?
    
    // MARK: - Private Properties
    private var poseLandmarker: PoseLandmarker?
    private let processingQueue = DispatchQueue(label: "com.flexa.mediapipe.processing", qos: .userInteractive)
    private var lastProcessedTime: TimeInterval = 0
    private let minimumFrameInterval: TimeInterval = 1.0 / 30.0 // 30 FPS max
    private var started = false
    private var frameCount = 0

    private struct FrameState {
        var size: CGSize
        var isFrontCamera: Bool
        var orientation: UIImage.Orientation
    }

    private var frameState = FrameState(
        size: CGSize(width: 720, height: 1280),
        isFrontCamera: true,
        orientation: .leftMirrored
    )
    private let frameStateQueue = DispatchQueue(label: "com.flexa.mediapipe.frameState", qos: .userInteractive)
    
    // Error handling (matches VisionPoseProvider)
    private var errorHandler: ROMErrorHandler?
    private var consecutiveFailures: Int = 0
    private let maxConsecutiveFailures = 10
    private var lastSuccessfulDetection: Date?
    
    // Model configuration - Using FULL model for maximum accuracy
    private let modelName = "pose_landmarker_full" // Full model for better accuracy vs lite
    private let minDetectionConfidence: Float = 0.3  // Lowered from Vision's defaults
    private let minPresenceConfidence: Float = 0.3   // Lowered to handle tilted poses
    private let minTrackingConfidence: Float = 0.3   // Lowered for continuous tracking
    
    // MARK: - Initialization
    override init() {
        super.init()
        setupPoseLandmarker()
    }
    
    private func setupPoseLandmarker() {
        guard let modelPath = Bundle.main.path(forResource: modelName, ofType: "task") else {
            FlexaLog.vision.error("MediaPipe model file not found: \(self.modelName).task")
            FlexaLog.vision.info("Download from: https://developers.google.com/mediapipe/solutions/vision/pose_landmarker#models")
            return
        }
        
        do {
            let options = PoseLandmarkerOptions()
            options.baseOptions.modelAssetPath = modelPath
            options.runningMode = .liveStream
            options.numPoses = 1
            options.minPoseDetectionConfidence = minDetectionConfidence
            options.minPosePresenceConfidence = minPresenceConfidence
            options.minTrackingConfidence = minTrackingConfidence
            
            // Set up async result callback
            options.poseLandmarkerLiveStreamDelegate = self
            
            poseLandmarker = try PoseLandmarker(options: options)
            FlexaLog.vision.info("MediaPipe BlazePose initialized successfully with lowered confidence thresholds")
        } catch {
            FlexaLog.vision.error("Failed to initialize MediaPipe PoseLandmarker: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Public API (Matching VisionPoseProvider Interface)
    
    /// Set error handler for recovery support
    func setErrorHandler(_ handler: ROMErrorHandler) {
        self.errorHandler = handler
    }

    func configureCamera(position: AVCaptureDevice.Position) {
        frameStateQueue.async {
            self.frameState.isFrontCamera = (position == .front)
            self.frameState.orientation = (position == .front) ? .leftMirrored : .right
        }
    }
    
    func start() {
        FlexaLog.vision.info("🔥 [MEDIAPIPE] Starting pose tracking with BlazePose")
        started = true
    }
    
    func stop() {
        FlexaLog.vision.info("🔥 [MEDIAPIPE] Stopping pose tracking")
        started = false
    }
    
    // Aliases for compatibility
    func startPoseTracking() { start() }
    func stopPoseTracking() { stop() }
    
    /// Process a camera frame for pose detection (main entry point from SimpleMotionService)
    /// - Parameter sampleBuffer: CMSampleBuffer from AVCaptureVideoDataOutput
    func processFrame(_ sampleBuffer: CMSampleBuffer) {
        frameCount += 1
        
        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            let newSize = CGSize(width: CGFloat(width), height: CGFloat(height))
            frameStateQueue.async {
                if self.frameState.size != newSize {
                    self.frameState.size = newSize
                    DispatchQueue.main.async {
                        self.onCameraResolutionChanged?(newSize)
                    }
                }
            }
        }

        guard started else {
            if frameCount % 30 == 0 {
                FlexaLog.vision.warning("🔥 [MEDIAPIPE] Frame #\(self.frameCount) received but not started")
            }
            return
        }
        
        guard let poseLandmarker = poseLandmarker else {
            handleError("PoseLandmarker not initialized")
            return
        }
        
        // Throttle to 30 FPS
        let currentTime = CACurrentMediaTime()
        guard currentTime - lastProcessedTime >= minimumFrameInterval else { return }
        lastProcessedTime = currentTime
        
        if frameCount % 30 == 0 {
            FlexaLog.vision.info("🔥 [MEDIAPIPE] Processing frame #\(self.frameCount) - Started: \(self.started)")
        }
        
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                // Convert CMSampleBuffer to high-quality MPImage
                // Front camera portrait: use .up orientation for MediaPipe
                let orientation = self.frameStateQueue.sync { self.frameState.orientation }
                let mpImage = try self.createHighQualityMPImage(from: sampleBuffer, orientation: orientation)
                
                // Get timestamp in milliseconds
                let timestampMs = Int(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * 1000)
                
                // Process async (results come via delegate)
                try poseLandmarker.detectAsync(image: mpImage, timestampInMilliseconds: timestampMs)
                
                // Reset failure count on successful processing
                self.consecutiveFailures = 0
                
            } catch {
                self.handleError("Frame processing failed: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Error Handling
    
    private func handleError(_ message: String) {
        FlexaLog.vision.error("🔥 [MEDIAPIPE] \(message)")
        consecutiveFailures += 1
        
        if consecutiveFailures >= maxConsecutiveFailures {
            FlexaLog.vision.error("🔥 [MEDIAPIPE] Max consecutive failures reached (\(self.maxConsecutiveFailures))")
            errorHandler?.handleError(.visionPoseNotDetected)
        }
    }
    
    // MARK: - Image Preprocessing
    
    /// Create high-quality MPImage with preprocessing to maximize BlazePose accuracy
    private func createHighQualityMPImage(from sampleBuffer: CMSampleBuffer, orientation: UIImage.Orientation) throws -> MPImage {
        // Extract pixel buffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw NSError(domain: "MediaPipePoseProvider", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get pixel buffer"])
        }
        
        // Apply preprocessing for better detection:
        // 1. Ensure proper color space
        // 2. Maintain aspect ratio
        // 3. Apply brightness normalization if needed
        
        // Optional: Apply brightness/contrast adjustment for low-light scenarios
        // Uncomment if front camera struggles in dim lighting
        // let adjustedImage = ciImage.applyingFilter("CIColorControls", parameters: [
        //     "inputBrightness": 0.1,
        //     "inputContrast": 1.1
        // ])
        
        // Convert back to CVPixelBuffer with optimal format
        let adjustedPixelBuffer = pixelBuffer // or create new buffer from adjustedImage
        
        // Create MPImage with orientation correction
        let mpImage = try MPImage(pixelBuffer: adjustedPixelBuffer, orientation: orientation)
        
        return mpImage
    }
    
    // MARK: - MediaPipe to SimplifiedPoseKeypoints Conversion
    
    /// Convert MediaPipe's 33-point model to FlexaSwiftUI's SimplifiedPoseKeypoints
    private func convertToSimplifiedKeypoints(_ result: PoseLandmarkerResult, timestamp: TimeInterval) -> SimplifiedPoseKeypoints? {
        guard let landmarks = result.landmarks.first else {
            FlexaLog.vision.warning("🏴 [LANDMARK-DEBUG] No landmarks detected in result")
            return nil
        }
        
        // MediaPipe landmark indices:
        // 0: nose, 11: left shoulder, 12: right shoulder
        // 13: left elbow, 14: right elbow, 15: left wrist, 16: right wrist
        // 23: left hip, 24: right hip
        
        let nose = landmarks[0]
        let leftShoulder = landmarks[11]
        let rightShoulder = landmarks[12]
        let leftElbow = landmarks[13]
        let rightElbow = landmarks[14]
        let leftWrist = landmarks[15]
        let rightWrist = landmarks[16]
        let leftHip = landmarks[23]
        let rightHip = landmarks[24]
        let leftEye = landmarks[2]
        let rightEye = landmarks[5]

        // Log raw landmarks for debugging coordinate issues
        FlexaLog.vision.debug("🏴 [LANDMARK-RAW] Nose: (\(String(format: "%.4f", nose.x)), \(String(format: "%.4f", nose.y))) | LeftWrist: (\(String(format: "%.4f", leftWrist.x)), \(String(format: "%.4f", leftWrist.y))) | RightWrist: (\(String(format: "%.4f", rightWrist.x)), \(String(format: "%.4f", rightWrist.y)))")

        let leftWristPoint = getNormalizedMirroredPoint(leftWrist, label: "LeftWrist")
        let rightWristPoint = getNormalizedMirroredPoint(rightWrist, label: "RightWrist")
        let leftElbowPoint = getNormalizedMirroredPoint(leftElbow, label: "LeftElbow")
        let rightElbowPoint = getNormalizedMirroredPoint(rightElbow, label: "RightElbow")
        let leftShoulderPoint = getNormalizedMirroredPoint(leftShoulder, label: "LeftShoulder")
        let rightShoulderPoint = getNormalizedMirroredPoint(rightShoulder, label: "RightShoulder")
        let nosePoint = getNormalizedMirroredPoint(nose, label: "Nose")
        let leftHipPoint = getNormalizedMirroredPoint(leftHip, label: "LeftHip")
        let rightHipPoint = getNormalizedMirroredPoint(rightHip, label: "RightHip")
        let leftEyePoint = getNormalizedMirroredPoint(leftEye, label: "LeftEye")
        let rightEyePoint = getNormalizedMirroredPoint(rightEye, label: "RightEye")

        let neckPoint: CGPoint? = {
            return CGPoint(
                x: (leftShoulderPoint.x + rightShoulderPoint.x) / 2.0,
                y: (leftShoulderPoint.y + rightShoulderPoint.y) / 2.0
            )
        }()

        func confidenceValue(_ number: NSNumber?) -> Float {
            guard let value = number?.floatValue else { return 0.0 }
            return max(0.0, min(1.0, value))
        }

        let confidenceSum = landmarks.reduce(Float(0)) { partial, landmark in
            let visibility = confidenceValue(landmark.visibility)
            let presence = confidenceValue(landmark.presence)
            let combined = (visibility + presence) / 2.0
            return partial + combined
        }
        let avgConfidence = landmarks.isEmpty ? Float(0) : confidenceSum / Float(landmarks.count)

        let leftShoulderConfidence = confidenceValue(leftShoulder.visibility)
        let rightShoulderConfidence = confidenceValue(rightShoulder.visibility)
        let leftElbowConfidence = confidenceValue(leftElbow.visibility)
        let rightElbowConfidence = confidenceValue(rightElbow.visibility)
        let leftWristConfidence = confidenceValue(leftWrist.visibility)
        let rightWristConfidence = confidenceValue(rightWrist.visibility)
        let noseConfidence = confidenceValue(nose.visibility)

        DispatchQueue.main.async {
            self.rawConfidence = avgConfidence
        }

        return SimplifiedPoseKeypoints(
            timestamp: timestamp,
            leftWrist: leftWristPoint,
            rightWrist: rightWristPoint,
            leftElbow: leftElbowPoint,
            rightElbow: rightElbowPoint,
            leftShoulder: leftShoulderPoint,
            rightShoulder: rightShoulderPoint,
            nose: nosePoint,
            neck: neckPoint,
            leftHip: leftHipPoint,
            rightHip: rightHipPoint,
            leftEye: leftEyePoint,
            rightEye: rightEyePoint,
            leftShoulder3D: simd_float3(leftShoulder.x, leftShoulder.y, leftShoulder.z),
            rightShoulder3D: simd_float3(rightShoulder.x, rightShoulder.y, rightShoulder.z),
            leftElbow3D: simd_float3(leftElbow.x, leftElbow.y, leftElbow.z),
            rightElbow3D: simd_float3(rightElbow.x, rightElbow.y, rightElbow.z),
            leftShoulderConfidence: leftShoulderConfidence,
            rightShoulderConfidence: rightShoulderConfidence,
            leftElbowConfidence: leftElbowConfidence,
            rightElbowConfidence: rightElbowConfidence,
            leftWristConfidence: leftWristConfidence,
            rightWristConfidence: rightWristConfidence,
            noseConfidence: noseConfidence,
            neckConfidence: (leftShoulderConfidence + rightShoulderConfidence) / 2.0
        )
    }

    private func getNormalizedMirroredPoint(_ landmark: NormalizedLandmark, label: String = "") -> CGPoint {
        let state = frameStateQueue.sync { frameState }
        let isFront = state.isFrontCamera

        // Clamp to 0-1 range (MediaPipe sometimes returns out-of-bounds values)
        let rawX = max(0, min(1, CGFloat(landmark.x)))
        let rawY = max(0, min(1, CGFloat(landmark.y)))
        
        let originalX = rawX
        
        // Mirror X for front camera
        var normalizedX = rawX
        if isFront {
            normalizedX = 1.0 - normalizedX
        }

        let result = CGPoint(x: normalizedX, y: rawY)
        
        // Log landmark transformation
        if !label.isEmpty {
            FlexaLog.vision.debug("🏴 [LANDMARK-NORM] \(label): RAW(\(String(format: "%.4f", originalX)), \(String(format: "%.4f", rawY))) -> NORM(\(String(format: "%.4f", normalizedX)), \(String(format: "%.4f", result.y))) [Front: \(isFront)]")
        }
        
        return result
    }

    deinit {
        stop()
        onPoseDetected = nil
        FlexaLog.vision.info("MediaPipePoseProvider deinitializing and cleaning up resources")
    }
}

// MARK: - PoseLandmarkerLiveStreamDelegate

extension MediaPipePoseProvider: PoseLandmarkerLiveStreamDelegate {
    func poseLandmarker(
        _ poseLandmarker: PoseLandmarker,
        didFinishDetection result: PoseLandmarkerResult?,
        timestampInMilliseconds: Int,
        error: Error?
    ) {
        if let error = error {
            FlexaLog.vision.error("MediaPipe detection error: \(error.localizedDescription)")
            return
        }
        
        guard let result = result else {
            return
        }
        
        // Convert and publish keypoints on main thread
        if let keypoints = convertToSimplifiedKeypoints(result, timestamp: TimeInterval(timestampInMilliseconds) / 1000.0) {
            self.lastSuccessfulDetection = Date()
            self.consecutiveFailures = 0
            
            // Log final keypoints for debugging
            if let rightWrist = keypoints.rightWrist {
                FlexaLog.vision.debug("🏴 [LANDMARK-FINAL] RightWrist: (\(String(format: "%.4f", rightWrist.x)), \(String(format: "%.4f", rightWrist.y)))")
            }
            if let leftWrist = keypoints.leftWrist {
                FlexaLog.vision.debug("🏴 [LANDMARK-FINAL] LeftWrist: (\(String(format: "%.4f", leftWrist.x)), \(String(format: "%.4f", leftWrist.y)))")
            }
            
            DispatchQueue.main.async {
                self.currentKeypoints = keypoints
                // Call the callback (matches VisionPoseProvider behavior)
                self.onPoseDetected?(keypoints)
            }
        }
    }
}
