import SwiftUI

struct GoalsSection: View {
    @EnvironmentObject var goalsService: GoalsAndStreaksService
    @State private var showingGoalEditor = false
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Your Goals")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: {
                    showingGoalEditor = true
                }) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                Button(action: {
                    showingGoalEditor = true
                }) {
                    GoalCard(
                        title: "Daily Reps",
                        current: goalsService.todayProgress.repsCompleted,
                        target: goalsService.currentGoals.dailyReps,
                        icon: "repeat.circle.fill",
                        color: .blue
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    showingGoalEditor = true
                }) {
                    GoalCard(
                        title: "Weekly Minutes",
                        current: goalsService.weeklyProgress.minutesCompleted,
                        target: goalsService.currentGoals.weeklyMinutes,
                        icon: "clock.fill",
                        color: .orange
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    showingGoalEditor = true
                }) {
                    GoalCard(
                        title: "ROM Target",
                        current: Int(goalsService.todayProgress.bestROM),
                        target: Int(goalsService.currentGoals.targetROM),
                        icon: "arrow.up.circle.fill",
                        color: .purple
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    showingGoalEditor = true
                }) {
                    GoalCard(
                        title: "Weekly Days",
                        current: goalsService.weeklyProgress.daysActive,
                        target: 7,
                        icon: "calendar.circle.fill",
                        color: .green
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal)
        }
        .fullScreenCover(isPresented: $showingGoalEditor) {
            GoalEditorView(isPresented: $showingGoalEditor)
                .environmentObject(goalsService)
        }
    }
}

struct GoalCard: View {
    let title: String
    let current: Int
    let target: Int
    let icon: String
    let color: Color
    
    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(Double(current) / Double(target), 1.0)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                
                Spacer()
                
                Text("\(current)/\(target)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.gray)
            }
            
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            SwiftUI.ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle(tint: color))
                .scaleEffect(x: 1, y: 2, anchor: .center)
            
            Text("\(Int(progress * 100))%")
                .font(.caption2)
                .foregroundColor(progress >= 1.0 ? color : .gray)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.1))
        )
    }
}

// GoalEditorView removed - using the one in FitbitStyleGoalsView.swift instead

#Preview {
    GoalsSection()
        .environmentObject(GoalsAndStreaksService())
}
