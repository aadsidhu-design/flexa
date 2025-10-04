import SwiftUI
import AVFoundation

struct CameraPositioningGuide: View {
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
                    // Header with icon
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.rectangle")
                            .font(.system(size: 50))
                            .foregroundColor(.cyan)
                        
                        Text("Get Ready!")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    
                    // Clear instructions
                    VStack(spacing: 12) {
                        Text("Position yourself in the frame")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        
                        Text("Make sure your head and shoulders are clearly visible")
                            .font(.body)
                            .foregroundColor(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    
                    // Positioning box with better visual feedback
                    ZStack {
                        // Outer frame with pulsing effect
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white, lineWidth: 4)
                            .frame(width: 300, height: 420)
                            .opacity(0.9)
                            .scaleEffect(isPositioned ? 1.0 : 1.05)
                            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: !isPositioned)
                        
                        // Inner positioning area with color feedback
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isPositioned ? Color.green : Color.orange, lineWidth: 4)
                            .frame(width: 260, height: 380)
                            .opacity(0.8)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(isPositioned ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                            )
                        
                        // Head position indicator
                        VStack {
                            Circle()
                                .stroke(isPositioned ? Color.green : Color.yellow, lineWidth: 3)
                                .frame(width: 60, height: 60)
                                .opacity(0.8)
                            
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
                        }
                        .frame(width: 240, height: 360)
                        
                        // Status indicator
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: isPositioned ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .font(.title2)
                                    .foregroundColor(isPositioned ? .green : .yellow)
                                    .padding(.top, 10)
                                    .padding(.trailing, 10)
                            }
                            Spacer()
                        }
                        .frame(width: 240, height: 360)
                    }
                    
                    // Status text with better feedback
                    VStack(spacing: 8) {
                        Text(isPositioned ? "Perfect! Get ready to start..." : "Adjust your position")
                            .font(.subheadline)
                            .foregroundColor(isPositioned ? .green : .orange)
                            .fontWeight(.medium)
                        
                        if isPositioned {
                            Text("Tap anywhere to begin")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                }
                .padding()
                .background(Color.black.opacity(0.7))
                .cornerRadius(20)
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Start button (only when positioned)
                if isPositioned {
                    Button(action: {
                        showCountdown = true
                        startCountdown()
                    }) {
                        Text("Start Game")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 40)
                            .padding(.vertical, 16)
                            .background(Color.green)
                            .cornerRadius(25)
                    }
                    .padding(.bottom, 50)
                }
            }
            
            // Countdown overlay
            if showCountdown {
                Color.black.opacity(0.8)
                    .ignoresSafeArea()
                    .overlay(
                        VStack(spacing: 20) {
                            Text("Starting in...")
                                .font(.title)
                                .foregroundColor(.white)
                            
                            Text("\(positioningCountdown)")
                                .font(.system(size: 80, weight: .bold))
                                .foregroundColor(.green)
                            
                            Text("Get ready!")
                                .font(.headline)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    )
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
            checkPositioning()
        }
    }
    
    private func stopPositioningCheck() {
        positioningTimer?.invalidate()
        positioningTimer = nil
    }
    
    private func checkPositioning() {
        guard let keypoints = motionService.poseKeypoints else {
            isPositioned = false
            return
        }
        
        // Check if head and shoulders are visible and properly positioned
        let hasHead = keypoints.nose != nil && keypoints.neck != nil
        let hasShoulders = keypoints.leftShoulder != nil && keypoints.rightShoulder != nil
        let hasArms = keypoints.leftElbow != nil && keypoints.rightElbow != nil
        
        // Check if user is centered in frame (roughly)
        let isCentered = checkIfCentered(keypoints: keypoints)
        
        // Check if user is at proper distance (not too close/far)
        let isProperDistance = checkDistance(keypoints: keypoints)
        
        isPositioned = hasHead && hasShoulders && hasArms && isCentered && isProperDistance
    }
    
    private func checkIfCentered(keypoints: SimplifiedPoseKeypoints) -> Bool {
        guard let nose = keypoints.nose,
              let leftShoulder = keypoints.leftShoulder,
              let rightShoulder = keypoints.rightShoulder else { return false }
        
        // Check if nose is roughly in center of frame
        let noseX = nose.x
        let isHorizontallyCentered = noseX > 0.3 && noseX < 0.7
        
        // Check if shoulders are roughly level
        let shoulderYDiff = abs(leftShoulder.y - rightShoulder.y)
        let areShouldersLevel = shoulderYDiff < 0.1
        
        return isHorizontallyCentered && areShouldersLevel
    }
    
    private func checkDistance(keypoints: SimplifiedPoseKeypoints) -> Bool {
        guard let leftShoulder = keypoints.leftShoulder,
              let rightShoulder = keypoints.rightShoulder else { return false }
        
        // Check shoulder width (should be reasonable - not too close or far)
        let shoulderDistance = abs(leftShoulder.x - rightShoulder.x)
        let isProperWidth = shoulderDistance > 0.15 && shoulderDistance < 0.6
        
        return isProperWidth
    }
    
    private func startCountdown() {
        positioningCountdown = 3
        showCountdown = true
        
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

#Preview {
    CameraPositioningGuide {
        print("Positioned and ready to start!")
    }
    .environmentObject(SimpleMotionService())
}
