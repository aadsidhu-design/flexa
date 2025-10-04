import SwiftUI

#if DEBUG
struct DebugHUDView: View {
    @EnvironmentObject var motionService: SimpleMotionService

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DEBUG HUD").font(.caption2).foregroundColor(.white.opacity(0.7))
            Divider().background(Color.white.opacity(0.2))
            row("ROM Mode", motionService.romTrackingMode)
            row("Provider", motionService.providerHUD)
            row("ROM", String(format: "%.1f°", motionService.currentROM))
            row("Reps", "\(motionService.currentReps)")
        }
        .padding(8)
        .background(Color.black.opacity(0.6))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .padding(8)
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label + ":").font(.caption2).foregroundColor(.white.opacity(0.7))
            Text(value).font(.caption2).foregroundColor(.white)
        }
    }
}
#endif
