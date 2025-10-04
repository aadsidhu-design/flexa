import SwiftUI

enum PostSurveyCompletionAction {
    case submitted
    case skipped
    case retry
}

struct PostSurveyRetryView: View {
    @Binding var isPresented: Bool
    @Binding var postSurveyData: PostSurveyData
    let sessionData: ExerciseSessionData
    let onComplete: (PostSurveyCompletionAction) -> Void
    @EnvironmentObject var motionService: SimpleMotionService
    
    @State private var currentQuestion = 0
    @State private var canProceed = false
    @State private var hasInteractedWithCurrentQuestion = false
    
    
    private let questions = [
        "How do you feel after the exercise?",
        "What is your pain level now?",
        "How much did you enjoy this exercise?",
        "How hard was this exercise?"
    ]
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
                .onTapGesture {
                    // Prevent dismissal by tapping outside
                }
            
            VStack(spacing: 30) {
                HStack {
                    Spacer()
                    Button(action: skipSurvey) {
                        Label("Skip survey", systemImage: "forward.fill")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .foregroundColor(.white)
                    .background(Color.white.opacity(0.12))
                    .cornerRadius(22)
                    .tapTarget(60)
                }

                // Header
                VStack(spacing: 12) {
                    Text("Post-Exercise Survey")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 2)

                    Text("Help us improve your experience by rating how you feel after your exercise session")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.gray.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 20)
                }
                
                // Progress indicator
                HStack {
                    ForEach(0..<questions.count, id: \.self) { index in
                        Circle()
                            .frame(width: 12, height: 12)
                            .animation(.easeInOut(duration: 0.3), value: currentQuestion)
                    }
                }
                
                // Question cards
                VStack(spacing: 32) {
                    Text(questions[currentQuestion])
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)

                    // 1–10 numeric rating with context-specific labels
                    NumericRatingView(
                        rating: bindingForCurrentQuestion(),
                        onRatingChanged: { rating in
                            updateCurrentAnswer(rating)
                            checkCanProceed()
                        },
                        onInteractionChanged: { hasInteracted in
                            hasInteractedWithCurrentQuestion = hasInteracted
                            checkCanProceed()
                        },
                        lowLabel: lowLabelForCurrentQuestion(),
                        highLabel: highLabelForCurrentQuestion()
                    )

                    // Removed verbose helper/instruction to simplify the questionrompt.
                }
                .padding(30)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.gray.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
                
                // Navigation buttons (Back / Next only)
                HStack(spacing: 16) {
                    if currentQuestion > 0 {
                        Button("Back") {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentQuestion -= 1
                                hasInteractedWithCurrentQuestion = false
                                checkCanProceed()
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .tapTarget(60)
                    }
                    
                    Spacer()
                    
                    Button("Next") {
                        if currentQuestion == questions.count - 1 {
                            // Final step: complete and go Home
                            HapticFeedbackService.shared.buttonTapHaptic()
                            // Close the survey
                            isPresented = false
                            // Notify completion (treated as Done) after dismissal to keep UI smooth
                            DispatchQueue.main.async {
                                onComplete(.submitted)
                            }
                            // NavigationCoordinator handles goHome in parent
                        } else {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentQuestion += 1
                                hasInteractedWithCurrentQuestion = false
                                checkCanProceed()
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canProceed)
                    .tapTarget(60)
                }
                .padding(.horizontal)
                
                // Validation message
                if !canProceed {
                    Text("Please select a rating to continue")
                        .font(.caption)
                        .foregroundColor(.red)
                        .opacity(0.8)
                }
            }
            .padding(30)
        }
        .onAppear {
            // Reset ratings to 0 to force explicit user interaction
            postSurveyData.funRating = 0
            postSurveyData.painLevel = 0
            postSurveyData.enjoymentRating = 0
            postSurveyData.difficultyRating = 0
            hasInteractedWithCurrentQuestion = false
            checkCanProceed()
        }
    }
    
    // Removed completeAction with Done/Retry
    
    private func bindingForCurrentQuestion() -> Binding<Int> {
        switch currentQuestion {
        case 0:
            return $postSurveyData.funRating
        case 1:
            return $postSurveyData.painLevel
        case 2:
            return $postSurveyData.enjoymentRating
        case 3:
            return $postSurveyData.difficultyRating
        default:
            return $postSurveyData.funRating
        }
    }
    
    private func updateCurrentAnswer(_ rating: Int) {
        switch currentQuestion {
        case 0:
            postSurveyData.funRating = rating
        case 1:
            postSurveyData.painLevel = rating
            // Set pain level in motion service for tracking
            motionService.setPostPainLevel(rating)
        case 2:
            postSurveyData.enjoymentRating = rating
        case 3:
            postSurveyData.difficultyRating = rating
        default:
            break
        }
    }
    
    private func checkCanProceed() {
        // User must have interacted with the rating control to proceed
        guard hasInteractedWithCurrentQuestion else {
            canProceed = false
            return
        }
        
        switch currentQuestion {
        case 0:
            canProceed = postSurveyData.funRating >= 0  // Accept 0 as valid answer
        case 1:
            canProceed = postSurveyData.painLevel >= 0  // Accept 0 as valid answer
        case 2:
            canProceed = postSurveyData.enjoymentRating >= 0  // Accept 0 as valid answer
        case 3:
            canProceed = postSurveyData.difficultyRating >= 0  // Accept 0 as valid answer
        default:
            canProceed = false
        }
    }
    
    private func helperTextForCurrentQuestion() -> String {
        switch currentQuestion {
        case 0:
            return "0 = Much worse, 5 = About the same, 10 = Much better than before"
        case 1:
            return "0 = No pain, 5 = Moderate discomfort, 10 = Severe pain"
        case 2:
            return "0 = Not at all, 5 = Moderately, 10 = Very much"
        case 3:
            return "0 = Very easy, 5 = Moderate, 10 = Very hard"
        default:
            return ""
        }
    }

    private func instructionTextForCurrentQuestion() -> String {
        switch currentQuestion {
        case 0:
            return ""
        case 1:
            return "Rate any pain or discomfort you're experiencing in the areas you exercised. If you have no pain, select 1 star."
        case 2:
            return "Rate how much you enjoyed this exercise session."
        case 3:
            return "Rate the difficulty level of this exercise."
        default:
            return ""
        }
    }
    
    private func lowLabelForCurrentQuestion() -> String {
        switch currentQuestion {
    case 0: return "0 = Much Worse"
    case 1: return "0 = No Pain"
    case 2: return "0 = Boring"
    case 3: return "0 = Too Easy"
        default: return "1 = Low"
        }
    }
    
    private func highLabelForCurrentQuestion() -> String {
        switch currentQuestion {
    case 0: return "10 = Much Better"
    case 1: return "10 = Severe Pain"
    case 2: return "10 = Super Fun"
    case 3: return "10 = Too Hard"
        default: return "10 = High"
        }
    }

    private func skipSurvey() {
        HapticFeedbackService.shared.buttonTapHaptic()
        postSurveyData.funRating = 0
        postSurveyData.painLevel = 0
        postSurveyData.enjoymentRating = 0
        postSurveyData.difficultyRating = 0
        
        // Note: Goals are updated automatically when session data is saved
        // Skipping survey still saves the session with workout data
        print("✅ [SkipSurvey] Survey skipped - session data preserved for goals")
        
        isPresented = false
        DispatchQueue.main.async {
            onComplete(.skipped)
        }
    }
}

#Preview {
    PostSurveyRetryView(
        isPresented: Binding.constant(true),
        postSurveyData: Binding.constant(PostSurveyData(painLevel: 0, funRating: 0, difficultyRating: 0, enjoymentRating: 0, perceivedExertion: 0, willingnessToRepeat: 0, timestamp: Date())),
        sessionData: ExerciseSessionData(
            exerciseType: "Pendulum Swing",
            score: 85,
            reps: 12,
            maxROM: 65.5,
            duration: 90.0,
            romHistory: [45.2, 52.1, 58.3],
            sparcHistory: [0.75, 0.82, 0.78],
            aiScore: 87,
            sparcScore: 0.82
        ),
        onComplete: { _ in }
    )
}
