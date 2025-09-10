import SwiftUI

struct RecommendationsSection: View {
    @EnvironmentObject var recommendationsEngine: RecommendationsEngine
    
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Text("For You")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Spacer()
                Button {
                    Task { await recommendationsEngine.generatePersonalizedRecommendations(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .imageScale(.medium)
                }
                .buttonStyle(.bordered)
                .tint(.green)
                .disabled(recommendationsEngine.isGenerating)
                .accessibilityLabel("Refresh recommendations")
                
                if recommendationsEngine.isGenerating {
                    SwiftUI.ProgressView()
                        .scaleEffect(0.8)
                        .tint(.green)
                }
            }
            .padding(.horizontal)
            
            if let last = recommendationsEngine.lastUpdatedAt {
                Text("Updated \(relativeTime(last))")
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(recommendationsEngine.recommendations.prefix(5)) { recommendation in
                        RecommendationCard(recommendation: recommendation)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct RecommendationCard: View {
    let recommendation: Recommendation
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: iconForType(recommendation.type))
                    .font(.title2)
                    .foregroundColor(colorForPriority(recommendation.priority))
                
                Spacer()
                
                Text(recommendation.priority.rawValue.uppercased())
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(colorForPriority(recommendation.priority))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(colorForPriority(recommendation.priority).opacity(0.2))
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(recommendation.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                
                Text(recommendation.description)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
            }
            
            if !recommendation.estimatedBenefit.isEmpty {
                HStack {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                    
                    Text(recommendation.estimatedBenefit)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
        }
        .frame(width: 280, height: 140)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.1))
        )
    }
    
    private func iconForType(_ type: RecommendationType) -> String {
        switch type {
        case .exerciseModification: return "figure.strengthtraining.traditional"
        case .goalAdjustment: return "target"
        case .newGame: return "gamecontroller"
        case .restDay: return "bed.double"
        }
    }
    
    private func colorForPriority(_ priority: RecommendationPriority) -> Color {
        switch priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        }
    }
}

#Preview {
    RecommendationsSection()
        .environmentObject(RecommendationsEngine())
        .background(Color.black)
}
