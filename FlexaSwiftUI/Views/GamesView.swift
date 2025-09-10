import SwiftUI

struct GamesView: View {
    @EnvironmentObject var firebaseService: FirebaseService
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var streaksService: GoalsAndStreaksService
    @EnvironmentObject var recommendationsEngine: RecommendationsEngine
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    
    var body: some View {
        ScrollView {
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
                        .padding(.horizontal)
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        ForEach(GameType.allCases.filter { $0 != .makeYourOwn }, id: \.self) { game in
                            ModernGameCard(game: game) {
                                navigationCoordinator.showInstructions(for: game)
                            }
                        }
                    }
                    .padding(.horizontal)
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
        Button(action: action) {
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
    case witchBrew = "witch_brew"
    case fanOutFlame = "fan_out_flame"
    case wallClimbers = "wall_climbers"
    case balloonPop = "balloon_pop"
    case constellationMaker = "constellation_maker"
    case makeYourOwn = "make_your_own"
    case testROM = "test_rom"
    
    var displayName: String {
        switch self {
        case .fruitSlicer: return "Fruit Slicer"
        case .witchBrew: return "Witch Brew"
        case .fanOutFlame: return "Fan Out the Flame"
        case .wallClimbers: return "Wall Climbers"
        case .balloonPop: return "Balloon Pop"
        case .constellationMaker: return "Create constellations with arm movements"
        case .makeYourOwn: return "Create your own custom exercise"
        case .testROM: return "Live angle tracker for ROM testing"
        }
    }
    
    var description: String {
        switch self {
        case .fruitSlicer: return "Slice fruits with arm movements"
        case .witchBrew: return "Stir witch brew with circular motions"
        case .fanOutFlame: return "Fan left and right to extinguish flames"
        case .wallClimbers: return "Climb virtual walls with wrist tracking"
        case .balloonPop: return "Pop balloons with elbow extensions"
        case .constellationMaker: return "Connect stars in correct sequence"
        case .makeYourOwn: return "Test ROM calculation with live angle tracking"
        case .testROM: return "Live angle tracker for ROM testing"
        }
    }
    
    var icon: String {
        switch self {
        case .fruitSlicer: return "scissors"
        case .witchBrew: return "flask"
        case .fanOutFlame: return "flame"
        case .wallClimbers: return "mountain.2"
        case .balloonPop: return "balloon.2"
        case .constellationMaker: return "star.fill"
        case .makeYourOwn: return "ruler"
        case .testROM: return "angle"
        }
    }
    
    var color: Color {
        switch self {
        case .fruitSlicer: return .orange
        case .witchBrew: return .purple
        case .fanOutFlame: return .red
        case .wallClimbers: return .brown
        case .balloonPop: return .pink
        case .constellationMaker: return .cyan
        case .makeYourOwn: return .green
        case .testROM: return .cyan
        }
    }
    
    var exerciseType: String {
        switch self {
        case .fruitSlicer: return "Handheld"
        case .witchBrew: return "Handheld"
        case .fanOutFlame: return "Handheld"
        case .wallClimbers: return "Camera"
        case .balloonPop: return "Camera"
        case .constellationMaker: return "Camera"
        case .makeYourOwn: return "Test"
        case .testROM: return "Camera"
        }
    }
    
    var instructionImageName: String {
        switch self {
        case .fruitSlicer: return "instr_fruit_slicer"
        case .witchBrew: return "instr_witch_brew"
        case .fanOutFlame: return "trapezius-strengthening (2)"
        case .wallClimbers: return "acp2794_368x240"  // or acp2792_368x240
        case .balloonPop: return "elbow-extension (1)"
        case .constellationMaker: return "instr_constellation"  // No image provided
        case .makeYourOwn: return "instr_custom"
        case .testROM: return "elbow-extension (1)"
        }
    }
    
    var id: String { rawValue }
}

#Preview {
    GamesView()
}
