import SwiftUI
import AVFoundation

struct GameInstructionsView: View {
    let gameType: GameType
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    @EnvironmentObject var motionService: SimpleMotionService
    @State private var preSurveyData = PreSurveyData(painLevel: 0, timestamp: Date(), exerciseReadiness: nil, previousExerciseHours: nil)
    @State private var painLevel: Int = 0
    @State private var canStartExercise = false
    @State private var speechSynthesizer = AVSpeechSynthesizer()
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 30) {
                // Header
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(gameType.color.opacity(0.2))
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: gameType.icon)
                            .font(.system(size: 40))
                            .foregroundColor(gameType.color)
                    }
                    
                    VStack(spacing: 8) {
                        Text(gameType.displayName)
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text(gameType.description)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                }
                
                // Instructions with Image + Audio
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("How to Play")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Button(action: readInstructionsAloud) {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Circle().fill(Color.blue.opacity(0.2)))
                        }
                        .tapTarget(60)
                    }
                    
                    // Game media (video placeholder until assets are provided) - removed for Constellations and Make Your Own
                    if gameType != .constellationMaker && gameType != .makeYourOwn {
                        HStack {
                            Spacer()
                            InstructionMediaView(gameType: gameType)
                                .frame(height: 220)
                            Spacer()
                        }
                    }
                    
                    // Exercise reference link
                    if let exerciseLink = getExerciseLink() {
                        Link(destination: URL(string: exerciseLink)!) {
                            HStack {
                                Image(systemName: "link")
                                    .font(.caption)
                                Text("View Reference")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.blue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    
                    // Bullet steps (no scrolling)
                    VStack(alignment: .leading, spacing: 10) {
                        let steps = getGameInstructions()
                        if steps.count > 0 { InstructionRow(icon: "1.circle.fill", text: steps[0]) }
                        if steps.count > 1 { InstructionRow(icon: "2.circle.fill", text: steps[1]) }
                        if steps.count > 2 { InstructionRow(icon: "3.circle.fill", text: steps[2]) }
                        if steps.count > 3 { InstructionRow(icon: "4.circle.fill", text: steps[3]) }
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.gray.opacity(0.1))
                )
                .padding(.horizontal)
                
                // Pre-Survey Section
                VStack(spacing: 20) {
                    Text("Before you start")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    VStack(spacing: 16) {
                        Text("Rate your current pain level")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                        
                        // Pain level slider
                        VStack(spacing: 12) {
                            Text("\(painLevel)")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundColor(.red)
                            
                            Slider(value: Binding(
                                get: { Double(painLevel) },
                                set: { painLevel = Int($0) }
                            ), in: 0...10, step: 1)
                            .accentColor(.red)
                            .onChange(of: painLevel) { _ in
                                updateCanStartExercise()
                            }
                            
                            HStack {
                                Text("No Pain")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Spacer()
                                Text("Severe Pain")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.1))
                        )
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.gray.opacity(0.1))
                )
                .padding(.horizontal)
                
                // Action Buttons
                VStack(spacing: 12) {
                    Button("Start Exercise") {
                        preSurveyData.painLevel = painLevel
                        // Set pain level in motion service for tracking
                        motionService.setPrePainLevel(painLevel)
                        navigationCoordinator.startGame(gameType: gameType, preSurveyData: preSurveyData)
                    }
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(canStartExercise ? .black : .gray)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canStartExercise ? .green : Color.gray.opacity(0.3))
                    .cornerRadius(12)
                    .disabled(!canStartExercise)
                    .tapTarget(60)
                }
                .padding(.top, 30)
                .padding(.bottom, 100) // Extra bottom padding for safe area
                }
                .padding()
            }
        }
        .onAppear {
            updateCanStartExercise()
            // NO ARKit/Camera pre-initialization - causes crashes
            // All motion tracking starts when game screen loads
        }
    }
    
    private func updateCanStartExercise() {
        canStartExercise = painLevel > 0
    }
    
    private func getGameInstructions() -> [String] {
        switch gameType {
        case .fruitSlicer:
            return [
                "Body Setup: Stand with feet shoulder-width apart. Relax shoulders and keep good posture.",
                "Phone Position: Hold phone firmly in your dominant hand, screen facing you, vertical orientation.",
                "Movement: Swing arm smoothly across your body in pendulum motions. Use your whole arm from the shoulder.",
                "Gameplay: Slice fruits as they appear. Avoid bombs (3 hits ends game). Smooth swings = better scores."
            ]
        
        case .followCircle:
            return [
                "Body Setup: Stand comfortably with feet shoulder-width apart. Keep core stable.",
                "Phone Position: Hold phone normally in dominant hand, screen facing you.",
                "Movement: Move your entire arm in large circular motions, like drawing big circles in the air.",
                "Gameplay: Keep green cursor inside the white guide circle. Complete full circles for reps. Larger circles = better ROM."
            ]
        
        case .wallClimbers:
            return [
                "Body Setup: Stand facing the camera, arms at your sides. Ensure full body is visible on screen.",
                "Phone Position: Prop phone vertically on a stable surface (table, stand, or chair). Front camera should see your entire upper body.",
                "Movement: Raise both arms straight up above your head, then lower smoothly back to sides. Keep movements controlled.",
                "Gameplay: Altitude increases as arms rise. Reach 1000m to win. No time limit - focus on full range motion."
            ]
        
        
        case .constellationMaker:
            return [
                "Body Setup: Stand facing the camera with your upper body centered on screen.",
                "Phone Position: Prop phone vertically. Front camera must clearly see your shoulders, arms, and hands.",
                "Movement: Raise and move your arm. A cyan circle tracks your wrist position precisely.",
                "Gameplay: Guide the circle to touch constellation dots in order. Cyan line shows when near target. Complete 3 patterns."
            ]
        
        case .balloonPop:
            return [
                "Body Setup: Stand facing the camera. Position yourself so your arm is fully visible when raised.",
                "Phone Position: Prop phone vertically. Front camera should see from your waist to above your head.",
                "Movement: Raise arm up and fully extend your elbow. A cyan pin at your wrist tip pops balloons.",
                "Gameplay: Move hand up to reach balloons at screen top. Full elbow extension gives maximum ROM. Pop them one at a time."
            ]
        
        case .fanOutFlame:
            return [
                "Body Setup: Stand with feet shoulder-width apart. Keep your core engaged for stability.",
                "Phone Position: Hold phone securely in dominant hand, screen facing you, vertical orientation.",
                "Movement: Swing arm horizontally left and right across your body, like fanning flames.",
                "Gameplay: Each complete swing (left or right) reduces the flame. Extinguish it to win. Smooth, consistent swings score best."
            ]
        
        case .makeYourOwn:
            return [
                "Body Setup: Stand tall with relaxed shoulders. Make sure you have space to move smoothly without twisting your torso.",
                "Phone Position: Camera mode—prop your phone so the front camera sees your upper body. Handheld mode—hold the phone securely with the screen facing you.",
                "Choose Mode: When the instructions screen appears, pick Camera or Handheld based on what the AI recommended (highlighted on screen).",
                "Session Flow: Follow the reminder badge and let the two-minute timer guide your pace. Focus on smooth, pain-free motion—no scores or meters to watch."
            ]
        
        
        }
    }
    
    private func getExerciseLink() -> String? {
        switch gameType {
        case .wallClimbers:
            return "https://healthy.kaiserpermanente.org/health-wellness/health-encyclopedia/he.rotator-cuff-exercises.ad1509"
        case .fanOutFlame:
            return "https://orthoinfo.aaos.org/en/recovery/rotator-cuff-and-shoulder-conditioning-program/"
        case .fruitSlicer:
            return "https://www.uptodate.com/contents/image?imageKey=PI%2F141285"
        case .followCircle:
            return "https://orthoinfo.aaos.org/en/recovery/rotator-cuff-and-shoulder-conditioning-program/"
        case .balloonPop:
            // Elbow extension reference (AAOS)
            return "https://orthoinfo.aaos.org/en/recovery/rotator-cuff-and-shoulder-conditioning-program/"
        case .constellationMaker:
            return nil // No link for this game
        
        default:
            return nil
        }
    }
    
    private func readInstructionsAloud() {
        let instructions = getGameInstructions()
        let fullInstructions = "Instructions for \(gameType.displayName). " + instructions.enumerated().map { "Step \($0.offset + 1): \($0.element)" }.joined(separator: ". ")
        
        let utterance = AVSpeechUtterance(string: fullInstructions)
        utterance.rate = 0.5
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        
        speechSynthesizer.speak(utterance)
    }
}

struct InstructionRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.green)
                .frame(width: 24)
            
            Text(text)
                .font(.body)
                .foregroundColor(.white)
        }
    }
}

#Preview {
    GameInstructionsView(gameType: .fruitSlicer)
}
