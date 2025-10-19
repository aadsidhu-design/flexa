import Foundation
import AVFoundation
import UIKit

@available(*, deprecated, message: "VisionPoseProvider is deprecated. Use MediaPipePoseProvider instead.")
final class VisionPoseProvider: ObservableObject {
    // Minimal no-op stub to preserve public API without using Apple Vision
    var onPoseDetected: ((SimplifiedPoseKeypoints) -> Void)?
    private var errorHandler: ROMErrorHandler?

    func setErrorHandler(_ handler: ROMErrorHandler) {
        self.errorHandler = handler
    }

    func start() {
        FlexaLog.vision.warning("👁 [VISION-DEPRECATED] VisionPoseProvider.start called; use MediaPipePoseProvider instead.")
    }

    func stop() {
        FlexaLog.vision.info("👁 [VISION-DEPRECATED] VisionPoseProvider.stop called")
    }

    func startPoseTracking() { start() }
    func stopPoseTracking() { stop() }

    func configureCamera(position: AVCaptureDevice.Position) {}

    func processFrame(_ sampleBuffer: CMSampleBuffer) {
        // Deprecated provider does not process frames.
    }

    func process(sampleBuffer: CMSampleBuffer,
                 cgImageOrientation: CGImagePropertyOrientation,
                 cameraPosition: AVCaptureDevice.Position,
                 isMirrored: Bool,
                 completion: @escaping (SimplifiedPoseKeypoints?) -> Void) {
        completion(nil)
    }
}

