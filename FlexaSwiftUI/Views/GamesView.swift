import SwiftUI
import Foundation

struct GamesView: View {
    @EnvironmentObject var backendService: BackendService
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var streaksService: GoalsAndStreaksService
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Fitness")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("Choose your rehabilitation exercise")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                
                // Recommended Exercises Section
                RecommendedExercisesSection()
                
                // All Games Grid
                VStack(alignment: .leading, spacing: 16) {
                    Text("All Exercises")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(Edge.Set.horizontal)
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        ForEach(GameType.allCases, id: \.self) { game in
                            ModernGameCard(game: game) {
                                navigationCoordinator.showInstructions(for: game)
                            }
                        }
                    }
                    .padding(Edge.Set.horizontal)
                }
                
                Spacer(minLength: 100)
            }
            .padding(.top)
        }
        .background(themeManager.backgroundColor)
    }
}

struct ModernGameCard: View {
    let game: GameType
    let action: () -> Void

    var body: some View {
        Button(action: {
            print("🔍 [ModernGameCard] TAPPED exercise card: '\(game.displayName)' (\(game.rawValue)) - type: \(game.exerciseType)")
            print("🔍 [ModernGameCard] Game details:")
            print("  - Description: \(game.description)")
            print("  - Icon: \(game.icon)")
            print("  - Color: \(game.color)")
            print("  - Instruction image: \(game.instructionImageName)")
            print("  - Action: navigating to \(game.rawValue) instructions")

            action()
        }) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(game.color.opacity(0.2))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: game.icon)
                        .font(.system(size: 28))
                        .foregroundColor(game.color)
                }
                
                VStack(spacing: 4) {
                    Text(game.displayName)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    
                    Text(game.exerciseType)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text("5-10 min")
                        .font(.caption2)
                }
                .foregroundColor(.gray)
            }
            .frame(height: 160)
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.gray.opacity(0.1))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}


enum GameType: String, CaseIterable, Identifiable {
    case fruitSlicer = "fruit_slicer"
    case followCircle = "follow_circle"
    case fanOutFlame = "fan_out_flame"
    case wallClimbers = "wall_climbers"
    case balloonPop = "balloon_pop"
    case constellationMaker = "constellation_maker"
    case makeYourOwn = "make_your_own"
    
    
    var displayName: String {
        switch self {
        case .fruitSlicer: return "Pendulum Swing"
        case .followCircle: return "Pendulum Circles"
        case .fanOutFlame: return "Scapular Retractions"
        case .wallClimbers: return "Wall Climb"
        case .balloonPop: return "Elbow Extension"
        case .constellationMaker: return "Arm Raises"
        case .makeYourOwn: return "Make Your Own"
        
        }
    }

    var legacyNames: [String] {
        switch self {
        case .fruitSlicer: return ["Fruit Slicer"]
        case .followCircle: return ["Follow the Circle", "Witch Brew"]
        case .fanOutFlame: return ["Fan Out the Flame", "Flap Wings"]
        case .wallClimbers: return ["Wall Climbers", "Mountain Climbers"]
        case .balloonPop: return ["Balloon Pop"]
        case .constellationMaker: return ["Constellations", "Constellation"]
        case .makeYourOwn: return ["Make Your Own"]
        }
    }
    
    var description: String {
        switch self {
        case .fruitSlicer: return "Hold phone flat and swing arm forward/back like a pendulum to slice fruit"
        case .followCircle: return "Hold phone and move arm in circles - cursor follows your hand movement"
        case .fanOutFlame: return "Hold phone and swing arm side-to-side to fan out the flame"
        case .wallClimbers: return "Prop phone to see yourself - raise and lower arms to climb higher"
        case .balloonPop: return "Prop phone to see yourself - raise arms overhead to pop balloons"
        case .constellationMaker: return "Prop phone to see yourself - connect constellation dots with your hand"
        case .makeYourOwn: return "Create custom exercises with your preferred duration and tracking mode"
        
        }
    }
    
    var icon: String {
        switch self {
        case .fruitSlicer: return "scissors"
        case .followCircle: return "circle.dotted"
        case .fanOutFlame: return "flame"
        case .wallClimbers: return "mountain.2"
        case .balloonPop: return "balloon.2"
        case .constellationMaker: return "star.fill"
        case .makeYourOwn: return "gearshape.fill"
        
        }
    }
    
    var color: Color {
        switch self {
        case .fruitSlicer: return .orange
        case .followCircle: return .blue
        case .fanOutFlame: return .red
        case .wallClimbers: return .brown
        case .balloonPop: return .pink
        case .constellationMaker: return .cyan
        case .makeYourOwn: return .blue
        
        }
    }
    
    var exerciseType: String {
        switch self {
        case .fruitSlicer: return "Handheld"
        case .followCircle: return "Handheld"
        case .fanOutFlame: return "Handheld"
        case .wallClimbers: return "Camera"
        case .balloonPop: return "Camera"
        case .constellationMaker: return "Camera"
        case .makeYourOwn: return "Both"
        
        }
    }
    
    var instructionImageName: String {
        switch self {
        case .fruitSlicer: return "instr_fruit_slicer"
        case .followCircle: return "instr_witch_brew"
        case .fanOutFlame: return "instr_flap_wings"  // Uses trapezius-strengthening image
        case .wallClimbers: return "instr_wall_climbers"
        case .balloonPop: return "instr_balloon_pop"
        case .constellationMaker: return "instr_constellation"  // No image - will show placeholder
        case .makeYourOwn: return "instr_make_your_own"  // No image - will show placeholder
        
        }
    }

    var instructionVideoResourceName: String {
        switch self {
        case .fruitSlicer: return "pendulum_swing"
        case .followCircle: return "pendulum_circles"
        case .fanOutFlame: return "scapular_retractions"
        case .wallClimbers: return "wall_climb"
        case .balloonPop: return "elbow_extension"
        case .constellationMaker: return "arm_raises"
        case .makeYourOwn: return "make_your_own"
        }
    }

    var instructionVideoURL: URL? {
        Bundle.main.url(forResource: instructionVideoResourceName, withExtension: "mp4")
    }

    func matchesDisplayName(_ name: String) -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == displayName.lowercased() { return true }
        return legacyNames.map { $0.lowercased() }.contains(normalized)
    }

    var allDisplayNames: [String] {
        [displayName] + legacyNames
    }

    static func fromDisplayName(_ name: String) -> GameType? {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return GameType.allCases.first { type in
            type.matchesDisplayName(normalized)
                || type.rawValue == normalized
                || type.rawValue.replacingOccurrences(of: "_", with: " ") == normalized
                || type.legacyNames.map { $0.lowercased().replacingOccurrences(of: "_", with: " ") }.contains(normalized)
        }
    }

    var aiDescription: String {
        switch self {
        case .fruitSlicer:
            return "A handheld pendulum swing exercise using gentle forward and backward arm motions to slice virtual fruit. Emphasizes rhythmic pendulum swings and smooth pacing."
        case .followCircle:
            return "A handheld pendulum-circle drill where patients trace circular paths in the air. Focuses on smooth, continuous circular motion and control."
        case .fanOutFlame:
            return "A handheld scapular retraction exercise where patients sweep side-to-side to fan out a flame. Encourages even scapular engagement and rhythmic tempo."
        case .wallClimbers:
            return "A camera-based wall climb reaching drill that guides the arms overhead in alternating patterns. Builds shoulder elevation endurance and coordination."
        case .balloonPop:
            return "A camera-based elbow extension reaching task where patients pop balloons overhead. Reinforces full elbow extension and controlled lowering."
        case .constellationMaker:
            return "A camera-based arm raise sequence guiding patients to multiple targets. Promotes multi-directional shoulder raises and sustained control."
        case .makeYourOwn:
            return "A customizable exercise mode where patients configure their own motion tracking routines and durations."
        }
    }
    
    var id: String { rawValue }
}

#Preview {
    GamesView()
}
