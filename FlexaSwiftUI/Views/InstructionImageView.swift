import SwiftUI

struct InstructionMediaView: View {
    let gameType: GameType

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [gameType.color.opacity(0.55), gameType.color.opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(gameType.instructionImageName)
                .resizable()
                .renderingMode(.original)
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .saturation(1.18)
                .contrast(1.12)
                .brightness(0.08)
                .shadow(color: Color.black.opacity(0.35), radius: 14, x: 0, y: 10)
                .padding(20)

            LinearGradient(
                colors: [Color.white.opacity(0.25), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.screen)
            .opacity(0.6)
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 8)
    }
}
