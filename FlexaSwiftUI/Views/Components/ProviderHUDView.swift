import SwiftUI

struct ProviderHUDView: View {
    @EnvironmentObject var motionService: SimpleMotionService
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(colorFor(provider: motionService.providerHUD))
                .frame(width: 8, height: 8)
            Text(motionService.providerHUD)
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
        .padding([.top, .trailing], 12)
    }
    private func colorFor(provider: String) -> Color {
        switch provider {
        case "Vision": return .yellow
        case "Vision+IMU": return .orange
        case "IMU": return .green
        case "AR Body": return .blue
        case "AR World": return .purple
        default: return .gray
        }
    }
}
