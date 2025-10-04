import SwiftUI
import ARKit
import QuartzCore
import simd

struct CalibrationWizardView: View {
    @EnvironmentObject var motionService: SimpleMotionService
    @Environment(\.dismiss) private var dismiss
    
    // Simplified: Straight-arm ARKit calibration only (no 0/90/180 stages)
    @State private var completed: Bool = false
    // Segment lengths and grip offset inputs
    @State private var armLengthField: String = "0.65"
    @State private var forearmLengthField: String = "0.30"
    @State private var gripOffsetField: String = "0.02"
    @State private var savedConfig: Bool = false
    // Quick arm length flow
    @State private var quickChestCaptured: Bool = false
    @State private var quickReachCaptured: Bool = false
    @State private var quickPreview: Double? = nil
    // Auto-capture state
    private enum AutoStage { case waitingChest, waitingReach, applying, done }
    @State private var autoStage: AutoStage = .waitingChest
    @State private var autoTimer: Timer? = nil
    @State private var positionBuffer: [SIMD3<Double>] = []
    @State private var chestSIMD: SIMD3<Double>? = nil
    @State private var lastAutoCaptureTime: Date = .distantPast
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                if completed {
                    Spacer()
                    Text("Arm Length Saved")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 40)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 64, weight: .semibold))
                        .foregroundColor(.green)
                        .padding(.top, 8)
                    if let cal = CalibrationDataManager.shared.currentCalibration {
                        Text(String(format: "Measured arm length: %.2fm", cal.armLength))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.top, 8)
                    }
                    Spacer()
                    Button(action: { 
                        // Stop ARKit engine when finishing calibration
                        motionService.universal3DEngine.stop()
                        dismiss() 
                    }) {
                        Text("Done")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                            .contentShape(Rectangle())
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                    .tapTarget(60)
                } else {
                    // Minimal full-screen capture prompts only
                    Spacer()
                    Text(minimalPromptText())
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Spacer()
                }
            }
        }
        .onAppear {
            // Ensure ARKit position tracking is running during calibration
            // Start Universal3D engine directly (no CoreMotion)
            let convertedGameType = Universal3DROMEngine.convertGameType(.testROM)
            motionService.universal3DEngine.startDataCollection(gameType: convertedGameType)
            CalibrationDataManager.shared.clearQuickArmLength()
            startAutoCapture()
            // Prefill manual segment lengths from current calibration if available, else defaults
            if let cal = CalibrationDataManager.shared.currentCalibration {
                armLengthField = String(format: "%.2f", cal.armLength)
                if let fa = cal.forearmLength { forearmLengthField = String(format: "%.2f", fa) }
                if let go = cal.gripOffset { gripOffsetField = String(format: "%.2f", go) }
            } else {
                if armLengthField.isEmpty {
                    armLengthField = "0.65"
                    forearmLengthField = "0.30"
                    gripOffsetField = "0.02"
                }
            }
        }
        .onDisappear { 
            stopAutoCapture()
            // Defensive: stop ARKit engine on exit
            motionService.universal3DEngine.stop()
        }
    }
    
    private func pill(_ text: String, done: Bool) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(done ? .black : .white)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(done ? Color.green : Color.gray.opacity(0.25))
            .cornerRadius(10)
    }
    
    // Stage-based titles/instructions removed — using quick arm-length only
    
    // Removed stage-based capture flow
    
    // Removed stage advancement
    
    // Removed IMU stage detector handling
    // Save lengths and grip offset
    // Removed manual segment save (still available via settings if needed)

    // MARK: - Quick Arm Length Actions (auto)
    private func quickApply() {
        if let measured = CalibrationDataManager.shared.applyQuickArmLength() {
            armLengthField = String(format: "%.2f", measured)
            HapticFeedbackService.shared.successHaptic()
            // Mark user as calibrated
            UserDefaults.standard.set(true, forKey: "hasCompletedROMCalibration")
            NotificationCenter.default.post(name: Notification.Name("CalibrationCompleted"), object: nil)
            completed = true
        }
    }

    // MARK: - Auto-capture engine
    private func startAutoCapture() {
        stopAutoCapture()
        autoStage = .waitingChest
        positionBuffer.removeAll()
        quickChestCaptured = false
        quickReachCaptured = false
        chestSIMD = nil
        quickPreview = nil
        lastAutoCaptureTime = .distantPast
        autoTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            autoTick()
        }
        RunLoop.main.add(autoTimer!, forMode: .common)
    }
    private func stopAutoCapture() {
        autoTimer?.invalidate()
        autoTimer = nil
    }
    private func statusLine() -> String {
        switch autoStage {
        case .waitingChest:
            return "Step 1/2: Hold still at CHEST — capturing…"
        case .waitingReach:
            return "Step 2/2: Fully REACH forward — capturing…"
        case .applying:
            return "Applying and saving…"
        case .done:
            return "Done. Arm length saved."
        }
    }
    
    // Minimal, text-only prompt for capture (no other UI while capturing)
    private func minimalPromptText() -> String {
        switch autoStage {
        case .waitingChest:
            return "Hold phone at your chest\nKeep still until it vibrates"
        case .waitingReach:
            return "Hold phone straight in front of you\nKeep still until it vibrates"
        case .applying:
            return "Saving measurement…"
        case .done:
            return "Arm length saved"
        }
    }
    private func currentARPosition() -> SIMD3<Double>? {
        if let tr = motionService.universal3DEngine.currentTransform {
            return SIMD3<Double>(Double(tr.columns.3.x), Double(tr.columns.3.y), Double(tr.columns.3.z))
        }
        return nil
    }
    private func bufferStable(_ buf: [SIMD3<Double>], tol: Double) -> Bool {
        guard !buf.isEmpty else { return false }
        // Compute mean
        let mean = buf.reduce(SIMD3<Double>(0,0,0), +) / Double(buf.count)
        // RMS distance from mean
        let rms = sqrt(buf.reduce(0.0) { acc, p in
            acc + simd_length_squared(p - mean)
        } / Double(buf.count))
        return rms < tol
    }
    private func autoTick() {
        guard let pos = currentARPosition(), !completed else { return }
        // Maintain buffer
        positionBuffer.append(pos)
        if positionBuffer.count > 45 { positionBuffer.removeFirst(positionBuffer.count - 45) }
        let now = Date()
        switch autoStage {
        case .waitingChest:
            if positionBuffer.count >= 24 && bufferStable(Array(positionBuffer.suffix(24)), tol: 0.004) {
                if now.timeIntervalSince(lastAutoCaptureTime) > 0.5 {
                    CalibrationDataManager.shared.captureQuickArmLength(.chest)
                    chestSIMD = positionBuffer.suffix(24).reduce(SIMD3<Double>(0,0,0), +) / 24.0
                    quickChestCaptured = true
                    HapticFeedbackService.shared.successHaptic()
                    lastAutoCaptureTime = now
                    autoStage = .waitingReach
                }
            }
        case .waitingReach:
            guard let chest = chestSIMD else { break }
            let recent = Array(positionBuffer.suffix(20))
            let stable = bufferStable(recent, tol: 0.006)
            let dist = simd_distance(pos, chest)
            if dist > 0.28 && stable {
                if now.timeIntervalSince(lastAutoCaptureTime) > 0.5 {
                    CalibrationDataManager.shared.captureQuickArmLength(.reach)
                    quickReachCaptured = true
                    quickPreview = CalibrationDataManager.shared.previewQuickArmLength()
                    HapticFeedbackService.shared.successHaptic()
                    lastAutoCaptureTime = now
                    autoStage = .applying
                }
            }
        case .applying:
            quickApply()
            autoStage = .done
        case .done:
            stopAutoCapture()
        }
    }

}

final class OrientationStageDetector: ObservableObject {
    enum Stage { case down, tpose, overhead }
    @Published var currentAngle: Double = 0
    @Published var didCaptureZero: Bool = false
    @Published var didCaptureNinety: Bool = false
    @Published var didCaptureOneEighty: Bool = false
    var onStableStage: ((Stage) -> Void)?

    private var stage: Stage = .down
    private var stableSince: Date? = nil
    private let holdSeconds: TimeInterval = 1.0
    private var timer: CADisplayLink?
    private var lastTransform: simd_float4x4?
    // Gravity at user's starting orientation (0°). Angle = acos(dot(g0, g)).
    private var gZero: SIMD3<Double>? = nil

    func start() {
        timer = CADisplayLink(target: self, selector: #selector(tick))
        timer?.preferredFrameRateRange = CAFrameRateRange(minimum: 55, maximum: 60, preferred: 60)
        timer?.add(to: .main, forMode: .common)
    }
    func stop() { timer?.invalidate(); timer = nil }
    func setStage(_ s: Stage) {
        stage = s
        stableSince = nil
        if s == .down { gZero = nil }
    }

    @objc private func tick() {
        // Use CoreMotion IMU directly for angle calculation (ARKit only for arm length)
        guard let motion = SimpleMotionService.shared.currentDeviceMotion else { return }

        // Build normalized gravity vector in device frame
        let g = SIMD3<Double>(motion.gravity.x, motion.gravity.y, motion.gravity.z)
        let ng = simd_normalize(g)
        if gZero == nil { gZero = ng }
        let g0 = gZero!

        // Angle between current gravity and initial gravity (0° stage)
        let dotv = max(-1.0, min(1.0, simd_dot(g0, ng)))
        let angle = acos(dotv) * 180.0 / .pi

        currentAngle = max(0, min(180, angle))

        // Evaluate stage based on IMU-derived angle only (ARKit is NOT used for angle)
        evaluate(currentAngle)
    }

    private func evaluate(_ angle: Double) {
        let tol = (stage == .tpose) ? 10.0 : 12.0
        let ok: Bool
        switch stage {
        case .down: ok = angle < tol
        case .tpose: ok = abs(angle - 90.0) < tol
        case .overhead: ok = angle > (180.0 - tol)
        }

        if ok {
            if stableSince == nil { stableSince = Date() }
            if Date().timeIntervalSince(stableSince!) >= holdSeconds {
                onStableStage?(stage)
                stableSince = nil
            }
        } else {
            stableSince = nil
        }
    }
}
