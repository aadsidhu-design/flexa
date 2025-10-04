import SwiftUI
import AVKit

struct InstructionMediaView: View {
    let gameType: GameType
    @State private var player: AVPlayer?
    @State private var didAttemptLoad = false

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 10)
                    .onAppear {
                        player.seek(to: .zero)
                    }
            } else {
                PlaceholderView(gameType: gameType)
                    .task {
                        await preparePlayer()
                    }
            }
        }
    }

    private func preparePlayer() async {
        guard !didAttemptLoad else { return }
        didAttemptLoad = true

        guard let url = gameType.instructionVideoURL else { return }
        await MainActor.run {
            player = AVPlayer(url: url)
        }
    }

    private struct PlaceholderView: View {
        let gameType: GameType

        var body: some View {
            ZStack {
                LinearGradient(
                    colors: [gameType.color.opacity(0.35), .black.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                VStack(spacing: 12) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 44, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))

                    if gameType == .constellationMaker {
                        Text("Instruction video coming soon")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("Drop Arm Raises demo as \(gameType.instructionVideoResourceName).mp4 when ready.")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white.opacity(0.75))
                            .padding(.horizontal, 24)
                    }
                }
                .padding(.vertical, 32)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }
}
