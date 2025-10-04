import SwiftUI
import AVFoundation

struct WallClimbersPositioningGuide: View {
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
                    // Header with climbing icon
                    VStack(spacing: 12) {
                        Image(systemName: "figure.climbing")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)
                        
                        Text("Wall Climbers!")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    
                    // Clear instructions
                    VStack(spacing: 12) {
                        Text("Position your arms in the frame")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        
                        Text("Make sure your arms are clearly visible for climbing movements")
                            .font(.body)
                            .foregroundColor(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    
                    // Positioning box - arms and shoulders needed
                    ZStack {
                        // Outer frame
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white, lineWidth: 4)
                            .frame(width: 280, height: 400)
                            .opacity(0.8)
                        
                        // Inner positioning area
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isPositioned ? Color.green : Color.yellow, lineWidth: 3)
                            .frame(width: 240, height: 360)
                            .opacity(0.6)
                        
                        // Arm position indicators
                        VStack {
                            // Head position
                            Circle()
                                .stroke(isPositioned ? Color.green : Color.yellow, lineWidth: 3)
                                .frame(width: 40, height: 40)
                                .opacity(0.6)
                            
                            Spacer()
                            
                            // Shoulder position indicators
                            HStack(spacing: 80) {
                                Circle()
                                    .stroke(isPositioned ? Color.green : Color.yellow, lineWidth: 2)
                                    .frame(width: 30, height: 30)
                                    .opacity(0.6)
                                
                                Circle()
                                    .stroke(isPositioned ? Color.green : Color.yellow, lineWidth: 2)
                                    .frame(width: 30, height: 30)
                                    .opacity(0.6)
                            }
                            
                            Spacer()
                            
                            // Wrist position indicators
                            HStack(spacing: 100) {
                                Circle()
                                    .stroke(isPositioned ? Color.green : Color.yellow, lineWidth: 2)
                                    .frame(width: 25, height: 25)
                                    .opacity(0.6)
                                
                                Circle()
                                    .stroke(isPositioned ? Color.green : Color.yellow, lineWidth: 2)
                                    .frame(width: 25, height: 25)
                                    .opacity(0.6)
                            }
                            
                            Spacer()
                        }
                        .frame(width: 240, height: 360)
                        
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
                        .frame(width: 240, height: 360)
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
        
        // Check if both shoulders and wrists are visible
        let hasLeftShoulder = keypoints.leftShoulder != nil
        let hasRightShoulder = keypoints.rightShoulder != nil
        let hasLeftWrist = keypoints.leftWrist != nil
        let hasRightWrist = keypoints.rightWrist != nil
        
        let wasPositioned = isPositioned
        isPositioned = hasLeftShoulder && hasRightShoulder && hasLeftWrist && hasRightWrist
        
        // Start countdown when positioned
        if isPositioned && !wasPositioned {
            startCountdown()
        } else if !isPositioned && wasPositioned {
            showCountdown = false
            positioningCountdown = 3
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
