import SwiftUI

struct ProgressCard: View {
    @EnvironmentObject var goalsService: GoalsAndStreaksService
    
    var body: some View {
        NavigationLink(destination: EnhancedProgressViewFixed()) {
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("View My Progress")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        
                        Text(todaysSummary)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .lineLimit(2)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .foregroundColor(.blue)
                        .font(.title2)
                }
                
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.gray.opacity(0.1))
            )
            .padding(.horizontal)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var todaysSummary: String {
        let mainGoals = [
            GoalData(type: .sessions, targetValue: Double(goalsService.currentGoals.dailyReps), currentValue: Double(goalsService.todayProgress.gamesPlayed)),
            GoalData(type: .rom, targetValue: goalsService.currentGoals.targetROM, currentValue: goalsService.todayProgress.bestROM),
            GoalData(type: .smoothness, targetValue: goalsService.currentGoals.targetSmoothness, currentValue: goalsService.todayProgress.bestSmoothness)
        ].filter { $0.targetValue > 0 }
        let completedCount = mainGoals.filter { $0.isCompleted }.count
        let totalCount = mainGoals.count
        
        if completedCount == totalCount && totalCount > 0 {
            return "All goals completed today! 🎉"
        } else if completedCount > 0 {
            return "\(completedCount)/\(totalCount) goals completed"
        } else {
            return "Let's work towards your goals today"
        }
    }
}

#Preview {
    ProgressCard()
        .environmentObject(GoalsAndStreaksService())
        .background(Color.black)
}
