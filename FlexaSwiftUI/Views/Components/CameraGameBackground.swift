import SwiftUI

/// Reusable full-screen camera background for camera-based games.
/// Ensures the shared capture session is presented edge-to-edge behind game overlays.
struct CameraGameBackground: View {
    @EnvironmentObject private var motionService: SimpleMotionService

    var body: some View {
        GeometryReader { proxy in
            LiveCameraView()
                .environmentObject(motionService)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .overlay(Color.black.opacity(0.05)) // subtle darken for overlay legibility
                .accessibilityHidden(true)
        }
    }
}
