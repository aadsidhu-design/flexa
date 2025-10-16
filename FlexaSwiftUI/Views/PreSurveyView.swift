import SwiftUI

struct PreSurveyView: View {
    @Binding var isPresented: Bool
    @Binding var surveyData: SurveyData
    let onComplete: (SurveyData) -> Void
    
    @State private var currentQuestion = 0
    @State private var canProceed = false
    @State private var hasInteractedWithCurrentQuestion = false
    
    private let questions = [
        "How are you feeling today? (1 = Very Poor, 10 = Excellent)",
        "How motivated are you for this exercise? (1 = Not Motivated, 10 = Very Motivated)"
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
                VStack(spacing: 8) {
                    Text("Pre-Exercise Survey")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("Please answer these questions before starting")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                
                // Progress indicator
                HStack {
                    ForEach(0..<questions.count, id: \.self) { index in
                        Circle()
                            .fill(index <= currentQuestion ? Color.green : Color.gray.opacity(0.3))
                            .frame(width: 12, height: 12)
                            .animation(.easeInOut(duration: 0.2), value: currentQuestion)
                    }
                }
                
                // Question card
                VStack(spacing: 24) {
                    Text(questions[currentQuestion])
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    // Numeric rating (1-10 scale)
                    NumericRatingView(
                        rating: bindingForCurrentQuestion(),
                        onRatingChanged: { rating in
                            updateCurrentAnswer(rating)
                            checkCanProceed()
                        },
                        onInteractionChanged: { hasInteracted in
                            hasInteractedWithCurrentQuestion = hasInteracted
                            checkCanProceed()
                        }
                    )
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
                            withAnimation(.easeInOut(duration: 0.2)) {
                                currentQuestion -= 1
                                hasInteractedWithCurrentQuestion = false
                                checkCanProceed()
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    
                    Spacer()
                    
                    Button(currentQuestion == questions.count - 1 ? "Start Exercise" : "Next") {
                        if currentQuestion == questions.count - 1 {
                            // Complete survey
                            onComplete(surveyData)
                            isPresented = false
                        } else {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                currentQuestion += 1
                                hasInteractedWithCurrentQuestion = false
                                checkCanProceed()
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canProceed)
                }
                .padding(.horizontal)
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
            return $surveyData.feeling
        case 1:
            return $surveyData.motivation
        default:
            return $surveyData.feeling
        }
    }
    
    private func updateCurrentAnswer(_ rating: Int) {
        switch currentQuestion {
        case 0:
            surveyData.feeling = rating
        case 1:
            surveyData.motivation = rating
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
            canProceed = surveyData.feeling >= 1  // Must be at least 1 (scale is 1-10)
        case 1:
            canProceed = surveyData.motivation >= 1  // Must be at least 1 (scale is 1-10)
        default:
            canProceed = false
        }
    }
}

// StarRatingView moved to separate file

// PrimaryButtonStyle removed - using the one in FitbitStyleGoalsView.swift instead

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 25)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 25)
                            .fill(Color.clear)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SurveyData {
    var feeling: Int = 0
    var motivation: Int = 0
    var timestamp: Date = Date()
    
    var isComplete: Bool {
        return feeling >= 1 && motivation >= 1  // Both must be at least 1
    }
}

#Preview {
    PreSurveyView(
        isPresented: .constant(true),
        surveyData: .constant(SurveyData()),
        onComplete: { _ in }
    )
}
