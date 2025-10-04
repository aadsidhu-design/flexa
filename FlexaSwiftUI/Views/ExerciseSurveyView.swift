import SwiftUI

struct ExerciseSurveyView: View {
    let exerciseName: String
    let isPreExercise: Bool
    @Binding var isPresented: Bool
    @State private var painRating: Int = 0
    @State private var funRating: Int = 0
    @State private var difficultyRating: Int = 0
    @State private var canSubmit: Bool = false
    @State private var hasInteractedWithPainRating = false
    @State private var hasInteractedWithFunRating = false
    @State private var hasInteractedWithDifficultyRating = false
    
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
                            color: .red,
                            onInteractionChanged: { hasInteracted in
                                hasInteractedWithPainRating = hasInteracted
                                updateCanSubmit()
                            }
                        )
                    } else {
                        // Post-exercise: All three ratings
                        RatingSection(
                            title: "How fun was the exercise?",
                            rating: $funRating,
                            color: .green,
                            onInteractionChanged: { hasInteracted in
                                hasInteractedWithFunRating = hasInteracted
                                updateCanSubmit()
                            }
                        )
                        
                        RatingSection(
                            title: "How hard was the exercise?",
                            rating: $difficultyRating,
                            color: .orange,
                            onInteractionChanged: { hasInteracted in
                                hasInteractedWithDifficultyRating = hasInteracted
                                updateCanSubmit()
                            }
                        )
                        
                        RatingSection(
                            title: "Rate your pain level",
                            rating: $painRating,
                            color: .red,
                            onInteractionChanged: { hasInteracted in
                                hasInteractedWithPainRating = hasInteracted
                                updateCanSubmit()
                            }
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
            canSubmit = hasInteractedWithPainRating && painRating > 0
        } else {
            canSubmit = hasInteractedWithPainRating && hasInteractedWithFunRating && hasInteractedWithDifficultyRating &&
                       painRating > 0 && funRating > 0 && difficultyRating > 0
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
        if let type = GameType.fromDisplayName(gameName) {
            switch type {
            case .fruitSlicer:
                return "Hold your phone and perform gentle pendulum swings forward and backward. Keep the motion smooth and rhythmic to build shoulder mobility."
            case .followCircle:
                return "Hold your phone and trace slow, controlled circles in the air. Stay in sync with the on-screen target to keep the motion fluid."
            case .fanOutFlame:
                return "Hold your phone flat and sweep side-to-side as if squeezing shoulder blades together. Keep shoulders relaxed and core engaged."
            case .balloonPop:
                return "Place the phone securely so the camera sees you. Reach overhead to full elbow extension, then lower with control. Repeat steady reps."
            case .wallClimbers:
                return "Face the camera and reach arms overhead as if climbing a wall. Alternate sides while keeping posture tall and core engaged."
            case .constellationMaker:
                return "Stand where the camera sees your upper body. Reach for each illuminated point and lower smoothly between reps."
            case .makeYourOwn:
                return "Customize your routine—follow the prompts you configured for motion tracking or handheld mode."
            }
        }

        switch gameName.lowercased() {
        case "fruit slicer":
            return "Hold your phone and swing it forward/backward like a pendulum. The red dot moves up when you swing forward, down when you swing back. Slice fruits, avoid bombs (3 strikes = game over)."
        case "witch brew", "follow the circle":
            return "Hold your phone and make circular stirring motions. The stirrer follows your circular movement. Keep stirring to fill the progress bar - it decreases if you stop!"
        case "fan out the flame":
            return "Hold your phone flat and move it left/right to create a fanning motion. Keep the pace steady to keep the flames away."
        case "balloon pop":
            return "Place phone on table, use front camera. Extend your arm above your head to pop balloons with the pin tracker. Each extension counts as a rep."
        case "wall climbers", "mountain climber":
            return "Place phone on table, use front camera. Use index and middle fingers to 'climb' up the wall. The mountain texture moves as you climb higher."
        case "constellations", "constellation":
            return "Place phone on table, use front camera. Reach to each star to connect the constellation while keeping movements smooth."
        case "hammer time":
            return "Lie on your side with phone in landscape. Move your elbow up/down to swing the hammer left/right. Hit nails on both walls until they're flush to complete the level."
        default:
            return "Follow the on-screen prompts and perform the exercise movements as indicated."
        }
    }
    
    private func updateCanSubmit() {
        if isPreExercise {
            canSubmit = hasInteractedWithPainRating
        } else {
            canSubmit = hasInteractedWithFunRating && hasInteractedWithDifficultyRating && hasInteractedWithPainRating
        }
    }
}

struct RatingSection: View {
    let title: String
    @Binding var rating: Int
    let color: Color
    let onInteractionChanged: ((Bool) -> Void)?
    
    init(title: String, rating: Binding<Int>, color: Color, onInteractionChanged: ((Bool) -> Void)? = nil) {
        self.title = title
        self._rating = rating
        self.color = color
        self.onInteractionChanged = onInteractionChanged
    }
    
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
                        onInteractionChanged?(true)
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
