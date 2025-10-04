import Foundation
import Vision
import AVFoundation
import CoreGraphics

struct TPoseEstimation {
    let leftShoulder: CGPoint?
    let rightShoulder: CGPoint?
    let leftWrist: CGPoint?
    let rightWrist: CGPoint?
    let confidence: Float
}

final class VisionTPoseEstimator {
    private let request = VNDetectHumanBodyPoseRequest()
    private let queue = DispatchQueue(label: "com.flexa.tpose", qos: .userInitiated)
    
    func analyze(sampleBuffer: CMSampleBuffer, completion: @escaping (TPoseEstimation?) -> Void) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { completion(nil); return }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .leftMirrored, options: [:])
        queue.async {
            do {
                try handler.perform([self.request])
                guard let obs = self.request.results?.first as? VNHumanBodyPoseObservation else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                var conf: Float = 0
                let lS = self.point(obs, .leftShoulder, conf: &conf)
                let rS = self.point(obs, .rightShoulder, conf: &conf)
                let lW = self.point(obs, .leftWrist, conf: &conf)
                let rW = self.point(obs, .rightWrist, conf: &conf)
                let est = TPoseEstimation(leftShoulder: lS, rightShoulder: rS, leftWrist: lW, rightWrist: rW, confidence: conf / 4)
                DispatchQueue.main.async { completion(est) }
            } catch {
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }
    
    private func point(_ obs: VNHumanBodyPoseObservation, _ joint: VNHumanBodyPoseObservation.JointName, conf: inout Float) -> CGPoint? {
        guard let j = try? obs.recognizedPoint(joint), j.confidence > 0.3 else { return nil }
        conf += j.confidence
        // j.location is in normalized image coordinates (0-1)
        return CGPoint(x: CGFloat(j.location.x), y: CGFloat(1 - j.location.y))
    }
    
    // Anthropometric estimate: shoulder-to-wrist ~ 0.36-0.40 of height; use 0.38
    func estimateArmLengthMeters(fromUserHeightMeters h: Double) -> Double { max(0.3, min(1.0, 0.38 * h)) }
}
