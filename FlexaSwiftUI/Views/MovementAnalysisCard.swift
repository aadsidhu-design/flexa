import SwiftUI

struct MovementAnalysisCard: View {
    @ObservedObject var analyzer: MovementPatternAnalyzer
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "figure.walk")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                Text("Movement Analysis")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Spacer()
                
                // Movement Quality Score
                HStack(spacing: 4) {
                    Text("\(Int(analyzer.movementQualityScore))")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(qualityColor)
                    Text("/100")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
            
            // Quality Progress Bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 6)
                        .cornerRadius(3)
                    
                    Rectangle()
                        .fill(qualityColor)
                        .frame(width: geometry.size.width * (analyzer.movementQualityScore / 100), height: 6)
                        .cornerRadius(3)
                }
            }
            .frame(height: 6)
            
            // Compensatory Movements
            if !analyzer.compensatoryMovements.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Areas for Improvement")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    ForEach(Array(analyzer.compensatoryMovements.enumerated()), id: \.offset) { index, movement in
                        HStack {
                            Circle()
                                .fill(severityColor(movement.severity))
                                .frame(width: 8, height: 8)
                            
                            Text(movement.description)
                                .font(.caption)
                                .foregroundColor(.gray)
                            
                            Spacer()
                            
                            Text("\(Int(movement.severity * 100))%")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(severityColor(movement.severity))
                        }
                    }
                }
            }
            
            // Top Suggestion
            if let topSuggestion = analyzer.getTopSuggestion() {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recommendation")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.yellow)
                            .font(.caption)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(topSuggestion.title)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                            
                            Text(topSuggestion.description)
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            } else if analyzer.movementQualityScore > 85 {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    
                    Text("Excellent movement pattern! Keep it up!")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.1))
        )
        .padding(.horizontal)
    }
    
    private var qualityColor: Color {
        switch analyzer.movementQualityScore {
        case 85...100: return .green
        case 70..<85: return .yellow
        case 50..<70: return .orange
        default: return .red
        }
    }
    
    private func severityColor(_ severity: Double) -> Color {
        switch severity {
        case 0.8...1.0: return .red
        case 0.5..<0.8: return .orange
        case 0.3..<0.5: return .yellow
        default: return .blue
        }
    }
}

#Preview {
    MovementAnalysisCard(analyzer: MovementPatternAnalyzer())
        .background(Color.black)
}
