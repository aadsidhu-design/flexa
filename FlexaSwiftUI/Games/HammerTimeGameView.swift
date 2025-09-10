import SwiftUI
import CoreMotion

struct HammerTimeGameView: View {
    @Binding var score: Int
    @Binding var reps: Int
    @Binding var rom: Double
    @Binding var isActive: Bool
    
    @StateObject private var motionManager = MotionTrackingService()
    @State private var hammerPosition: CGFloat = 0 // -1 to 1 (left to right)
    @State private var leftNailProgress: CGFloat = 0 // 0 to 1
    @State private var rightNailProgress: CGFloat = 0 // 0 to 1
    @State private var gameTimer: Timer?
    @State private var isGameComplete = false
    @State private var hammerAnimation: Bool = false
    
    private let nailsNeeded = 10 // Number of hits per nail to complete
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Dark background
                Color.black
                    .ignoresSafeArea()
                
                // Left wall with painting
                VStack {
                    Spacer()
                    HStack {
                        WallWithPainting(
                            nailProgress: leftNailProgress,
                            isLeft: true
                        )
                        .frame(width: 120, height: 200)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.leading, 40)
                
                // Right wall with painting
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        WallWithPainting(
                            nailProgress: rightNailProgress,
                            isLeft: false
                        )
                        .frame(width: 120, height: 200)
                    }
                    Spacer()
                }
                .padding(.trailing, 40)
                
                // Hammer in center
                VStack {
                    Spacer()
                    HammerView(position: hammerPosition, isAnimating: hammerAnimation)
                        .frame(width: 80, height: 40)
                    Spacer()
                }
                
                // Progress indicators
                VStack {
                    HStack {
                        VStack {
                            Text("Left Nail")
                                .font(.caption)
                                .foregroundColor(.white)
                            SwiftUI.ProgressView(value: leftNailProgress)
                                .progressViewStyle(LinearProgressViewStyle(tint: .green))
                                .frame(width: 80)
                        }
                        
                        Spacer()
                        
                        VStack {
                            Text("Right Nail")
                                .font(.caption)
                                .foregroundColor(.white)
                            SwiftUI.ProgressView(value: rightNailProgress)
                                .progressViewStyle(LinearProgressViewStyle(tint: .green))
                                .frame(width: 80)
                        }
                    }
                    .padding(.horizontal)
                    Spacer()
                }
                .padding(.top, 50)
                
                // Game complete overlay
                if isGameComplete {
                    Color.black.opacity(0.7)
                        .ignoresSafeArea()
                    
                    VStack {
                        Text("🔨")
                            .font(.system(size: 80))
                        Text("Job Complete!")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        Text("Both nails hammered in!")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
                    .scaleEffect(isGameComplete ? 1.0 : 0.5)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isGameComplete)
                }
            }
        }
        .onAppear {
            setupGame()
        }
        .onDisappear {
            cleanup()
        }
        .onChange(of: isActive) { _, active in
            if active {
                setupGame()
            } else {
                cleanup()
            }
        }
    }
    
    private func setupGame() {
        guard isActive else { return }
        
        // Reset game state
        leftNailProgress = 0
        rightNailProgress = 0
        isGameComplete = false
        hammerPosition = 0
        
        // Start motion tracking
        motionManager.startTracking()
        
        // Start game loop
        gameTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { _ in
            updateGame()
        }
    }
    
    private func cleanup() {
        gameTimer?.invalidate()
        motionManager.stopTracking()
    }
    
    private func updateGame() {
        guard isActive && !isGameComplete else { return }
        
        // Get motion data (roll for left/right movement when phone is landscape-ish)
        let rollAngle = motionManager.getCurrentRotationAngle() * .pi / 180 // Convert back to radians
        
        // Map roll to hammer position (-1 to 1)
        let normalizedRoll = max(-1.0, min(1.0, rollAngle / 0.8)) // Limit range
        hammerPosition = normalizedRoll
        
        // Update ROM based on motion
        rom = abs(rollAngle) * 180 / .pi
        
        // Check for hammer hits
        checkHammerHits()
        
        // Check game completion
        if leftNailProgress >= 1.0 && rightNailProgress >= 1.0 && !isGameComplete {
            completeGame()
        }
    }
    
    private func checkHammerHits() {
        let hitThreshold: CGFloat = 0.6 // How far hammer needs to move to hit
        
        // Check left nail hit
        if hammerPosition < -hitThreshold && leftNailProgress < 1.0 {
            hitNail(isLeft: true)
        }
        
        // Check right nail hit
        if hammerPosition > hitThreshold && rightNailProgress < 1.0 {
            hitNail(isLeft: false)
        }
    }
    
    private func hitNail(isLeft: Bool) {
        let progressIncrement: CGFloat = 1.0 / CGFloat(nailsNeeded)
        
        if isLeft {
            leftNailProgress = min(1.0, leftNailProgress + progressIncrement)
        } else {
            rightNailProgress = min(1.0, rightNailProgress + progressIncrement)
        }
        
        // Update score and reps
        score += 10
        reps += 1
        
        // Trigger hammer animation
        hammerAnimation = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            hammerAnimation = false
        }
    }
    
    private func completeGame() {
        isGameComplete = true
        
        // Stop game after showing completion
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            isActive = false
        }
    }
}

struct HammerView: View {
    let position: CGFloat // -1 to 1
    let isAnimating: Bool
    
    var body: some View {
        ZStack {
            // Hammer handle
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.brown)
                .frame(width: 8, height: 60)
            
            // Hammer heads (double-sided)
            HStack(spacing: 0) {
                // Left head
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray)
                    .frame(width: 20, height: 16)
                
                // Center (handle connection)
                Rectangle()
                    .fill(Color.brown)
                    .frame(width: 8, height: 16)
                
                // Right head
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray)
                    .frame(width: 20, height: 16)
            }
        }
        .rotationEffect(.degrees(Double(position) * 45.0)) // Tilt based on position
        .scaleEffect(isAnimating ? 1.2 : 1.0)
        .animation(.easeOut(duration: 0.1), value: isAnimating)
        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 2)
    }
}

struct WallWithPainting: View {
    let nailProgress: CGFloat
    let isLeft: Bool
    
    var body: some View {
        ZStack {
            // Wall
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray, lineWidth: 2)
                )
            
            // Painting
            VStack {
                // Painting frame
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.brown)
                    .frame(width: 80, height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.blue.opacity(0.7))
                            .padding(8)
                            .overlay(
                                Text("🖼️")
                                    .font(.system(size: 30))
                            )
                    )
                
                Spacer().frame(height: 20)
            }
            
            // Nail
            VStack {
                Circle()
                    .fill(Color.yellow)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 8, height: 8)
                            .offset(y: nailProgress * 6) // Nail gets pushed in
                    )
                    .shadow(color: .black.opacity(0.3), radius: 1)
                
                Spacer()
            }
            .padding(.top, 10)
        }
    }
}

#Preview {
    HammerTimeGameView(
        score: .constant(0),
        reps: .constant(0),
        rom: .constant(0),
        isActive: .constant(true)
    )
}
