import AVFoundation
import Foundation
import MediaPipeTasksVision
import UIKit

/// MediaPipe Pose Landmarker provider for GPU-accelerated pose detection
/// Uses MediaPipe's latest Pose Landmarker full model with 33 landmarks
final class MediaPipePoseProvider: ObservableObject {
    private let queue = DispatchQueue(label: "com.flexa.mediapipe.pose", qos: .userInitiated)
    private var poseLandmarker: PoseLandmarker?
    private var started = false
    private var isProcessingFrame = false

    // Optional callback for push updates
    var onPoseDetected: ((SimplifiedPoseKeypoints) -> Void)?

    // Error handling
    private var errorHandler: ROMErrorHandler?
    private var consecutiveFailures: Int = 0
    private let maxConsecutiveFailures = 10
    private var lastSuccessfulDetection: Date?

    // Frame counting for debugging
    private var frameCount: Int = 0

    init() {
        setupPoseLandmarker()
    }

    deinit {
        stop()
        onPoseDetected = nil
        poseLandmarker = nil
        FlexaLog.vision.info("MediaPipePoseProvider deinitializing and cleaning up resources")
    }

    /// Set error handler for recovery support
    func setErrorHandler(_ handler: ROMErrorHandler) {
        self.errorHandler = handler
    }

    func start() {
        FlexaLog.vision.info("👁 [MEDIAPIPE] Starting pose tracking")
        started = true
    }

    func stop() {
        FlexaLog.vision.info("👁 [MEDIAPIPE] Stopping pose tracking")
        started = false
    }

    func startPoseTracking() { start() }
    func stopPoseTracking() { stop() }

    // MARK: - MediaPipe Setup

    private func setupPoseLandmarker() {
        do {
            // Locate the model file
            guard
                let modelPath = Bundle.main.path(
                    forResource: "pose_landmarker_full", ofType: "task")
            else {
                FlexaLog.vision.error(
                    "❌ [MEDIAPIPE] Model file 'pose_landmarker_full.task' not found in bundle")
                return
            }

            // Configure MediaPipe options with GPU acceleration
            let options = PoseLandmarkerOptions()
            options.baseOptions.modelAssetPath = modelPath

            // CRITICAL: Enable GPU delegate for maximum performance
            options.baseOptions.delegate = .GPU

            // Running mode for video stream processing
            options.runningMode = .video

            // Number of poses to detect (we only need 1 person)
            options.numPoses = 1

            // Confidence thresholds - optimized for real-time tracking
            // Lower thresholds = more detections but may be less stable
            // Higher thresholds = fewer detections but more accurate
            options.minPoseDetectionConfidence = 0.3  // Lower for better detection
            options.minPosePresenceConfidence = 0.3   // Lower for better detection
            options.minTrackingConfidence = 0.3       // Lower for smoother tracking

            // Create the pose landmarker
            poseLandmarker = try PoseLandmarker(options: options)

            FlexaLog.vision.info("✅ [MEDIAPIPE] Pose Landmarker initialized with GPU acceleration")
            FlexaLog.vision.info("✅ [MEDIAPIPE] Full model loaded from: \(modelPath)")

        } catch {
            FlexaLog.vision.error(
                "❌ [MEDIAPIPE] Failed to initialize: \(error.localizedDescription)")
            poseLandmarker = nil
        }
    }

    // MARK: - Frame Processing

    func processFrame(_ sampleBuffer: CMSampleBuffer) {
        frameCount += 1

        guard started else {
            return
        }

        guard poseLandmarker != nil else {
            return
        }

        // Drop frame if still processing previous one
        if isProcessingFrame {
            return
        }

        isProcessingFrame = true

        // Front camera in portrait mode
        // MediaPipe expects .up orientation for portrait front camera
        let orientation: UIImage.Orientation = .up

        process(
            sampleBuffer: sampleBuffer,
            orientation: orientation,
            cameraPosition: .front,
            isMirrored: true
        ) { [weak self] keypoints in
            guard let self = self else { return }

            if let keypoints = keypoints {
                self.onPoseDetected?(keypoints)
            }
        }
    }

    private func process(
        sampleBuffer: CMSampleBuffer,
        orientation: UIImage.Orientation,
        cameraPosition: AVCaptureDevice.Position,
        isMirrored: Bool,
        completion: @escaping (SimplifiedPoseKeypoints?) -> Void
    ) {
        guard started, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            DispatchQueue.main.async { [weak self] in
                self?.isProcessingFrame = false
                completion(nil)
            }
            return
        }

        guard let poseLandmarker = poseLandmarker else {
            DispatchQueue.main.async { [weak self] in
                self?.isProcessingFrame = false
                completion(nil)
            }
            return
        }

        queue.async { [weak self] in
            guard let self = self else { return }

            autoreleasepool {
                do {
                    // Convert CVPixelBuffer to MPImage
                    // Note: MPImage orientation is set at initialization, not after
                    let mpImage = try MPImage(pixelBuffer: pixelBuffer)

                    // Get timestamp in milliseconds
                    let timestamp = Int(
                        CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds * 1000)

                    // Detect pose using MediaPipe
                    let result = try poseLandmarker.detect(
                        videoFrame: mpImage, timestampInMilliseconds: timestamp)

                    // Convert to SimplifiedPoseKeypoints with world coordinates
                    if let keypoints = self.convertToSimplifiedKeypoints(
                        from: result, isMirrored: isMirrored, orientation: orientation)
                    {
                        self.handleSuccess()
                        
                        // Detailed logging every 30 frames (~0.5 second at 60fps)
                        if self.frameCount % 30 == 0 {
                            guard let landmarks = result.landmarks.first else {
                                FlexaLog.vision.debug("👁 [MEDIAPIPE] Frame \(self.frameCount) - No landmarks")
                                DispatchQueue.main.async {
                                    self.isProcessingFrame = false
                                    completion(keypoints)
                                }
                                return
                            }
                            
                            // Visibility scores
                            let leftWristVis = landmarks[15].visibility?.floatValue ?? 0
                            let rightWristVis = landmarks[16].visibility?.floatValue ?? 0
                            let leftElbowVis = landmarks[13].visibility?.floatValue ?? 0
                            let rightElbowVis = landmarks[14].visibility?.floatValue ?? 0
                            let leftShoulderVis = landmarks[11].visibility?.floatValue ?? 0
                            let rightShoulderVis = landmarks[12].visibility?.floatValue ?? 0
                            
                            // 2D normalized coordinates (0-1)
                            let leftWrist2D = landmarks[15]
                            let rightWrist2D = landmarks[16]
                            let leftElbow2D = landmarks[13]
                            let rightElbow2D = landmarks[14]
                            
                            FlexaLog.vision.info(
                                """
                                👁 [MEDIAPIPE] Frame \(self.frameCount)
                                📊 VISIBILITY:
                                  L-Wrist: \(String(format: "%.2f", leftWristVis)) | R-Wrist: \(String(format: "%.2f", rightWristVis))
                                  L-Elbow: \(String(format: "%.2f", leftElbowVis)) | R-Elbow: \(String(format: "%.2f", rightElbowVis))
                                  L-Shoulder: \(String(format: "%.2f", leftShoulderVis)) | R-Shoulder: \(String(format: "%.2f", rightShoulderVis))
                                📍 2D COORDS (normalized 0-1):
                                  L-Wrist: (\(String(format: "%.3f", leftWrist2D.x)), \(String(format: "%.3f", leftWrist2D.y)))
                                  R-Wrist: (\(String(format: "%.3f", rightWrist2D.x)), \(String(format: "%.3f", rightWrist2D.y)))
                                  L-Elbow: (\(String(format: "%.3f", leftElbow2D.x)), \(String(format: "%.3f", leftElbow2D.y)))
                                  R-Elbow: (\(String(format: "%.3f", rightElbow2D.x)), \(String(format: "%.3f", rightElbow2D.y)))
                                """
                            )
                        }
                        
                        DispatchQueue.main.async {
                            self.isProcessingFrame = false
                            completion(keypoints)
                        }
                    } else {
                        if self.consecutiveFailures < 5 {
                            self.handleFailure(reason: "No pose detected or insufficient landmarks")
                        }
                        DispatchQueue.main.async {
                            self.isProcessingFrame = false
                            completion(nil)
                        }
                    }

                } catch {
                    if self.consecutiveFailures < 5 {
                        self.handleFailure(reason: "MediaPipe Pose Landmarker error: \(error.localizedDescription)")
                    }
                    DispatchQueue.main.async {
                        self.isProcessingFrame = false
                        completion(nil)
                    }
                }
            }
        }
    }

    // MARK: - Landmark Conversion

    /// Convert MediaPipe Pose Landmarker results to SimplifiedPoseKeypoints
    /// MediaPipe Pose Landmarker provides 33 landmarks vs Vision's 17
    private func convertToSimplifiedKeypoints(
        from result: PoseLandmarkerResult,
        isMirrored: Bool,
        orientation: UIImage.Orientation
    ) -> SimplifiedPoseKeypoints? {
        guard let landmarks = result.landmarks.first else {
            return nil
        }

        // Ensure we have all required landmarks
        guard landmarks.count >= 33 else {
            return nil
        }

        // MediaPipe Pose Landmarker landmark indices (0-32)
        // See: https://developers.google.com/mediapipe/solutions/vision/pose_landmarker
        let nose = landmarks[0]
        let leftEye = landmarks[2]
        let rightEye = landmarks[5]
        let leftShoulder = landmarks[11]
        let rightShoulder = landmarks[12]
        let leftElbow = landmarks[13]
        let rightElbow = landmarks[14]
        let leftWrist = landmarks[15]
        let rightWrist = landmarks[16]
        let leftHip = landmarks[23]
        let rightHip = landmarks[24]

        // World landmarks for 3D coordinates (in meters, origin at hips)
        // Convert normalized landmarks (0-1) to CGPoint
        // MediaPipe returns coordinates in image space:
        // - X: 0 (left) to 1 (right) in the camera's view
        // - Y: 0 (top) to 1 (bottom) in the camera's view
        // For front camera with mirroring, flip X so user sees themselves correctly
        let convertPoint = { (landmark: NormalizedLandmark) -> CGPoint in
            // Mirror X for front camera (user's left appears on right side of screen)
            let x = isMirrored ? (1.0 - CGFloat(landmark.x)) : CGFloat(landmark.x)
            let y = CGFloat(landmark.y)
            return CGPoint(x: x, y: y)
        }

        // Build SimplifiedPoseKeypoints with timestamp and 3D data
        let timestamp = Date().timeIntervalSince1970

        // 🔥 TRUST MEDIAPIPE POSE LANDMARKER COMPLETELY - it's trained on diverse exercise data!
        // MediaPipe Pose Landmarker estimates landmarks even when occluded/out of frame
        // Use ALL landmarks regardless of visibility - the model knows what it's doing
        
        // CRITICAL: When mirroring for front camera, SWAP left/right landmarks!
        // MediaPipe sees your left arm on the right side of the image, then we mirror X,
        // but the landmark is still called "right" - so we need to swap the assignments
        let keypoints = SimplifiedPoseKeypoints(
            timestamp: timestamp,
            // SWAP left/right when mirrored so they match the user's actual body
            leftWrist: isMirrored ? convertPoint(rightWrist) : convertPoint(leftWrist),
            rightWrist: isMirrored ? convertPoint(leftWrist) : convertPoint(rightWrist),
            leftElbow: isMirrored ? convertPoint(rightElbow) : convertPoint(leftElbow),
            rightElbow: isMirrored ? convertPoint(leftElbow) : convertPoint(rightElbow),
            leftShoulder: isMirrored ? convertPoint(rightShoulder) : convertPoint(leftShoulder),
            rightShoulder: isMirrored ? convertPoint(leftShoulder) : convertPoint(rightShoulder),
            nose: convertPoint(nose),
            neck: nil,  // MediaPipe Pose Landmarker doesn't have explicit neck, can compute from shoulders
            leftHip: isMirrored ? convertPoint(rightHip) : convertPoint(leftHip),
            rightHip: isMirrored ? convertPoint(leftHip) : convertPoint(rightHip),
            leftEye: isMirrored ? convertPoint(rightEye) : convertPoint(leftEye),
            rightEye: isMirrored ? convertPoint(leftEye) : convertPoint(rightEye),
            // 2D-only pipeline: omit 3D world coordinates
            leftShoulder3D: nil,
            rightShoulder3D: nil,
            leftElbow3D: nil,
            rightElbow3D: nil,
            // Keep confidence scores - also swap
            leftShoulderConfidence: isMirrored ? Float(truncating: rightShoulder.visibility ?? 0) : Float(truncating: leftShoulder.visibility ?? 0),
            rightShoulderConfidence: isMirrored ? Float(truncating: leftShoulder.visibility ?? 0) : Float(truncating: rightShoulder.visibility ?? 0),
            leftElbowConfidence: isMirrored ? Float(truncating: rightElbow.visibility ?? 0) : Float(truncating: leftElbow.visibility ?? 0),
            rightElbowConfidence: isMirrored ? Float(truncating: leftElbow.visibility ?? 0) : Float(truncating: rightElbow.visibility ?? 0),
            leftWristConfidence: isMirrored ? Float(truncating: rightWrist.visibility ?? 0) : Float(truncating: leftWrist.visibility ?? 0),
            rightWristConfidence: isMirrored ? Float(truncating: leftWrist.visibility ?? 0) : Float(truncating: rightWrist.visibility ?? 0),
            noseConfidence: Float(truncating: nose.visibility ?? 0),
            neckConfidence: 0.0
        )

        return keypoints
    }

    // MARK: - Helpers

    private func uiOrientationToImageOrientation(_ orientation: UIImage.Orientation)
        -> UIImage.Orientation
    {
        return orientation
    }

    private func handleSuccess() {
        consecutiveFailures = 0
        lastSuccessfulDetection = Date()

        // Clear consecutive failures on success
        // Error handler will auto-clear on successful detection
    }

    private func handleFailure(reason: String) {
        consecutiveFailures += 1

        if consecutiveFailures == 1 {
            FlexaLog.vision.warning("⚠️ [MEDIAPIPE] Detection failed: \(reason)")
        }

        if consecutiveFailures >= self.maxConsecutiveFailures {
            FlexaLog.vision.error(
                "❌ [MEDIAPIPE] \(self.maxConsecutiveFailures) consecutive failures")

            // Notify error handler
            if let handler = errorHandler {
                let _ = // timeSinceLastSuccess - unused
                    lastSuccessfulDetection.map { Date().timeIntervalSince($0) } ?? 999

                Task { @MainActor in
                    handler.handleError(.visionPoseNotDetected)
                }
            }
        }
    }
}

