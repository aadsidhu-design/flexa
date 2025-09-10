import SwiftUI

struct PostSurveyView: View {
    @Binding var isPresented: Bool
    @Binding var surveyData: PostSurveyData
    let onComplete: (PostSurveyData) -> Void
    
    @State private var currentQuestion = 0
    @State private var canProceed = false
    
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
                            .fill(index <= currentQuestion ? Color.green : Color.gray.opacity(0.3))
                            .frame(width: 12, height: 12)
                            .animation(.easeInOut(duration: 0.3), value: currentQuestion)
                    }
                }
                
                // Question card
                VStack(spacing: 32) {
                    Text(questions[currentQuestion])
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .lineSpacing(6)
                        .minimumScaleFactor(0.8)

                    // 1–10 numeric rating (consistent with pre-survey)
                    NumericRatingView(
                        rating: bindingForCurrentQuestion(),
                        onRatingChanged: { rating in
                            updateCurrentAnswer(rating)
                            checkCanProceed()
                        }
                    )

                    // Enhanced helper text with better instructions
                    VStack(spacing: 8) {
                        Text(helperTextForCurrentQuestion())
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)

                        // Additional instruction based on question
                        Text(instructionTextForCurrentQuestion())
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundColor(.gray.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .lineSpacing(3)
                    }
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
                
                // Navigation buttons
                HStack(spacing: 16) {
                    if currentQuestion > 0 {
                        Button("Back") {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentQuestion -= 1
                                checkCanProceed()
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    
                    Spacer()
                    
                    Button(currentQuestion == questions.count - 1 ? "Submit" : "Next") {
                        if currentQuestion == questions.count - 1 {
                            // Complete survey and trigger background upload
                            onComplete(surveyData)
                            isPresented = false
                        } else {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentQuestion += 1
                                checkCanProceed()
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canProceed)
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
            checkCanProceed()
        }
    }
    
    private func bindingForCurrentQuestion() -> Binding<Int> {
        switch currentQuestion {
        case 0:
            return $surveyData.funRating
        case 1:
            return $surveyData.painLevel
        case 2:
            return $surveyData.enjoymentRating
        case 3:
            return $surveyData.difficultyRating
        default:
            return $surveyData.funRating
        }
    }
    
    private func updateCurrentAnswer(_ rating: Int) {
        switch currentQuestion {
        case 0:
            surveyData.funRating = rating
        case 1:
            surveyData.painLevel = rating
        case 2:
            surveyData.enjoymentRating = rating
        case 3:
            surveyData.difficultyRating = rating
        default:
            break
        }
    }
    
    private func checkCanProceed() {
        switch currentQuestion {
        case 0:
            canProceed = surveyData.funRating > 0
        case 1:
            canProceed = surveyData.painLevel > 0
        case 2:
            canProceed = surveyData.enjoymentRating > 0
        case 3:
            canProceed = surveyData.difficultyRating > 0
        default:
            canProceed = false
        }
    }
    
    private func helperTextForCurrentQuestion() -> String {
        switch currentQuestion {
        case 0:
            return "1 = Much worse, 5 = About the same, 10 = Much better than before"
        case 1:
            return "1 = No pain, 5 = Moderate discomfort, 10 = Severe pain"
        case 2:
            return "1 = Not at all, 5 = Moderately, 10 = Very much"
        case 3:
            return "1 = Very easy, 5 = Moderate, 10 = Very hard"
        default:
            return ""
        }
    }

    private func instructionTextForCurrentQuestion() -> String {
        switch currentQuestion {
        case 0:
            return "Think about how your body feels right now compared to before you started the exercise. Consider factors like energy level, muscle fatigue, and overall well-being."
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
}


#Preview {
    PostSurveyView(
        isPresented: .constant(true),
        surveyData: .constant(PostSurveyData(painLevel: 0, funRating: 0, difficultyRating: 0, enjoymentRating: 0, perceivedExertion: 0, willingnessToRepeat: 0, timestamp: Date())),
        onComplete: { _ in }
    )
}
