import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession?
    
    init(session: AVCaptureSession? = nil) {
        self.session = session
        FlexaLog.motion.info("📹 [PREVIEW-VIEW] CameraPreviewView init with session: \(session?.debugDescription ?? "nil")")
    }
    
    func makeUIView(context: Context) -> CameraPreview {
        FlexaLog.motion.info("📹 [PREVIEW-VIEW] makeUIView with session: \(session?.debugDescription ?? "nil")")
        let preview = CameraPreview(session: session)
        FlexaLog.motion.info("📹 [PREVIEW-VIEW] CameraPreview created: \(preview)")
        return preview
    }
    
    func updateUIView(_ uiView: CameraPreview, context: Context) {
        FlexaLog.motion.info("📹 [PREVIEW-VIEW] updateUIView with session: \(session?.debugDescription ?? "nil")")
        // Attach session dynamically if it becomes available later
        uiView.attach(session: session)
    }
}

class CameraPreview: UIView {
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    init(session: AVCaptureSession? = nil) {
        super.init(frame: .zero)
        FlexaLog.motion.info("📹 [PREVIEW] CameraPreview init with session: \(session?.debugDescription ?? "nil")")
        self.captureSession = session
        if session != nil { 
            FlexaLog.motion.info("📹 [PREVIEW] Session provided - setting up preview layer")
            setupPreviewLayer() 
        } else {
            FlexaLog.motion.info("📹 [PREVIEW] No session provided - will wait for attach")
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        FlexaLog.motion.debug("📹 [PREVIEW] layoutSubviews - bounds: \(NSCoder.string(for: self.bounds))")
        if let previewLayer = self.previewLayer {
            previewLayer.frame = self.bounds
            FlexaLog.motion.debug("📹 [PREVIEW] Preview layer frame updated to: \(NSCoder.string(for: self.bounds))")
        } else {
            FlexaLog.motion.debug("📹 [PREVIEW] No preview layer to layout")
        }
    }
    
    deinit {
        // Session lifecycle is owned by the motion service
    }
    
    private func setupPreviewLayer() {
        guard let captureSession = self.captureSession else { 
            FlexaLog.motion.warning("📹 [PREVIEW] setupPreviewLayer called but no capture session")
            return 
        }
        
        FlexaLog.motion.info("📹 [PREVIEW] Setting up preview layer for session: \(captureSession)")
        self.previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        self.previewLayer?.videoGravity = .resizeAspectFill
        FlexaLog.motion.info("📹 [PREVIEW] Preview layer created with videoGravity=resizeAspectFill")
        
        self.updateConnectionConfiguration(for: captureSession)
        
        if let previewLayer = self.previewLayer {
            FlexaLog.motion.info("📹 [PREVIEW] Adding preview layer to view hierarchy")
            self.layer.addSublayer(previewLayer)
            FlexaLog.motion.info("📹 [PREVIEW] Preview layer added successfully - bounds: \(NSCoder.string(for: self.bounds))")
        } else {
            FlexaLog.motion.error("📹 [PREVIEW] Failed to create preview layer")
        }
    }

    func attach(session: AVCaptureSession?) {
        FlexaLog.motion.info("📹 [PREVIEW] attach called with session: \(session?.debugDescription ?? "nil")")
        guard let session = session else { 
            FlexaLog.motion.info("📹 [PREVIEW] No session to attach - clearing current session")
            self.captureSession = nil
            self.previewLayer?.session = nil
            return 
        }
        
        // If already attached to this session, skip
        if self.captureSession === session { 
            FlexaLog.motion.info("📹 [PREVIEW] Already attached to this session - skipping")
            return 
        }
        
        FlexaLog.motion.info("📹 [PREVIEW] Attaching to new session - isRunning: \(session.isRunning)")
        self.captureSession = session
        
        if let previewLayer = self.previewLayer {
            FlexaLog.motion.info("📹 [PREVIEW] Updating existing preview layer session")
            previewLayer.session = session
            self.updateConnectionConfiguration(for: session)
        } else {
            FlexaLog.motion.info("📹 [PREVIEW] No existing preview layer - creating new one")
            self.setupPreviewLayer()
        }
        
        FlexaLog.motion.info("📹 [PREVIEW] Triggering layout update")
        self.setNeedsLayout()
    }
    
    private func updateConnectionConfiguration(for session: AVCaptureSession) {
        guard let connection = self.previewLayer?.connection else { return }
        if connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = session.inputs.contains(where: { input in
                guard let deviceInput = input as? AVCaptureDeviceInput else { return false }
                return deviceInput.device.position == .front
            })
        }
    }
    
}
