import SwiftUI

struct RecommendedExercisesSection: View {
    @EnvironmentObject var goalsService: GoalsAndStreaksService
    @State private var selectedGame: GameType?
    @State private var showingGameInstructions = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Try These Exercises")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(recommendedGames, id: \.self) { game in
                        RecommendedGameCard(game: game) {
                            selectedGame = game
                            showingGameInstructions = true
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .fullScreenCover(isPresented: $showingGameInstructions) {
            if let game = selectedGame {
                GameInstructionsView(gameType: game)
            }
        }
    }
    
    private var recommendedGames: [GameType] {
        let allGames = GameType.allCases.filter { $0 != .makeYourOwn }

        let todaySessions = LocalDataManager.shared.getStoredSessions().filter { session in
            Calendar.current.isDateInToday(session.timestamp)
        }

        let playedToday = Set(todaySessions.compactMap { GameType.fromDisplayName($0.exerciseType) })

        let notPlayedToday = allGames.filter { !playedToday.contains($0) }

        return Array(notPlayedToday.prefix(3))
    }
}

struct RecommendedGameCard: View {
    let game: GameType
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                // Game icon with recommendation badge
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [gameColor.opacity(0.3), gameColor.opacity(0.1)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 80)
                    
                    Image(systemName: gameIcon)
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(gameColor)
                    
                    // Recommendation badge
                    VStack {
                        HStack {
                            Spacer()
                            Text("★")
                                .font(.caption)
                                .foregroundColor(.yellow)
                                .padding(4)
                                .background(Circle().fill(Color.black.opacity(0.3)))
                        }
                        Spacer()
                    }
                    .frame(width: 120, height: 80)
                }
                
                VStack(spacing: 4) {
                    Text(game.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    
                    Text("Not played today")
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .frame(width: 120)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var gameIcon: String {
        switch game {
        case .fruitSlicer: return "scope"
        case .balloonPop: return "figure.arms.open"
        case .wallClimbers: return "figure.climbing"
        case .constellationMaker: return "star.circle"
        case .fanOutFlame: return "flame"
        case .followCircle: return "circle.dotted"
        case .makeYourOwn: return "gamecontroller"
        }
    }
    
    private var gameColor: Color {
        game.color
    }
}

#Preview {
    RecommendedExercisesSection()
        .environmentObject(GoalsAndStreaksService())
        .background(Color.black)
}