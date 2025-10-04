import SwiftUI
import AVFoundation
import Vision

struct CalibrateTPoseView: View {
    var onComplete: (Double) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var controller = TPoseCameraController()
    @State private var heightCm: String = "170" // default
    @State private var estimatedArmLength: Double = 0.65
    
    enum Stage { case scanning, down, tpose, overhead, complete }
    @State private var stage: Stage = .scanning
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Automatic ROM Calibration")
                .font(.headline)
                .foregroundColor(.white)
            
            // Instructions
            Text(instructionText)
                .foregroundColor(.white.opacity(0.85))
                .font(.caption)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            
            ZStack {
                CameraPreviewView(session: controller.session)
                    .frame(height: 260)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.2), lineWidth: 1))
                VStack {
                    Spacer()
                    HStack {
                        Text("Conf: \(String(format: "%.0f%%", controller.lastConfidence * 100))  |  Angle: \(Int(controller.abductionAngle))°")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.black.opacity(0.4))
                            .cornerRadius(6)
                        Spacer()
                    }.padding(8)
                }
            }
            .padding(.horizontal, 16)
            
            // Stage progress
            HStack(spacing: 12) {
                stagePill("Down", isDone: controller.reachedDown)
                stagePill("T-Pose", isDone: controller.reachedTPose)
                stagePill("Overhead", isDone: controller.reachedOverhead)
            }
            
            // Height input
            HStack(spacing: 10) {
                Text("Your height (cm)")
                    .foregroundColor(.white)
                    .font(.caption)
                TextField("170", text: $heightCm)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .onChange(of: heightCm) { _ in recalcArmLength() }
            }
            .padding(.horizontal, 16)
            
            Text("Estimated arm length: \(String(format: "%.2f m", estimatedArmLength))")
                .foregroundColor(.white)
                .font(.caption)
            
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Done") {
                    onComplete(estimatedArmLength)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!controller.reachedOverhead)
            }
            .padding(.top, 6)
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            controller.onStageChange = { newStage in
                self.stage = newStage
            }
            recalcArmLength()
            controller.start()
        }
        .onDisappear { controller.stop() }
    }
    
    private func stagePill(_ text: String, isDone: Bool) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundColor(isDone ? .black : .white)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(isDone ? Color.green : Color.gray.opacity(0.25))
            .cornerRadius(10)
    }
    
    private var instructionText: String {
        switch stage {
        case .scanning: return "Stand back so your upper body is in view."
        case .down: return "Place arms down at your sides. Hold still…"
        case .tpose: return "Raise arms to a T-pose (90°). Hold still…"
        case .overhead: return "Raise arms overhead (180°). Hold still…"
        case .complete: return "Calibration captured. Tap Done to apply."
        }
    }
    
    private func recalcArmLength() {
        let h = Double(heightCm) ?? 170
        estimatedArmLength = controller.estimator.estimateArmLengthMeters(fromUserHeightMeters: h / 100.0)
    }
}

final class TPoseCameraController: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    let estimator = VisionTPoseEstimator()
    @Published var lastConfidence: Float = 0
    @Published var abductionAngle: Double = 0
    @Published var reachedDown: Bool = false
    @Published var reachedTPose: Bool = false
    @Published var reachedOverhead: Bool = false
    var onStageChange: ((CalibrateTPoseView.Stage) -> Void)?
    private var stage: CalibrateTPoseView.Stage = .scanning { didSet { onStageChange?(stage) } }
    private var stableSince: Date? = nil
    private let queue = DispatchQueue(label: "com.flexa.tpose.camera", qos: .userInitiated)
    
    func start() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            guard granted else { return }
            self.configureSession()
            self.session.startRunning()
            DispatchQueue.main.async { self.stage = .scanning }
        }
    }
    
    func stop() {
        session.stopRunning()
    }
    
    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .high
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else {
            session.commitConfiguration(); return
        }
        if session.canAddInput(input) { session.addInput(input) }
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        if session.canAddOutput(output) { session.addOutput(output) }
        if let conn = output.connection(with: .video) {
            conn.isVideoMirrored = true
            if #available(iOS 17.0, *) {
                let portraitAngle: Double = 90
                if conn.isVideoRotationAngleSupported(portraitAngle) { conn.videoRotationAngle = portraitAngle }
            } else {
                conn.videoOrientation = .portrait
            }
        }
        session.commitConfiguration()
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        estimator.analyze(sampleBuffer: sampleBuffer) { [weak self] est in
            guard let self = self else { return }
            self.lastConfidence = est?.confidence ?? 0
            guard let est = est else { self.updateStage(bodyVisible: false, angle: 0); return }
            // Compute abduction angle using shoulder->wrist vector vs screen vertical
            let (angle, visible) = self.computeAngle(est)
            self.abductionAngle = angle
            self.updateStage(bodyVisible: visible, angle: angle)
        }
    }
    
    private func computeAngle(_ est: TPoseEstimation) -> (Double, Bool) {
        guard let ls = est.leftShoulder, let rs = est.rightShoulder,
              let lw = est.leftWrist, let rw = est.rightWrist else { return (0, false) }
        func angle(_ s: CGPoint, _ w: CGPoint) -> Double {
            let v = CGPoint(x: w.x - s.x, y: w.y - s.y)
            // Screen vertical (downwards)
            let vert = CGPoint(x: 0, y: 1)
            let dot = v.x * vert.x + v.y * vert.y
            let magV = max(1e-3, sqrt(v.x*v.x + v.y*v.y))
            let cosA = max(-1.0, min(1.0, dot / magV)) // |vert|=1
            return acos(cosA) * 180.0 / .pi
        }
        let aL = angle(ls, lw)
        let aR = angle(rs, rw)
        let a = max(aL, aR)
        let conf = est.confidence
        let visible = conf >= 0.4
        return (a, visible)
    }
    
    private func updateStage(bodyVisible: Bool, angle: Double) {
        let now = Date()
        let tol = (stage == .tpose) ? 15.0 : 20.0
        let ok: Bool
        switch stage {
        case .scanning:
            if bodyVisible { stage = .down; stableSince = now }
            return
        case .down:
            ok = angle < tol
        case .tpose:
            ok = abs(angle - 90.0) < tol
        case .overhead:
            ok = angle > (180.0 - tol)
        case .complete:
            return
        }
        if ok {
            if stableSince == nil { stableSince = now }
            if now.timeIntervalSince(stableSince!) > 0.7 {
                DispatchQueue.main.async {
                    switch self.stage {
                    case .down:
                        self.reachedDown = true
                        self.stage = .tpose
                    case .tpose:
                        self.reachedTPose = true
                        self.stage = .overhead
                    case .overhead:
                        self.reachedOverhead = true
                        self.stage = .complete
                    default: break
                    }
                }
                stableSince = now // reset to require hold at next stage
            }
        } else {
            stableSince = nil
        }
    }
}
