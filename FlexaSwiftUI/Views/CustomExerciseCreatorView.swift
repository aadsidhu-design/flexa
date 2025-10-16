import SwiftUI

struct CustomExerciseCreatorView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    @StateObject private var aiAnalyzer = AIExerciseAnalyzer.shared
    @StateObject private var exerciseManager = CustomExerciseManager.shared

    @State private var exerciseDescription: String = ""
    @FocusState private var isEditorFocused: Bool
    @State private var isAnalyzing: Bool = false
    @State private var analysisResult: AIExerciseAnalysis?
    @State private var showingError: Bool = false
    @State private var errorMessage: String = ""
    @State private var showingPreview: Bool = false
    @State private var selectedExampleIndex: Int? = nil
    
    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Create custom exercise")
                            .font(.system(size: 32, weight: .bold, design: .default))
                            .foregroundColor(.primary)
                        
                        Text("Tell us about a movement you want to track")
                            .font(.system(size: 16, weight: .regular, design: .default))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                    
                    Divider()
                        .padding(.horizontal, 20)
                    
                    VStack(spacing: 32) {
                        // Input Section
                        PromptEditorCardSimple(
                            text: $exerciseDescription,
                            isFocused: _isEditorFocused
                        )
                        .padding(.horizontal, 20)
                        
                        // Example Prompts Section
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Quick start")
                                .font(.system(size: 17, weight: .semibold, design: .default))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 20)
                            
                            ExamplePromptGridSimple { prompt in
                                exerciseDescription = prompt
                                isEditorFocused = false
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        // Analyze Button
                        AnalyzeButtonSimple(isAnalyzing: isAnalyzing, isDisabled: exerciseDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                            analyzeExercise()
                        }
                        .padding(.horizontal, 20)
                        
                        // Results
                        if let result = analysisResult {
                            AnalysisResultCardSimple(analysis: result) {
                                showingPreview = true
                            }
                            .padding(.horizontal, 20)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                        
                        Spacer(minLength: 20)
                    }
                    .padding(.vertical, 24)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .fontWeight(.semibold)
                        Text("Back")
                    }
                    .foregroundColor(.blue)
                }
            }
        }
        .dismissKeyboardOnTap()
        .alert("Analysis Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showingPreview) {
            if let result = analysisResult {
                ExercisePreviewSheet(
                    analysis: result,
                    description: exerciseDescription,
                    onSave: saveAndStartExercise
                )
            }
        }
    }
    
    private func analyzeExercise() {
        isAnalyzing = true
        
        Task {
            do {
                let result = try await aiAnalyzer.analyzeExercise(description: exerciseDescription)
                await MainActor.run {
                    self.analysisResult = result
                    self.isAnalyzing = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.showingError = true
                    self.isAnalyzing = false
                }
            }
        }
    }
    
    private func saveAndStartExercise() {
        guard let analysis = analysisResult else { return }
        
        let customExercise = analysis.toCustomExercise(userDescription: exerciseDescription)
        exerciseManager.addExercise(customExercise)
        exerciseManager.storeLatestAnalysis(analysis, prompt: exerciseDescription)
        
        dismiss()
        
        // Navigate to custom exercise game view
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            navigationCoordinator.showCustomExerciseGame(exercise: customExercise)
        }
    }
}

struct PromptEditorCardSimple: View {
    @Binding var text: String
    @FocusState var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exercise description")
                .font(.system(size: 15, weight: .semibold, design: .default))
                .foregroundColor(.secondary)
            
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(UIColor.secondarySystemBackground))
                
                TextEditor(text: $text)
                    .focused($isFocused)
                    .frame(minHeight: 140)
                    .padding(12)
                    .font(.system(size: 16, weight: .regular, design: .default))
                    .foregroundColor(.primary)
                    .background(Color.clear)
                    .scrollContentBackground(.hidden)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty && !isFocused {
                            Text("For example: Swing my phone side to side like a pendulum")
                                .foregroundColor(Color(UIColor.tertiaryLabel))
                                .padding(12)
                                .font(.system(size: 16, weight: .regular, design: .default))
                        }
                    }
            }
        }
    }
}

struct ExamplePromptGridSimple: View {
    let prompts: [PromptSample] = [
        PromptSample(
            icon: "waveform.path",
            title: "Pendulum swing",
            subtitle: "Swing back and forth smoothly",
            prompt: "Swing my phone side to side like a pendulum"
        ),
        PromptSample(
            icon: "arrow.up.circle",
            title: "Reach up",
            subtitle: "Stretch arms overhead",
            prompt: "Reach my arms overhead as high as I can"
        ),
        PromptSample(
            icon: "circle.dotted",
            title: "Circle motion",
            subtitle: "Make smooth circles",
            prompt: "Make circular motions with my phone"
        )
    ]
    let onSelect: (String) -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            ForEach(prompts) { sample in
                Button(action: { onSelect(sample.prompt) }) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Image(systemName: sample.icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.blue)
                                .frame(width: 32)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sample.title)
                                    .font(.system(size: 15, weight: .semibold, design: .default))
                                    .foregroundColor(.primary)
                                
                                Text(sample.subtitle)
                                    .font(.system(size: 13, weight: .regular, design: .default))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(10)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct AnalyzeButtonSimple: View {
    let isAnalyzing: Bool
    let isDisabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isAnalyzing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.9)
                } else {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(isAnalyzing ? "Analyzing..." : "Analyze with AI")
                    .font(.system(size: 16, weight: .semibold, design: .default))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .backgroundColor(isDisabled ? Color(UIColor.tertiarySystemBackground) : Color.blue)
            .foregroundColor(isDisabled ? .secondary : .white)
            .cornerRadius(10)
        }
        .disabled(isDisabled || isAnalyzing)
        .opacity(isDisabled ? 0.6 : 1)
    }
}

struct AnalysisResultCardSimple: View {
    let analysis: AIExerciseAnalysis
    let onStartExercise: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 20))
                    
                    Text("Ready to start")
                        .font(.system(size: 17, weight: .semibold, design: .default))
                        .foregroundColor(.primary)
                }
                
                Text(analysis.exerciseName)
                    .font(.system(size: 28, weight: .bold, design: .default))
                    .foregroundColor(.primary)
                
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mode")
                            .font(.system(size: 13, weight: .semibold, design: .default))
                            .foregroundColor(.secondary)
                        Text(analysis.trackingMode.rawValue.capitalized)
                            .font(.system(size: 15, weight: .semibold, design: .default))
                            .foregroundColor(.primary)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Confidence")
                            .font(.system(size: 13, weight: .semibold, design: .default))
                            .foregroundColor(.secondary)
                        Text("\(Int(analysis.confidence * 100))%")
                            .font(.system(size: 15, weight: .semibold, design: .default))
                            .foregroundColor(.primary)
                    }
                }
            }
            .padding(16)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
            
            Button(action: onStartExercise) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Start session")
                        .font(.system(size: 16, weight: .semibold, design: .default))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .backgroundColor(.green)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
}



struct PromptSample: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
    let prompt: String
}



struct ExercisePreviewSheet: View {
    @Environment(\.dismiss) var dismiss
    let analysis: AIExerciseAnalysis
    let description: String
    let onSave: () -> Void
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Icon and Name
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color.green.opacity(0.2))
                                    .frame(width: 100, height: 100)
                                
                                Image(systemName: iconForMovementType(analysis.movementType))
                                    .font(.system(size: 40))
                                    .foregroundColor(.green)
                            }
                            
                            Text(analysis.exerciseName)
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                        }
                        
                        // Full Details
                        VStack(spacing: 16) {
                            InfoSection(title: "Your Description", content: description)
                            InfoSection(title: "AI Analysis", content: analysis.reasoning)
                            
                            // Technical Parameters
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Technical Parameters")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                                ParameterRow(icon: "target", label: "Mode", value: analysis.trackingMode.rawValue.capitalized)
                                
                                if let joint = analysis.jointToTrack {
                                    ParameterRow(icon: "hand.raised", label: "Joint", value: joint.rawValue.capitalized)
                                }
                                
                                ParameterRow(icon: "arrow.triangle.2.circlepath", label: "Movement", value: analysis.movementType.rawValue.capitalized)
                                ParameterRow(icon: "arrow.left.arrow.right", label: "Direction", value: analysis.directionality.rawValue.capitalized)
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(12)
                        }
                        
                        // Confirm Button
                        Button(action: {
                            onSave()
                            dismiss()
                        }) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Save & Start Exercise")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        
                        Spacer(minLength: 50)
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
    
    private func iconForMovementType(_ type: CustomExercise.RepParameters.MovementType) -> String {
        switch type {
        case .pendulum: return "waveform.path"
        case .circular: return "circle.dotted"
        case .vertical: return "arrow.up.arrow.down"
        case .horizontal: return "arrow.left.arrow.right"
        case .straightening: return "arrow.up.forward"
        case .mixed: return "square.3.layers.3d"
        }
    }
}

struct InfoSection: View {
    let title: String
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
            
            Text(content)
                .font(.subheadline)
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

struct ParameterRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.cyan)
                .frame(width: 24)
            
            Text(label)
                .foregroundColor(.gray)
            
            Spacer()
            
            Text(value)
                .fontWeight(.medium)
                .foregroundColor(.white)
        }
        .font(.subheadline)
    }
}

extension View {
    func backgroundColor(_ color: Color) -> some View {
        self.background(color)
    }
}

#Preview {
    CustomExerciseCreatorView()
        .environmentObject(NavigationCoordinator.shared)
}
