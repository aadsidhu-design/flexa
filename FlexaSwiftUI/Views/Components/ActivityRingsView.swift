import SwiftUI

struct ActivityRingsView: View {
    @EnvironmentObject var goalsService: GoalsAndStreaksService
    @State private var showingGoalEditor = false
    @State private var selectedGoalType: GoalType?
    
    private let ringSize: CGFloat = 100
    private let strokeWidth: CGFloat = 12
    
    var mainGoals: [GoalData] {
        // Convert GoalsAndStreaksService data to GoalData format for ActivityRings
        [
            GoalData(type: .sessions, targetValue: Double(goalsService.currentGoals.dailyReps), currentValue: Double(goalsService.todayProgress.gamesPlayed)),
            GoalData(type: .rom, targetValue: goalsService.currentGoals.targetROM, currentValue: goalsService.todayProgress.bestROM),
            // Smoothness uses SPARC 0–100 scale in UI; targets are stored 0–1 so convert to 0–100
            GoalData(type: .smoothness, targetValue: goalsService.currentGoals.targetSmoothness * 100.0, currentValue: goalsService.todayProgress.bestSmoothness)
        ].filter { $0.targetValue > 0 }
    }
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Today's Goals")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Apple Fitness–inspired pyramid of rings (1 over 2)
            VStack(spacing: 16) {
                if mainGoals.indices.contains(0) {
                    ZStack {
                        ActivityRing(
                            goal: mainGoals[0],
                            size: 180,
                            strokeWidth: 20,
                            onTap: { selectedGoalType = mainGoals[0].type; showingGoalEditor = true }
                        )
                        RingCenterLabel(goal: mainGoals[0])
                    }
                }
                HStack(spacing: 20) {
                    if mainGoals.indices.contains(1) {
                        ZStack {
                            ActivityRing(
                                goal: mainGoals[1],
                                size: 130,
                                strokeWidth: 18,
                                onTap: { selectedGoalType = mainGoals[1].type; showingGoalEditor = true }
                            )
                            RingCenterLabel(goal: mainGoals[1])
                        }
                    }
                    if mainGoals.indices.contains(2) {
                        ZStack {
                            ActivityRing(
                                goal: mainGoals[2],
                                size: 130,
                                strokeWidth: 18,
                                onTap: { selectedGoalType = mainGoals[2].type; showingGoalEditor = true }
                            )
                            RingCenterLabel(goal: mainGoals[2])
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            
        }
        .padding(.horizontal)
        .sheet(item: Binding<GoalType?>(
            get: { selectedGoalType },
            set: { _ in selectedGoalType = nil }
        )) { goalType in
            GoalEditSheet(goalType: goalType)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .onAppear {
                    print("🎯 [SHEET] Goal editor opened for \(goalType.displayName)")
                }
                .onDisappear {
                    selectedGoalType = nil
                    showingGoalEditor = false
                }
        }
    }
}

struct ActivityRing: View {
    let goal: GoalData
    let size: CGFloat
    let strokeWidth: CGFloat
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        ZStack {
            // Invisible full circle for complete tap area - INSTANT response
            Circle()
                .fill(Color.clear)
                .frame(width: size, height: size)
                .contentShape(Circle()) // Ensures entire circle area is tappable
            
            // Background ring - Apple style with darker opacity
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: strokeWidth)
                .frame(width: size, height: size)
            
            // Progress ring - Apple Fitness colors with proper coverage
            Circle()
                .trim(from: 0, to: min(max(goal.progress, 0.0), 1.0))
                .stroke(
                    appleRingColor(for: goal.type),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.15), value: goal.progress)
                .overlay(
                    // Full blue coverage when complete
                    Circle()
                        .trim(from: 0, to: goal.isCompleted ? 1.0 : 0)
                        .stroke(
                            appleRingColor(for: goal.type).opacity(0.3),
                            style: StrokeStyle(lineWidth: strokeWidth + 2, lineCap: .round)
                        )
                        .frame(width: size + 4, height: size + 4)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.3), value: goal.isCompleted)
                )
            
            // Completion indicator (static to avoid lag)
            if goal.isCompleted {
                Circle()
                    .stroke(appleRingColor(for: goal.type).opacity(0.3), lineWidth: strokeWidth + 4)
                    .frame(width: size + 8, height: size + 8)
            }
        }
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .onTapGesture {
            // INSTANT haptic feedback and response
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.prepare() // Pre-prepare for instant response
            impact.impactOccurred()
            
            // Execute immediately without any async wrapping
            onTap()
        }
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
    
    private func appleRingColor(for goalType: GoalType) -> Color {
        switch goalType {
        case .sessions: return Color(red: 1.0, green: 0.067, blue: 0.31) // Apple Move Red
        case .rom: return Color(red: 0.196, green: 0.843, blue: 0.294) // Apple Exercise Green  
        case .smoothness: return Color(red: 0.0, green: 0.722, blue: 1.0) // Apple Stand Blue
        default: return goalType.color
        }
    }
}

struct RingCenterLabel: View {
    let goal: GoalData
    var body: some View {
        VStack(spacing: 4) {
            Text(goal.type == .rom ? "ROM" : goal.type == .smoothness ? "Smoothness" : goal.type.displayName)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            // Fix progress display accuracy
            Text(formattedProgress)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
        }
        // Let taps fall through to the underlying ring view
        .allowsHitTesting(false)
    }
    
    private var formattedProgress: String {
        let current = goal.currentValue
        let target = goal.targetValue
        
        switch goal.type {
        case .smoothness:
            // Values are already on 0–100 scale
            return "\(Int(current.rounded()))/\(Int(target.rounded()))"
        case .rom:
            // Always round ROM values to whole numbers for cleaner display
            return "\(Int(current.rounded()))/\(Int(target.rounded()))"
        default:
            return "\(Int(current))/\(Int(target))"
        }
    }
}

struct GoalEditSheet: View {
    let goalType: GoalType
    @EnvironmentObject var goalsService: GoalsAndStreaksService
    @Environment(\.dismiss) var dismiss
    
    @State private var targetValue: Double = 0
    @State private var dragOffset: CGSize = .zero
    
    var goal: GoalData? {
        // Get goal data from GoalsAndStreaksService
        switch goalType {
        case .sessions:
            return GoalData(type: .sessions, targetValue: Double(goalsService.currentGoals.dailyReps), currentValue: Double(goalsService.todayProgress.repsCompleted))
        case .rom:
            return GoalData(type: .rom, targetValue: goalsService.currentGoals.targetROM, currentValue: goalsService.todayProgress.bestROM)
        case .smoothness:
            return GoalData(type: .smoothness, targetValue: goalsService.currentGoals.targetSmoothness, currentValue: goalsService.todayProgress.bestSmoothness)
        default:
            return nil
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 40) {
                Spacer()
                
                // Goal info
                VStack(spacing: 16) {
                    Image(systemName: goalType.icon)
                        .font(.system(size: 60))
                        .foregroundColor(goalType.color)
                    
                    Text(goalType.metricDisplayName)
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                
                // Circular slider
                ZStack {
                    // Background circle - brighter for visibility
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 12)
                        .frame(width: 240, height: 240)
                    
                    // Progress circle - accurate fractional display
                    Circle()
                        .trim(from: 0, to: min(max(targetValue / maxValue, 0.0), 1.0))
                        .stroke(
                            goalType.color,
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .frame(width: 240, height: 240)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.2), value: targetValue)
                    
                    // Value text
                    VStack {
                        Text(formattedValue)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        Text(goalType.metricDisplayName)
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    
                    // White slider indicator dot
                    let currentProgress = min(targetValue / maxValue, 1.0)
                    let angle = currentProgress * 2 * .pi - .pi/2
                    let radius: CGFloat = 120
                    let dotX = cos(angle) * radius
                    let dotY = sin(angle) * radius
                    
                    Circle()
                        .fill(Color.white)
                        .frame(width: 20, height: 20)
                        .offset(x: dotX, y: dotY)
                        .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 2)
                    
                    // Circular slider interaction - Fixed drag zone
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 280, height: 280)
                        .contentShape(Circle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let center = CGPoint(x: 140, y: 140)
                                    let vector = CGVector(
                                        dx: value.location.x - center.x,
                                        dy: value.location.y - center.y
                                    )
                                    let angle = atan2(vector.dy, vector.dx)
                                    let normalizedAngle = (angle + .pi/2 + 2 * .pi).truncatingRemainder(dividingBy: 2 * .pi)
                                    let progress = normalizedAngle / (2 * .pi)
                                    let newValue = max(0, min(maxValue, progress * maxValue))
                                    
                                    if abs(newValue - targetValue) > 0.1 {
                                        targetValue = newValue
                                        
                                        // Light haptic feedback for smoother interaction
                                        let impact = UIImpactFeedbackGenerator(style: .light)
                                        impact.impactOccurred()
                                    }
                                }
                        )
                }
                
                Spacer()
                
                // Action buttons
                HStack(spacing: 20) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .foregroundColor(.primary)
                    .cornerRadius(12)
                    
                    Button("Save") {
                        let valueToSave: Double
                        if goalType == .smoothness {
                            // Convert from 0–100 UI scale back to 0–1 storage scale
                            valueToSave = max(0, min(1, targetValue / 100.0))
                        } else {
                            valueToSave = targetValue
                        }
                        // Update goal in GoalsAndStreaksService
                        var updatedGoals = goalsService.currentGoals
                        switch goalType {
                        case .sessions:
                            updatedGoals.dailyReps = Int(valueToSave)
                        case .rom:
                            updatedGoals.targetROM = valueToSave
                        case .smoothness:
                            updatedGoals.targetSmoothness = valueToSave
                        default:
                            break
                        }
                        goalsService.updateGoals(updatedGoals)
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(goalType.color)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            // Set goal value efficiently without heavy logging
            if let goal = goal {
                if goalType == .smoothness {
                    // Convert from 0–1 storage scale to 0–100 UI scale
                    targetValue = goal.targetValue * 100.0
                } else {
                    targetValue = goal.targetValue
                }
            } else {
                targetValue = maxValue * 0.5
            }
        }
    }
    
    private var maxValue: Double {
        switch goalType {
        case .sessions: return 10
        case .rom: return 180
        case .smoothness: return 100.0
        case .aiScore: return 100
        case .painImprovement: return 10
        case .totalReps: return 200
        }
    }
    
    private var formattedValue: String {
        switch goalType {
        case .rom:
            return targetValue.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(targetValue))" : String(format: "%.1f", targetValue)
        case .smoothness:
            return String(Int(targetValue))
        default:
            return String(Int(targetValue))
        }
    }
}

struct FullGoalEditor: View {
    @EnvironmentObject var goalsService: GoalsAndStreaksService
    @Environment(\.dismiss) var dismiss
    
    @State private var sessionTarget: String = ""
    @State private var romTarget: String = ""
    @State private var smoothnessTarget: String = ""
    
    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // Main Goals Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Main Goals")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        VStack(spacing: 12) {
                            GoalInputRow(
                                title: GoalType.sessions.metricDisplayName,
                                subtitle: nil,
                                value: $sessionTarget,
                                unit: "sessions",
                                icon: "figure.walk",
                                color: .blue
                            )
                            
                            GoalInputRow(
                                title: GoalType.rom.metricDisplayName,
                                subtitle: "ROM",
                                value: $romTarget,
                                unit: "degrees",
                                icon: "arrow.up.and.down.circle",
                                color: .green
                            )
                            
                            GoalInputRow(
                                title: GoalType.smoothness.metricDisplayName,
                                subtitle: nil,
                                value: $smoothnessTarget,
                                unit: "score (0-100)",
                                icon: "waveform.path",
                                color: .purple
                            )
                        }
                    }
                    
                    // Additional Goals Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Additional Goals")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        ForEach(goalsService.getAdditionalGoals()) { goal in
                            AdditionalGoalRow(goal: goal)
                        }
                        
                        Button(action: {
                            // Add custom goal functionality
                        }) {
                            HStack {
                                Image(systemName: "plus.circle")
                                Text("Add Goal")
                            }
                            .foregroundColor(.blue)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Edit Goals")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveGoals()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            loadCurrentValues()
        }
    }
    
    private func loadCurrentValues() {
        sessionTarget = String(goalsService.currentGoals.dailyReps)
        romTarget = String(format: "%.1f", goalsService.currentGoals.targetROM)
        // Display on 0–100 scale in the editor
        smoothnessTarget = String(Int(goalsService.currentGoals.targetSmoothness * 100))
    }
    
    private func saveGoals() {
        var updatedGoals = goalsService.currentGoals
        
        if let sessions = Double(sessionTarget) {
            updatedGoals.dailyReps = Int(sessions)
        }
        if let rom = Double(romTarget) {
            updatedGoals.targetROM = rom
        }
        if let smoothness = Double(smoothnessTarget) {
            // Convert from 0–100 text input to 0–1 storage scale
            updatedGoals.targetSmoothness = max(0, min(1, smoothness / 100.0))
        }
        
        goalsService.updateGoals(updatedGoals)
    }
}

struct GoalInputRow: View {
    let title: String
    let subtitle: String?
    @Binding var value: String
    let unit: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(subtitle ?? unit)
                    .font(subtitle == nil ? .caption : .caption2)
                    .foregroundColor(subtitle == nil ? .secondary : .gray)
            }
            
            Spacer()
            
            TextField("0", text: $value)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .keyboardType(.decimalPad)
                .frame(width: 80)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

struct AdditionalGoalRow: View {
    let goal: GoalData
    @EnvironmentObject var goalsService: GoalsAndStreaksService
    
    var body: some View {
        HStack {
            Image(systemName: goal.type.icon)
                .foregroundColor(goal.type.color)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(goal.type.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(goal.type.unit)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { goal.isEnabled },
                set: { _ in 
                    // Toggle goal in GoalsAndStreaksService
                    var updatedGoals = goalsService.currentGoals
                    switch goal.type {
                    case .aiScore:
                        updatedGoals.targetAIScore = goal.isEnabled ? 0 : 85.0
                    case .painImprovement:
                        updatedGoals.targetPainImprovement = goal.isEnabled ? 0 : 2.0
                    case .totalReps:
                        updatedGoals.weeklyReps = goal.isEnabled ? 0 : 50
                    default:
                        break
                    }
                    goalsService.updateGoals(updatedGoals)
                }
            ))
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

#Preview {
    ActivityRingsView()
        .environmentObject(GoalsAndStreaksService())
}
