import SwiftUI

struct TestROMExerciseView: View {
    @EnvironmentObject var motionService: SimpleMotionService
    @State private var isTracking = false
    @State private var currentAngle: Double = 0
    @State private var maxAngle: Double = 0
    @State private var minAngle: Double = 180
    @State private var romRange: Double = 0
    @State private var repCount: Int = 0
    @State private var startTime: Date?

    private let timer = Timer.publish(every: 0.033, on: .main, in: .common).autoconnect() // 30 FPS

    var body: some View {
        ZStack {
            // Background
            Color.black.edgesIgnoringSafeArea(.all)

            VStack(spacing: 30) {
                // Title
                Text("ROM Test Exercise")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                // Live Angle Display
                VStack(spacing: 20) {
                    Text("Live Angle (Universal3D)")
                        .font(.title2)
                        .foregroundColor(.white)

                    Text("\(String(format: "%.1f", currentAngle))°")
                        .font(.system(size: 80, weight: .bold))
                        .foregroundColor(isTracking ? .green : .blue)
                        .padding()
                        .background(
                            Circle()
                                .fill((isTracking ? Color.green : Color.blue).opacity(0.2))
                                .frame(width: 200, height: 200)
                        )

                    // ROM Stats
                    if isTracking {
                        VStack(spacing: 10) {
                            Text("ROM Range: \(String(format: "%.1f", romRange))°")
                                .font(.title3)
                                .foregroundColor(.green)

                            HStack(spacing: 30) {
                                VStack {
                                    Text("Min")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                    Text("\(String(format: "%.1f", minAngle))°")
                                        .font(.headline)
                                        .foregroundColor(.red)
                                }

                                VStack {
                                    Text("Max")
                                        .font(.headline)
                                        .foregroundColor(.white.opacity(0.7))
                                    Text("\(String(format: "%.1f", maxAngle))°")
                                        .font(.headline)
                                        .foregroundColor(.green)
                                }
                                
                                VStack {
                                    Text("Reps")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                    Text("\(repCount)")
                                        .font(.headline)
                                        .foregroundColor(.yellow)
                                }
                            }
                        }
                    }
                }

                // Start/Stop ROM Button
                Button(action: {
                    if !isTracking {
                        startROMTracking()
                    } else {
                        stopROMTracking()
                    }
                }) {
                    Text(isTracking ? "STOP ROM" : "START ROM")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 25)
                                .fill(isTracking ? Color.red : Color.green)
                        )
                }

                // Instructions
                if !isTracking {
                    VStack(spacing: 15) {
                        Text("Universal3D ROM Test")
                            .font(.headline)
                            .foregroundColor(.white)

                        Text("• Uses Universal3D engine")
                        Text("• ARKit + IMU fallback")
                        Text("• Same as handheld games")
                        Text("• Press START ROM to begin")
                    }
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                }

                Spacer()

                // Finish Exercise Button
                Button(action: {
                    finishExercise()
                }) {
                    Text("FINISH EXERCISE")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 15)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.orange)
                        )
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 50)
        }
        .onReceive(timer) { _ in
            updateROMData()
        }
        .onDisappear {
            stopROMTracking()
        }
        .navigationTitle("ROM Test")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func startROMTracking() {
        isTracking = true
        startTime = Date()
        currentAngle = 0
        maxAngle = 0
        minAngle = 180
        romRange = 0
        repCount = 0
        
        // Start Universal3D ROM tracking
        motionService.startGameSession(gameType: .testROM)
        // TestROM uses automatic 3D tracking
        
        print("🏁 [ROM Test] Started ARKit 3D tracking")
    }

    private func stopROMTracking() {
        isTracking = false
        motionService.stopSession() // Properly stop all services
        print("⏹️ [ROM Test] Stopped Universal3D tracking")
        print("📊 [ROM Test] ROM Range: \(String(format: "%.1f", romRange))° (Min: \(String(format: "%.1f", minAngle))° - Max: \(String(format: "%.1f", maxAngle))°)")
        print("🔢 [ROM Test] Reps: \(repCount)")
    }

    private func finishExercise() {
        if isTracking {
            stopROMTracking()
        }
        
        // Just close the view
        // In a real app, you might navigate back or show results
        print("✅ [ROM Test] Exercise finished")
    }

    private func updateROMData() {
        guard isTracking else { return }

        // Get data from motion service
        currentAngle = motionService.currentROM
        repCount = motionService.currentReps

        // Update min/max
        if currentAngle > 0 {
            minAngle = min(minAngle, currentAngle)
            maxAngle = max(maxAngle, currentAngle)
        }

        // Calculate ROM range
        romRange = maxAngle - minAngle
        
        // Use service's max ROM if higher
        if motionService.maxROM > maxAngle {
            maxAngle = motionService.maxROM
        }
    }
}

#Preview {
    TestROMExerciseView()
        .environmentObject(SimpleMotionService.shared)
}
