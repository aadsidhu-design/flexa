import SwiftUI

struct LiveCameraView: View {
    @EnvironmentObject var motionService: SimpleMotionService
    
    var body: some View {
        let session = motionService.previewSession
        FlexaLog.motion.info("📹 [LIVE-CAMERA] Body rendering with session: \(session?.debugDescription ?? "nil")")
        
        return CameraPreviewView(session: session)
            .background(Color.black)
            .onAppear {
                FlexaLog.motion.info("📹 [LIVE-CAMERA] onAppear - ensuring camera ready")
                motionService.ensureCameraPreviewReady()
            }
            .onDisappear {
                FlexaLog.motion.info("📹 [LIVE-CAMERA] onDisappear")
            }
    }
}

#Preview {
    LiveCameraView()
        .environmentObject(SimpleMotionService.shared)
}
