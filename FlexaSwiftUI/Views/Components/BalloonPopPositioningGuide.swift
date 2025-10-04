import SwiftUI
import AVFoundation

struct BalloonPopPositioningGuide: View {
    @EnvironmentObject var motionService: SimpleMotionService
    @State private var isPositioned = false
    @State private var positioningTimer: Timer?
    @State private var positioningCountdown = 3
    @State private var showCountdown = false
    
    let onPositioned: () -> Void
    
    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewView()
                .ignoresSafeArea()
                .environmentObject(motionService)
            
            // Positioning overlay
            VStack {
                Spacer()
                
                // Instructions
                VStack(spacing: 20) {
                    // Header with balloon icon
                    VStack(spacing: 12) {
                        Image(systemName: "balloon.2")
                            .font(.system(size: 50))
                            .foregroundColor(.pink)
                        
                        Text("Balloon Pop!")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    
                    // Clear instructions
                    VStack(spacing: 12) {
                        Text("Position your head in the frame")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        
                        Text("Make sure your head is clearly visible for balloon popping")
                            .font(.body)
                            .foregroundColor(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    
                    // Positioning box - only head needed
                    ZStack {
                        // Outer frame
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white, lineWidth: 4)
                            .frame(width: 200, height: 250)
                            .opacity(0.8)
                        
                        // Inner positioning area
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isPositioned ? Color.green : Color.yellow, lineWidth: 3)
                            .frame(width: 180, height: 200)
                            .opacity(0.6)
                        
                        // Head position indicator only
                        VStack {
                            Circle()
                                .stroke(isPositioned ? Color.green : Color.yellow, lineWidth: 3)
                                .frame(width: 60, height: 60)
                                .opacity(0.8)
                            
                            Spacer()
                        }
                        .frame(width: 180, height: 200)
                        
                        // Status indicator
                        VStack {
                            if isPositioned {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.yellow)
                            }
                            
                            Spacer()
                        }
                        .frame(width: 180, height: 200)
                    }
                    
                    // Countdown
                    if showCountdown {
                        Text("Starting in \(positioningCountdown)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(10)
                    }
                }
                .padding()
                .background(Color.black.opacity(0.6))
                .cornerRadius(20)
                .padding(.horizontal, 20)
                
                Spacer()
            }
        }
        .onAppear {
            startPositioningCheck()
        }
        .onDisappear {
            stopPositioningCheck()
        }
    }
    
    private func startPositioningCheck() {
        positioningTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            checkPosition()
        }
    }
    
    private func stopPositioningCheck() {
        positioningTimer?.invalidate()
        positioningTimer = nil
    }
    
    private func checkPosition() {
        guard let keypoints = motionService.poseKeypoints else {
            isPositioned = false
            return
        }
        
        // Check if head is in the target box area
        if let nose = keypoints.nose {
            let screenHeight = UIScreen.main.bounds.height
            let targetY = screenHeight * 0.4
            let distance = abs(nose.y * screenHeight - targetY)
            let wasPositioned = isPositioned
            isPositioned = distance < 125 // Within box height
            
            // Start countdown when positioned
            if isPositioned && !wasPositioned {
                startCountdown()
            } else if !isPositioned && wasPositioned {
                showCountdown = false
                positioningCountdown = 3
            }
        } else {
            isPositioned = false
        }
    }
    
    private func startCountdown() {
        showCountdown = true
        positioningCountdown = 3
        
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            positioningCountdown -= 1
            
            if positioningCountdown <= 0 {
                timer.invalidate()
                showCountdown = false
                onPositioned()
            }
        }
    }
}
