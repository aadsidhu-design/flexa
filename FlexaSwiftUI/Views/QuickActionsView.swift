import SwiftUI

struct QuickActionsView: View {
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Quick Start")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    QuickActionCard(
                        title: "Start Workout",
                        subtitle: "Begin your session",
                        icon: "play.circle.fill",
                        color: .green,
                        action: {}
                    )
                    
                    QuickActionCard(
                        title: "Arm Raises",
                        subtitle: "Upper body focus",
                        icon: "arrow.up.circle.fill",
                        color: .blue,
                        action: {}
                    )
                    
                    QuickActionCard(
                        title: "ROM Check",
                        subtitle: "Test flexibility",
                        icon: "arrow.up.and.down.circle.fill",
                        color: .purple,
                        action: {}
                    )
                    
                    QuickActionCard(
                        title: "Set Goals",
                        subtitle: "Update targets",
                        icon: "target",
                        color: .orange,
                        action: {}
                    )
                }
                .padding(.horizontal)
            }
        }
    }
}

struct QuickActionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundColor(color)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .frame(width: 140, height: 100)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.1))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    QuickActionsView()
        .background(Color.black)
}
