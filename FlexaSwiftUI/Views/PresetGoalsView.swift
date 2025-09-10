import SwiftUI

struct PresetGoalsView: View {
    @EnvironmentObject var goalsService: GoalsAndStreaksService
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPreset: GoalPreset?
    
    private let presets: [GoalPreset] = [
        GoalPreset(
            name: "Beginner Recovery",
            description: "Perfect for starting your rehabilitation journey",
            dailyReps: 10,
            weeklyMinutes: 60,
            romTarget: 45,
            icon: "figure.walk",
            color: .green
        ),
        GoalPreset(
            name: "Active Recovery",
            description: "For those making steady progress",
            dailyReps: 20,
            weeklyMinutes: 120,
            romTarget: 75,
            icon: "figure.strengthtraining.traditional",
            color: .blue
        ),
        GoalPreset(
            name: "Advanced Training",
            description: "Push your limits and achieve full mobility",
            dailyReps: 35,
            weeklyMinutes: 200,
            romTarget: 90,
            icon: "figure.gymnastics",
            color: .purple
        ),
        GoalPreset(
            name: "Maintenance Mode",
            description: "Maintain your progress with consistent practice",
            dailyReps: 15,
            weeklyMinutes: 90,
            romTarget: 60,
            icon: "heart.fill",
            color: .red
        ),
        GoalPreset(
            name: "Pain Management",
            description: "Gentle exercises focused on pain reduction",
            dailyReps: 8,
            weeklyMinutes: 45,
            romTarget: 30,
            icon: "leaf.fill",
            color: .orange
        ),
        GoalPreset(
            name: "Custom Goals",
            description: "Set your own personalized targets",
            dailyReps: 20,
            weeklyMinutes: 150,
            romTarget: 90,
            icon: "slider.horizontal.3",
            color: .gray
        )
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Text("Choose Your Goals")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text("Select a preset that matches your current fitness level and rehabilitation goals")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top)
                    
                    // Preset Cards
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        ForEach(presets, id: \.name) { preset in
                            PresetCard(
                                preset: preset,
                                isSelected: selectedPreset?.name == preset.name
                            ) {
                                selectedPreset = preset
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    // Selected Preset Details
                    if let selected = selectedPreset {
                        PresetDetailsView(preset: selected)
                            .transition(.opacity.combined(with: .scale))
                    }
                    
                    Spacer(minLength: 100)
                }
            }
            .background(Color.black)
            .navigationBarHidden(true)
        }
        .sheet(item: $selectedPreset) { preset in
            GoalCustomizationView(preset: preset) { finalGoals in
                Task {
                    try? await goalsService.updateGoals(finalGoals)
                    dismiss()
                }
            }
        }
    }
}

struct PresetCard: View {
    let preset: GoalPreset
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                // Icon
                Image(systemName: preset.icon)
                    .font(.system(size: 30))
                    .foregroundColor(preset.color)
                
                // Title
                Text(preset.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                // Quick stats
                VStack(spacing: 4) {
                    Text("\(preset.dailyReps) daily reps")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Text("\(preset.weeklyMinutes) min/week")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Text("\(preset.romTarget)° ROM")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .frame(height: 160)
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? preset.color.opacity(0.2) : Color.gray.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? preset.color : Color.clear, lineWidth: 2)
                    )
            )
        }
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.3), value: isSelected)
    }
}

struct PresetDetailsView: View {
    let preset: GoalPreset
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Selected: \(preset.name)")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Text(preset.description)
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 30) {
                StatBadge(title: "Daily Reps", value: "\(preset.dailyReps)", color: preset.color)
                StatBadge(title: "Weekly Minutes", value: "\(preset.weeklyMinutes)", color: preset.color)
                StatBadge(title: "ROM Target", value: "\(preset.romTarget)°", color: preset.color)
            }
            
            Button(action: {
                // This will trigger the sheet
            }) {
                Text("Customize & Apply")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(preset.color)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.1))
        )
        .padding(.horizontal)
    }
}

struct StatBadge: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
}

struct GoalCustomizationView: View {
    let preset: GoalPreset
    let onSave: (UserGoals) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var dailyReps: Int
    @State private var weeklyMinutes: Int
    @State private var romTarget: Int
    
    init(preset: GoalPreset, onSave: @escaping (UserGoals) -> Void) {
        self.preset = preset
        self.onSave = onSave
        self._dailyReps = State(initialValue: preset.dailyReps)
        self._weeklyMinutes = State(initialValue: preset.weeklyMinutes)
        self._romTarget = State(initialValue: preset.romTarget)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Customize \(preset.name)") {
                    HStack {
                        Text("Daily Reps Goal")
                        Spacer()
                        Stepper("\(dailyReps)", value: $dailyReps, in: 5...50, step: 5)
                    }
                    
                    HStack {
                        Text("Weekly Minutes")
                        Spacer()
                        Stepper("\(weeklyMinutes)", value: $weeklyMinutes, in: 30...300, step: 15)
                    }
                    
                    HStack {
                        Text("ROM Target")
                        Spacer()
                        Stepper("\(romTarget)°", value: $romTarget, in: 20...180, step: 5)
                    }
                }
                
                Section("Preview") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your personalized goals:")
                            .font(.headline)
                        
                        Text("• Complete \(dailyReps) reps daily")
                        Text("• Exercise \(weeklyMinutes) minutes per week")
                        Text("• Achieve \(romTarget)° range of motion")
                        Text("• Track progress with AI analysis")
                    }
                    .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Customize Goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        let goals = UserGoals(
                            dailyReps: dailyReps,
                            weeklyMinutes: weeklyMinutes,
                            targetROM: Double(romTarget)
                        )
                        onSave(goals)
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

struct GoalPreset: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let dailyReps: Int
    let weeklyMinutes: Int
    let romTarget: Int
    let icon: String
    let color: Color
}

#Preview {
    PresetGoalsView()
        .environmentObject(GoalsAndStreaksService())
}
