import SwiftUI

struct StarRatingView: View {
    @Binding var rating: Int
    let onRatingChanged: (Int) -> Void
    let maxRating: Int = 5
    
    // Optimize haptic feedback - reuse single instance
    private static let hapticGenerator = UIImpactFeedbackGenerator(style: .light)
    
    // Internal state for immediate UI updates
    @State private var internalRating: Int = 0
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...maxRating, id: \.self) { index in
                Button(action: {
                    // Immediate UI update for responsiveness
                    internalRating = index
                    
                    // Immediate haptic feedback
                    Self.hapticGenerator.impactOccurred()
                    
                    // Debounce the actual rating change
                    debounceRatingChange(to: index)
                }) {
                    Image(systemName: index <= internalRating ? "star.fill" : "star")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(index <= internalRating ? .yellow : Color.gray.opacity(0.5))
                        .animation(nil, value: internalRating) // Remove animation for immediate response
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .onAppear {
            internalRating = rating
        }
        .onChange(of: rating) { newValue in
            internalRating = newValue
        }
    }
    
    private func debounceRatingChange(to newRating: Int) {
        // Cancel previous debounce task
        debounceTask?.cancel()
        
        // Create new debounced task
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms debounce
            
            if !Task.isCancelled {
                await MainActor.run {
                    rating = newRating
                    onRatingChanged(newRating)
                }
            }
        }
    }
}

#Preview {
    StarRatingView(rating: .constant(3)) { _ in }
}
