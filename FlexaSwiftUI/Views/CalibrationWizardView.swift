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
    private enum AutoStage { case waitingARKit, waitingChest, waitingReach, applying, done }
    @State private var autoStage: AutoStage = .waitingARKit
    @State private var autoTimer: Timer? = nil
    @State private var positionBuffer: [SIMD3<Double>] = []
    @State private var chestSIMD: SIMD3<Double>? = nil
    @State private var lastAutoCaptureTime: Date = .distantPast
    
    // Multi-sample collection (3-5 samples per position)
    @State private var chestSamples: [SIMD3<Double>] = []
    @State private var reachSamples: [SIMD3<Double>] = []
    private let samplesPerPosition = 1  // Single capture per position for quicker flow
    private let maxSampleVariance = 0.08 // Relaxed to 8cm (ARKit can be noisy)
    
    // ARKit initialization tracking
    @State private var arkitReady: Bool = false
    @State private var arkitInitStartTime: Date = .distantPast
    
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
                        // Stop ARKit tracker when finishing calibration
                        motionService.deactivateInstantARKitTracking(source: "CalibrationWizard.done")
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
            FlexaLog.motion.info("🎯 [Calibration] Starting wizard")
            
            // Reset state
            autoStage = .waitingARKit
            arkitReady = false
            arkitInitStartTime = Date()
            CalibrationDataManager.shared.clearQuickArmLength()
            
            // Start ARKit with delay to ensure proper initialization
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                FlexaLog.motion.info("🎯 [Calibration] Starting ARKit tracker")
                motionService.activateInstantARKitTracking(source: "CalibrationWizard")
                
                // Start auto-capture after ARKit initializes
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    FlexaLog.motion.info("🎯 [Calibration] Starting auto-capture timer")
                    startAutoCapture()
                }
            }
            
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
            // Defensive: stop ARKit tracker on exit
            motionService.deactivateInstantARKitTracking(source: "CalibrationWizard.onDisappear")
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
            // Mark user as calibrated
            UserDefaults.standard.set(true, forKey: "hasCompletedROMCalibration")
            NotificationCenter.default.post(name: Notification.Name("CalibrationCompleted"), object: nil)
            completed = true
        }
    }

    // MARK: - Auto-capture engine
    private func startAutoCapture() {
        stopAutoCapture()
        
        FlexaLog.motion.info("🎯 [Calibration] Auto-capture started")
        
        // Clear all state
        positionBuffer.removeAll()
        chestSamples.removeAll()
        reachSamples.removeAll()
        quickChestCaptured = false
        quickReachCaptured = false
        chestSIMD = nil
        quickPreview = nil
        lastAutoCaptureTime = .distantPast
        
        // Start timer at 30fps (less aggressive than 60fps)
        autoTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
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
        case .waitingARKit:
            return "Initializing ARKit tracking..."
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
        case .waitingARKit:
            let elapsed = Date().timeIntervalSince(arkitInitStartTime)
            return "Initializing camera tracking...\n\(Int(max(0, 3 - elapsed)))s"
        case .waitingChest:
            if chestSamples.isEmpty {
                return "Hold phone at your chest\nKeep steady and still"
            } else {
                let progress = "\(chestSamples.count)/\(samplesPerPosition)"
                return "Hold phone at your chest\nCapturing... \(progress)"
            }
        case .waitingReach:
            if reachSamples.isEmpty {
                return "Extend arm straight forward\nKeep steady and still"
            } else {
                let progress = "\(reachSamples.count)/\(samplesPerPosition)"
                return "Extend arm straight forward\nCapturing... \(progress)"
            }
        case .applying:
            return "Calculating arm length..."
        case .done:
            return "Calibration complete!"
        }
    }
    private func currentARPosition() -> SIMD3<Double>? {
        guard let tr = motionService.currentARKitTransform else {
            return nil
        }
        
        let pos = SIMD3<Double>(Double(tr.columns.3.x), Double(tr.columns.3.y), Double(tr.columns.3.z))
        
        // Sanity check: ARKit positions should be within reasonable bounds (±5m from origin)
        let magnitude = simd_length(pos)
        guard magnitude < 5.0 else {
            FlexaLog.motion.warning("🎯 [Calibration] Invalid ARKit position: \(pos) (magnitude=\(magnitude)m)")
            return nil
        }
        
        return pos
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
        guard !completed else { return }
        
        let now = Date()
        
        switch autoStage {
        case .waitingARKit:
            // Wait for ARKit to initialize (check for valid position)
            if currentARPosition() != nil {
                let initTime = now.timeIntervalSince(arkitInitStartTime)
                
                // Require at least 3 seconds of ARKit tracking before starting
                if initTime >= 3.0 {
                    FlexaLog.motion.info("🎯 [Calibration] ARKit ready, switching to chest capture")
                    arkitReady = true
                    autoStage = .waitingChest
                    positionBuffer.removeAll()
                    // Removed pre-stage haptic — vibrate only when chest/reach complete
                }
            } else {
                // ARKit not ready yet, wait longer
                if now.timeIntervalSince(arkitInitStartTime) > 10.0 {
                    FlexaLog.motion.error("🎯 [Calibration] ARKit failed to initialize after 10s")
                    // Could show error UI here
                }
            }
            
        case .waitingChest:
            guard let pos = currentARPosition() else {
                FlexaLog.motion.warning("🎯 [Calibration] Lost ARKit position in chest stage")
                return
            }
            
            // Maintain buffer
            positionBuffer.append(pos)
            if positionBuffer.count > 60 { positionBuffer.removeFirst(positionBuffer.count - 60) }
            
            // Need sufficient buffer and stability before capturing
            if positionBuffer.count >= 30 && bufferStable(Array(positionBuffer.suffix(30)), tol: 0.006) {
                if now.timeIntervalSince(lastAutoCaptureTime) > 1.0 {
                    // Collect sample from stable buffer
                    let sample = positionBuffer.suffix(30).reduce(SIMD3<Double>(0,0,0), +) / 30.0
                    chestSamples.append(sample)
                    lastAutoCaptureTime = now
                    
                    FlexaLog.motion.info("🎯 [Calibration] Chest sample \(chestSamples.count)/\(samplesPerPosition) captured")
                    
                    // After collecting enough samples, validate and average
                    if chestSamples.count >= samplesPerPosition {
                        if let avgChest = validateAndAverageSamples(chestSamples) {
                            CalibrationDataManager.shared.captureQuickArmLength(.chest)
                            chestSIMD = avgChest
                            quickChestCaptured = true
                            HapticFeedbackService.shared.successHaptic()
                            autoStage = .waitingReach
                            positionBuffer.removeAll() // Clear buffer for next stage
                            FlexaLog.motion.info("🎯 [Calibration] Chest position saved, moving to reach")
                        } else {
                            // Samples too noisy, retry
                            FlexaLog.motion.warning("🎯 [Calibration] Chest samples variance >8cm, retrying")
                            chestSamples.removeAll()
                            HapticFeedbackService.shared.errorHaptic()
                        }
                    }
                }
            }
            
        case .waitingReach:
            guard let chest = chestSIMD else {
                FlexaLog.motion.error("🎯 [Calibration] No chest position in reach stage")
                autoStage = .waitingChest
                return
            }
            
            guard let pos = currentARPosition() else {
                FlexaLog.motion.warning("🎯 [Calibration] Lost ARKit position in reach stage")
                return
            }
            
            // Maintain buffer
            positionBuffer.append(pos)
            if positionBuffer.count > 60 { positionBuffer.removeFirst(positionBuffer.count - 60) }
            
            let recent = Array(positionBuffer.suffix(30))
            let stable = bufferStable(recent, tol: 0.008)
            let dist = simd_distance(pos, chest)
            
            // Require at least 25cm distance from chest (arm extended)
            if dist > 0.25 && stable && positionBuffer.count >= 30 {
                if now.timeIntervalSince(lastAutoCaptureTime) > 1.0 {
                    // Collect sample from stable buffer
                    let sample = positionBuffer.suffix(30).reduce(SIMD3<Double>(0,0,0), +) / 30.0
                    reachSamples.append(sample)
                    lastAutoCaptureTime = now
                    
                    FlexaLog.motion.info("🎯 [Calibration] Reach sample \(reachSamples.count)/\(samplesPerPosition) captured (dist=\(String(format: "%.2f", dist))m)")
                    
                    // After collecting enough samples, validate and average
                    if reachSamples.count >= samplesPerPosition {
                        if let _ = validateAndAverageSamples(reachSamples) {
                            CalibrationDataManager.shared.captureQuickArmLength(.reach)
                            quickReachCaptured = true
                            quickPreview = CalibrationDataManager.shared.previewQuickArmLength()
                            HapticFeedbackService.shared.successHaptic()
                            autoStage = .applying
                            FlexaLog.motion.info("🎯 [Calibration] Reach position saved, applying calibration")
                        } else {
                            // Samples too noisy, retry
                            FlexaLog.motion.warning("🎯 [Calibration] Reach samples variance >8cm, retrying")
                            reachSamples.removeAll()
                            HapticFeedbackService.shared.errorHaptic()
                        }
                    }
                }
            }
            
        case .applying:
            FlexaLog.motion.info("🎯 [Calibration] Applying arm length measurement")
            quickApply()
            autoStage = .done
            
        case .done:
            FlexaLog.motion.info("🎯 [Calibration] Complete, stopping timer")
            stopAutoCapture()
        }
    }
    
    /// Validates samples have <8cm variance, returns averaged position
    private func validateAndAverageSamples(_ samples: [SIMD3<Double>]) -> SIMD3<Double>? {
        if samples.count == 1 {
            let single = samples[0]
            FlexaLog.motion.info("🎯 [Calibration] Single-sample capture accepted")
            return single
        }
        
        // Calculate mean position
        let mean = samples.reduce(SIMD3<Double>(0,0,0), +) / Double(samples.count)
        
        // Calculate variance (max distance from mean)
        let maxVariance = samples.map { simd_distance($0, mean) }.max() ?? 0.0
        
        FlexaLog.motion.info("🎯 [Calibration] Sample validation: count=\(samples.count), variance=\(String(format: "%.3f", maxVariance))m (threshold=\(String(format: "%.3f", maxSampleVariance))m)")
        
        // Reject if variance exceeds threshold (8cm is reasonable for handheld ARKit)
        if maxVariance >= maxSampleVariance {
            FlexaLog.motion.warning("🎯 [Calibration] Variance too high: \(String(format: "%.3f", maxVariance))m > \(String(format: "%.3f", maxSampleVariance))m")
            return nil
        }
        
        FlexaLog.motion.info("🎯 [Calibration] Samples validated successfully, mean position: \(mean)")
        return mean
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
