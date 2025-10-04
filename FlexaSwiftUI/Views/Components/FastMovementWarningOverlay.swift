import SwiftUI

struct FastMovementWarningOverlay: View {
    let isMovementTooFast: Bool
    let reason: String
    
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        if isMovementTooFast {
            VStack(spacing: 12) {
                Image(systemName: "tortoise.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.orange)
                
                Text("Slow Down!")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text(reason)
                    .font(.body)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(themeManager.warningBackgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.orange, lineWidth: 2)
                    )
            )
            .transition(.scale.combined(with: .opacity))
            .animation(.easeInOut(duration: 0.2), value: isMovementTooFast)
        }
    }
}

#Preview {
    FastMovementWarningOverlay(
        isMovementTooFast: true,
        reason: "Slow down! Move more smoothly for better results"
    )
    .background(Color.gray)
}
