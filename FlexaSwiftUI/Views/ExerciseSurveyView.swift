import SwiftUI

struct ExerciseSurveyView: View {
    let exerciseName: String
    let isPreExercise: Bool
    @Binding var isPresented: Bool
    @State private var painRating: Int = 0
    @State private var funRating: Int = 0
    @State private var difficultyRating: Int = 0
    @State private var canSubmit: Bool = false
    
    var onSubmit: ((ExerciseSurveyData) -> Void)?
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }
            
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 8) {
                    Text(exerciseName)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    if isPreExercise {
                        Text("Before you start")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    } else {
                        Text("How was your exercise?")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
                
                VStack(spacing: 25) {
                    if isPreExercise {
                        // Pre-exercise: Only pain rating
                        VStack(spacing: 12) {
                            Text("Instructions")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Text(getGameInstructions(for: exerciseName))
                                .font(.body)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.1))
                        )
                        
                        RatingSection(
                            title: "Rate your current pain level",
                            rating: $painRating,
                            color: .red
                        )
                    } else {
                        // Post-exercise: All three ratings
                        RatingSection(
                            title: "How fun was the exercise?",
                            rating: $funRating,
                            color: .green
                        )
                        
                        RatingSection(
                            title: "How hard was the exercise?",
                            rating: $difficultyRating,
                            color: .orange
                        )
                        
                        RatingSection(
                            title: "Rate your pain level",
                            rating: $painRating,
                            color: .red
                        )
                    }
                }
                
                // Submit Button
                Button(action: {
                    submitSurvey()
                }) {
                    Text(isPreExercise ? "Start Exercise" : "Submit")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(canSubmit ? .black : .gray)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(canSubmit ? Color.green : Color.gray.opacity(0.3))
                        )
                }
                .disabled(!canSubmit)
                .animation(.easeInOut(duration: 0.2), value: canSubmit)
            }
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            )
          .padding(.horizontal, 40)
        }
        .onChange(of: painRating) { _ in updateSubmitState() }
        .onChange(of: funRating) { _ in updateSubmitState() }
        .onChange(of: difficultyRating) { _ in updateSubmitState() }
    }
    
    private func updateSubmitState() {
        if isPreExercise {
            canSubmit = painRating > 0
        } else {
            canSubmit = painRating > 0 && funRating > 0 && difficultyRating > 0
        }
    }
    
    private func submitSurvey() {
        let surveyData = ExerciseSurveyData(
            exerciseName: exerciseName,
            painRating: painRating,
            funRating: isPreExercise ? nil : funRating,
            difficultyRating: isPreExercise ? nil : difficultyRating,
            isPreExercise: isPreExercise
        )
        
        onSubmit?(surveyData)
        isPresented = false
    }
    
    private func getGameInstructions(for gameName: String) -> String {
        switch gameName.lowercased() {
        case "fruit slicer":
            return "Hold your phone and swing it forward/backward like a pendulum. The red dot moves up when you swing forward, down when you swing back. Slice fruits, avoid bombs (3 strikes = game over)."
        case "hammer time":
            return "Lie on your side with phone in landscape. Move your elbow up/down to swing the hammer left/right. Hit nails on both walls until they're flush to complete the level."
        case "witch brew":
            return "Hold your phone and make circular stirring motions. The stirrer follows your circular movement. Keep stirring to fill the progress bar - it decreases if you stop!"
        case "balloon pop":
            return "Place phone on table, use front camera. Extend your arm above your head to pop balloons with the pin tracker. Each extension counts as a rep."
        case "arm raise":
            return "Place phone on table, use front camera. Raise your arms (front or side) to hit targets. Green circles track your hands - touch targets to score points."
        case "wall climbers":
            return "Place phone on table, use front camera. Use index and middle fingers to 'climb' up the wall. The mountain texture moves as you climb higher."
        default:
            return "Follow the on-screen prompts and perform the exercise movements as indicated."
        }
    }
}

struct RatingSection: View {
    let title: String
    @Binding var rating: Int
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 20) {
                ForEach(1...5, id: \.self) { star in
                    Button(action: {
                        rating = star
                    }) {
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.system(size: 32))
                            .foregroundColor(star <= rating ? color : .gray)
                            .animation(.easeInOut(duration: 0.1), value: rating)
                    }
                }
            }
        }
    }
}

struct ExerciseSurveyData {
    let exerciseName: String
    let painRating: Int
    let funRating: Int?
    let difficultyRating: Int?
    let isPreExercise: Bool
}

#Preview {
    ExerciseSurveyView(
        exerciseName: "Fruit Slicer",
        isPreExercise: true,
        isPresented: .constant(true)
    )
}
