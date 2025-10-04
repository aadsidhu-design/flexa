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
        }
    }
    
    private func updateCanStartExercise() {
        canStartExercise = painLevel > 0
    }
    
    private func getGameInstructions() -> [String] {
        switch gameType {
        case .fruitSlicer:
            return [
                "📱 Grip phone FIRMLY in dominant hand with screen facing you (vertical orientation)",
                "💪 Swing arm ACROSS your body in smooth pendulum motions - shoulder rotation exercise",
                "🎯 Slice fruits as they appear on screen - AVOID bombs!",
                "⭐ Smooth, controlled swings score best. Game ends after 3 bomb hits. Go for maximum ROM!"
            ]
        
        case .followCircle:
            return [
                "📱 Hold phone normally in dominant hand (screen facing you, vertical grip)",
                "🔄 Move YOUR ENTIRE ARM in LARGE CIRCULAR MOTIONS like drawing big circles in the air",
                "🎯 Green cursor circle follows your hand - keep it INSIDE the white guide circle",
                "⭐ Complete FULL circles (350°+) for reps. Larger, smoother circles = better ROM & score!"
            ]
        
        case .wallClimbers:
            return [
                "📱 PROP phone VERTICALLY on table/stand/chair so camera sees YOUR FULL BODY",
                "🙆 Raise BOTH arms HIGH above your head, then lower smoothly to sides - controlled motion",
                "🏔️ Altitude increases as arms go up, decreases as they come down. Goal: reach 1000m!",
                "⭐ NO TIME LIMIT - take your time. Smooth, full range arm raises climb faster!"
            ]
        
        
        case .constellationMaker:
            return [
                "📱 PROP phone VERTICALLY with front camera clearly viewing your upper body",
                "✋ RAISE/MOVE your arm - a CYAN CIRCLE precisely tracks your wrist position",
                "⭐ Guide circle to touch constellation dots IN ORDER (cyan line appears when near target)",
                "🎯 Complete 3 constellation patterns. NO TIMER - focus on smooth, accurate movements!"
            ]
        
        case .balloonPop:
            return [
                "📱 PROP phone VERTICALLY so front camera sees your FULL UPPER BODY (arm fully visible)",
                "💪 RAISE arm UP and fully EXTEND ELBOW - cyan pin at wrist tip pops balloons",
                "🎈 Pin follows your wrist exactly - move hand UP to reach balloons at screen top",
                "⭐ Full elbow extension = maximum ROM! Pop balloons one at a time by reaching high."
            ]
        
        case .fanOutFlame:
            return [
                "📱 Hold phone SECURELY in dominant hand (normal vertical grip, screen facing you)",
                "💨 SWING arm HORIZONTALLY left and right across your body - like fanning flames",
                "🔥 Each complete swing (left OR right) reduces flame - extinguish it to win!",
                "⭐ Both short and long swings count. Smooth, consistent motion = better smoothness score!"
            ]
        
        case .makeYourOwn:
            return [
                "📱 First, choose CAMERA mode (prop phone vertically) OR HANDHELD mode (hold phone)",
                "🎮 CAMERA: tracks shoulder/elbow joints. HANDHELD: tracks device motion in hand",
                "📋 Follow the specific on-screen instructions for your chosen exercise and mode",
                "⭐ Fully customizable! Adjust duration and movement range to match your therapy needs."
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
