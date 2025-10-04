import SwiftUI

struct GoalEditorView: View {
    @EnvironmentObject var goalsService: GoalsAndStreaksService
    @Binding var isPresented: Bool
    
    @State private var dailyReps: Int = 10
    @State private var weeklyMinutes: Int = 150
    @State private var targetROM: Double = 120.0
    @State private var isLoading: Bool = false
    @State private var showingError: Bool = false
    @State private var errorMessage: String = ""
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if isLoading {
                    VStack {
                        ProgressView()
                            .scaleEffect(1.5)
                            .progressViewStyle(CircularProgressViewStyle(tint: .green))
                        Text("Loading goals...")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .padding(.top)
                    }
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 24) {
                            // Header
                            VStack(spacing: 8) {
                                Text("Customize Your Goals")
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                
                                Text("Set targets that challenge and motivate you")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.top, 20)
                            
                            // Goals Cards
                            VStack(spacing: 16) {
                                GoalEditCard(
                                    title: "Daily Reps",
                                    subtitle: "Number of exercise repetitions per day",
                                    icon: "repeat.circle.fill",
                                    color: .blue,
                                    value: $dailyReps,
                                    range: 5...50,
                                    unit: "reps"
                                )
                                
                                GoalEditCard(
                                    title: "Weekly Minutes",
                                    subtitle: "Exercise time per week",
                                    icon: "clock.fill",
                                    color: .orange,
                                    value: $weeklyMinutes,
                                    range: 30...300,
                                    unit: "min"
                                )
                                
                                ROMGoalEditCard(
                                    title: "ROM Target",
                                    subtitle: "Range of motion goal",
                                    icon: "arrow.up.circle.fill",
                                    color: .purple,
                                    value: $targetROM,
                                    range: 60.0...180.0,
                                    unit: "°"
                                )
                            }
                            
                            Spacer(minLength: 100)
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
            .navigationTitle("Goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundColor(.gray)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveGoals()
                    }
                    .foregroundColor(.green)
                    .fontWeight(.semibold)
                    .disabled(isLoading)
                }
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            loadCurrentGoals()
        }
    }
    
    private func loadCurrentGoals() {
        // Load instantly from already available data - no delays needed
        dailyReps = goalsService.currentGoals.dailyReps
        weeklyMinutes = goalsService.currentGoals.weeklyMinutes
        targetROM = goalsService.currentGoals.targetROM
        isLoading = false
    }
    
    private func saveGoals() {
        let newGoals = UserGoals(
            dailyReps: dailyReps,
            weeklyMinutes: weeklyMinutes,
            targetROM: targetROM,
            preferredGames: goalsService.currentGoals.preferredGames
        )
        
        // Save instantly - no artificial delays
        goalsService.currentGoals = newGoals
        isPresented = false
        
        // Haptic feedback for success
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }
}

struct GoalEditCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Text("\(value) \(unit)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(color)
            }
            
            Slider(value: Binding(
                get: { Double(value) },
                set: { value = Int($0) }
            ), in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
            .accentColor(color)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

struct ROMGoalEditCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Text("\(Int(value))\(unit)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(color)
            }
            
            Slider(value: $value, in: range, step: 5.0)
                .accentColor(color)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

#Preview {
    GoalEditorView(isPresented: .constant(true))
        .environmentObject(GoalsAndStreaksService())
}
