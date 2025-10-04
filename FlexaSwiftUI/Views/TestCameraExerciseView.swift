import SwiftUI
import AVFoundation

struct TestCameraExerciseView: View {
    @EnvironmentObject var motionService: SimpleMotionService
    @State private var currentAngle: Double = 0
    @State private var currentROM: Double = 0
    @State private var repCount: Int = 0
    @State private var isTracking = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Camera Preview Background
                CameraPreviewView(session: motionService.captureSession)
                    .ignoresSafeArea()
                
                // Skeleton overlay removed - no longer needed
                
                // Angle Display Overlay
                VStack {
                HStack {
                    Spacer()
                    AngleDisplayPanel(
                        currentAngle: currentAngle,
                        currentROM: currentROM,
                        repCount: repCount
                    )
                    .padding()
                }
                Spacer()
                
                // Control Panel
                HStack(spacing: 20) {
                    Button(action: toggleTracking) {
                        Text(isTracking ? "Stop" : "Start")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 12)
                            .background(isTracking ? Color.red : Color.green)
                            .cornerRadius(25)
                    }
                    
                    Button("Reset") {
                        resetTracking()
                    }
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .cornerRadius(25)
                }
                .padding(.bottom, 50)
                }
            }
        }
        .navigationTitle("Camera Exercise Test")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            startTracking()
        }
        .onDisappear {
            stopTracking()
        }
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            updateAngleData()
        }
    }
    
    private func toggleTracking() {
        if isTracking {
            stopTracking()
        } else {
            startTracking()
        }
    }
    
    private func startTracking() {
        motionService.startGameSession(gameType: .camera)
        isTracking = true
    }
    
    private func stopTracking() {
        motionService.stopSession()
        isTracking = false
    }
    
    private func resetTracking() {
        motionService.stopSession()
        currentAngle = 0
        currentROM = 0
        repCount = 0
    }
    
    private func updateAngleData() {
        if let keypoints = motionService.poseKeypoints,
           let romAngle = keypoints.getBestArmpitROM() {
            currentAngle = romAngle
            currentROM = motionService.currentROM
            repCount = motionService.currentReps
        }
    }
}


// Removed duplicate SkeletonOverlayView - using the one from SkeletonOverlayView.swift

struct AngleDisplayPanel: View {
    let currentAngle: Double
    let currentROM: Double
    let repCount: Int
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack {
                Text("Angle:")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("\(Int(currentAngle))°")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.yellow)
            }
            
            HStack {
                Text("ROM:")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("\(Int(currentROM))°")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
            }
            
            HStack {
                Text("Reps:")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("\(repCount)")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(Color.black.opacity(0.7))
        .cornerRadius(12)
    }
}

// Vision framework extension removed - using Apple Vision pose landmarks instead
