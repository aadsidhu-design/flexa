import SwiftUI

struct NumericRatingView: View {
    @Binding var rating: Int
    let onRatingChanged: (Int) -> Void
    let onInteractionChanged: ((Bool) -> Void)?
    let maxRating: Int = 10
    let lowLabel: String
    let highLabel: String
    
    init(rating: Binding<Int>, onRatingChanged: @escaping (Int) -> Void, onInteractionChanged: ((Bool) -> Void)? = nil, lowLabel: String = "1 = Low", highLabel: String = "10 = High") {
        self._rating = rating
        self.onRatingChanged = onRatingChanged
        self.onInteractionChanged = onInteractionChanged
        self.lowLabel = lowLabel
        self.highLabel = highLabel
    }
    
    private static let hapticGenerator = UIImpactFeedbackGenerator(style: .light)
    
    @State private var sliderValue: Double = 0.0
    @State private var hasUserInteracted: Bool = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Selected rating display
            Text("\(Int(sliderValue))")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundColor(.green)
                .frame(height: 60)
            
            // Pain scale slider
            VStack(spacing: 12) {
                Slider(value: $sliderValue, in: 0...Double(maxRating), step: 1) { editing in
                    if !editing {
                        updateRating()
                    }
                }
                .simultaneousGesture(TapGesture().onEnded {
                    // Count any tap on the slider area as an interaction (tapping 0 is valid)
                    hasUserInteracted = true
                    onInteractionChanged?(hasUserInteracted)
                })
                .accentColor(.green)
                .onChange(of: sliderValue) { _ in
                    hasUserInteracted = true
                    onInteractionChanged?(hasUserInteracted)
                    Self.hapticGenerator.impactOccurred()
                }
                
                // Scale labels
                HStack {
                    Text(lowLabel)
                        .font(.caption)
                        .foregroundColor(.gray)
                    Spacer()
                    Text(highLabel)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 4)
            }
        }
        .onAppear {
            // Clamp rating into 0...maxRating and reflect in the slider
            let clamped = max(0, min(maxRating, rating))
            sliderValue = Double(clamped)
        }
        .onChange(of: rating) { newValue in
            let clamped = max(0, min(maxRating, newValue))
            sliderValue = Double(clamped)
        }
    }
    
    private func updateRating() {
        let newRating = Int(sliderValue)
        rating = newRating
        onRatingChanged(newRating)
    }
}

struct RatingButton: View {
    let number: Int
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Text("\(number)")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(isSelected ? .white : .gray)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(isSelected ? Color.green : Color.gray.opacity(0.2))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                )
                .contentShape(Circle())
                .scaleEffect(isSelected ? 1.1 : 1.0)
                .animation(.easeOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    NumericRatingView(rating: .constant(5)) { _ in }
        .preferredColorScheme(.dark)
}
