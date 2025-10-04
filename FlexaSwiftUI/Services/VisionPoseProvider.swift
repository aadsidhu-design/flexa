import Foundation
import AVFoundation
import Vision
import UIKit

final class VisionPoseProvider: ObservableObject {
    private let queue = DispatchQueue(label: "com.flexa.vision.pose", qos: .userInitiated)
    private let request = VNDetectHumanBodyPoseRequest()
    private var started = false
    private var isProcessingFrame = false
    
    // Optional callback if a consumer wants push updates
    var onPoseDetected: ((SimplifiedPoseKeypoints) -> Void)?
    
    // Error handling
    private var errorHandler: ROMErrorHandler?
    private var consecutiveFailures: Int = 0
    private let maxConsecutiveFailures = 10
    private var lastSuccessfulDetection: Date?
    
    deinit {
        // Stop processing and clear callbacks
        stop()
        onPoseDetected = nil
        FlexaLog.vision.info("VisionPoseProvider deinitializing and cleaning up resources")
    }
    
    /// Set error handler for recovery support
    func setErrorHandler(_ handler: ROMErrorHandler) {
        self.errorHandler = handler
    }
    
    func start() { 
        FlexaLog.vision.info("👁 [VISION] Starting pose tracking")
        started = true 
    }
    
    func stop() { 
        FlexaLog.vision.info("👁 [VISION] Stopping pose tracking")
        started = false 
    }
    
    // Same as start(), just a more descriptive name
    func startPoseTracking() { start() }
    func stopPoseTracking() { stop() }
    
    // Frame counting for debugging
    private var visionFrameCount: Int = 0
    
    // Called by SimpleMotionService
    func processFrame(_ sampleBuffer: CMSampleBuffer) {
        visionFrameCount += 1
        
        guard started else { 
            if visionFrameCount % 30 == 0 {
                FlexaLog.vision.warning("👁 [VISION] Frame #\(self.visionFrameCount) received but not started")
            }
            return 
        }
        
        // Drop frame if a previous Vision request is still running
        if isProcessingFrame { 
            if visionFrameCount % 30 == 0 {
                FlexaLog.vision.debug("👁 [VISION] Frame #\(self.visionFrameCount) dropped - still processing")
            }
            return 
        }
        
        if visionFrameCount % 30 == 0 {
            FlexaLog.vision.debug("👁 [VISION] Processing frame #\(self.visionFrameCount)")
        }
        
        isProcessingFrame = true
        // Front camera portrait frames are delivered as .leftMirrored for upright people space
        // This orientation ensures proper skeleton alignment with the camera preview
        let orientation: CGImagePropertyOrientation = .leftMirrored
        process(sampleBuffer: sampleBuffer,
                cgImageOrientation: orientation,
                cameraPosition: .front,
                isMirrored: true) { [weak self] keypoints in
            guard let self else { return }
            if let keypoints = keypoints {
                if self.visionFrameCount % 30 == 0 {
                    FlexaLog.vision.debug("👁 [VISION] Frame #\(self.visionFrameCount) processed successfully - calling callback")
                }
                self.onPoseDetected?(keypoints)
            } else {
                if self.visionFrameCount % 30 == 0 {
                    FlexaLog.vision.debug("👁 [VISION] Frame #\(self.visionFrameCount) processed but no keypoints")
                }
            }
        }
    }
    
    func process(sampleBuffer: CMSampleBuffer,
                 cgImageOrientation: CGImagePropertyOrientation,
                 cameraPosition: AVCaptureDevice.Position,
                 isMirrored: Bool,
                 completion: @escaping (SimplifiedPoseKeypoints?) -> Void) {
        guard started, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
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
                    let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: cgImageOrientation, options: [:])
                    try handler.perform([self.request])
                    guard let obs = self.request.results?.first as? VNHumanBodyPoseObservation else {
                        // Only log failure if we haven't had too many consecutive failures
                        if self.consecutiveFailures < 5 {
                            self.handleVisionFailure(reason: "No pose observation detected")
                        }
                        DispatchQueue.main.async {
                            self.isProcessingFrame = false
                            completion(nil)
                        }
                        return
                    }
                    let keypoints = VisionPoseProvider.makeKeypoints(from: obs, isMirrored: isMirrored)
                    if keypoints != nil {
                        self.handleVisionSuccess()
                    } else {
                        // Only log failure if we haven't had too many consecutive failures
                        if self.consecutiveFailures < 5 {
                            self.handleVisionFailure(reason: "Failed to extract keypoints")
                        }
                    }
                    DispatchQueue.main.async {
                        self.isProcessingFrame = false
                        completion(keypoints)
                    }
                } catch {
                    // Only log error if we haven't had too many consecutive failures
                    if self.consecutiveFailures < 5 {
                        self.handleVisionFailure(reason: "Vision processing error: \(error.localizedDescription)")
                    }
                    DispatchQueue.main.async {
                        self.isProcessingFrame = false
                        completion(nil)
                    }
                }
            }
        }
    }
    
    private static func makeKeypoints(from obs: VNHumanBodyPoseObservation, isMirrored _: Bool) -> SimplifiedPoseKeypoints? {
        func point(_ joint: VNHumanBodyPoseObservation.JointName) -> (CGPoint, Float)? {
            guard let rp = try? obs.recognizedPoint(joint), rp.confidence > 0 else { return nil }
            
            // Use a consistent coordinate space that matches camera aspect ratio
            // Camera is 640x480, but we'll use portrait orientation (480 wide, 640 tall)
            let referenceWidth: CGFloat = 480.0
            let referenceHeight: CGFloat = 640.0
            
            // Vision coordinates: (0,0) is bottom-left, (1,1) is top-right
            // Convert to reference coordinate space with top-left origin
            let x = CGFloat(rp.location.x) * referenceWidth
            let y = CGFloat(1.0 - rp.location.y) * referenceHeight // Flip Y for top-left origin
            
            // Orientation .leftMirrored already matches the mirrored preview, so no further X flip is required here.
            
            return (CGPoint(x: x, y: y), Float(rp.confidence))
        }
        func conf(_ joint: VNHumanBodyPoseObservation.JointName) -> Float {
            return (try? obs.recognizedPoint(joint).confidence).map { Float($0) } ?? 0
        }
        let ls = point(.leftShoulder)?.0
        let rs = point(.rightShoulder)?.0
        let le = point(.leftElbow)?.0
        let re = point(.rightElbow)?.0
        let lw = point(.leftWrist)?.0
        let rw = point(.rightWrist)?.0
        let lh = point(.leftHip)?.0
        let rh = point(.rightHip)?.0
        let nose = point(.nose)?.0
        let neck: CGPoint? = {
            if let ls = ls, let rs = rs { return CGPoint(x: (ls.x+rs.x)/2, y: (ls.y+rs.y)/2) }
            return nil
        }()
        return SimplifiedPoseKeypoints(
            timestamp: CACurrentMediaTime(),
            leftWrist: lw,
            rightWrist: rw,
            leftElbow: le,
            rightElbow: re,
            leftShoulder: ls,
            rightShoulder: rs,
            nose: nose,
            neck: neck,
            leftHip: lh,
            rightHip: rh,
            leftEye: nil,
            rightEye: nil,
            leftShoulder3D: nil,
            rightShoulder3D: nil,
            leftElbow3D: nil,
            rightElbow3D: nil,
            leftShoulderConfidence: conf(.leftShoulder),
            rightShoulderConfidence: conf(.rightShoulder),
            leftElbowConfidence: conf(.leftElbow),
            rightElbowConfidence: conf(.rightElbow),
            neckConfidence: (ls != nil && rs != nil) ? (conf(.leftShoulder)+conf(.rightShoulder))/2.0 : 0.0
        )
    }
    
    // MARK: - Error Handling
    
    private func handleVisionSuccess() {
        consecutiveFailures = 0
        lastSuccessfulDetection = Date()
    }
    
    private func handleVisionFailure(reason: String) {
        consecutiveFailures += 1
        
        FlexaLog.vision.warning("Vision processing failure: \(reason)")
        
        // Check if we should report this as an error
        if consecutiveFailures >= maxConsecutiveFailures {
            errorHandler?.handleError(.visionPoseNotDetected)
        }
        
        // Check for extended periods without detection
        if let lastSuccess = lastSuccessfulDetection,
           Date().timeIntervalSince(lastSuccess) > 10.0 { // 10 seconds without detection
            errorHandler?.handleError(.visionProcessingFailed(NSError(domain: "VisionPoseProvider", code: -1, userInfo: [NSLocalizedDescriptionKey: "Extended period without pose detection"])))
        }
    }
}

