import SwiftUI
import Charts

struct SessionDetailsPopupView: View {
    let session: ExerciseSessionData
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var geminiService: GeminiService
    
    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    // Header with exercise info
                    VStack(alignment: .leading, spacing: 8) {
                        Text(session.exerciseType)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        Text(formatDate(session.timestamp))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom)
                    
                    // AI Score and Feedback Section
                    if let aiScore = session.aiScore, aiScore > 0 {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("AI Analysis")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            // AI Score
                            HStack {
                                Text("AI Score:")
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(aiScore)/100")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(colorForScore(Double(aiScore)))
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(10)
                            
                            // AI Feedback (prefer session.aiFeedback, else use last analysis from GeminiService)
                            let feedbackText: String? = {
                                if let f = session.aiFeedback, !f.isEmpty { return f }
                                if let last = geminiService.lastAnalysis?.specificFeedback, !last.isEmpty { return last }
                                return nil
                            }()

                            if let feedback = feedbackText {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("AI Feedback:")
                                        .fontWeight(.medium)
                                    
                                    Text(feedback)
                                        .padding()
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(10)
                                        .foregroundColor(.primary)
                                }
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.05))
                        .cornerRadius(15)
                    }
                    
                    // Performance Metrics
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Performance Metrics")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 16) {
                            MetricCard(title: "Reps", value: "\(session.reps)", color: .blue)
                            MetricCard(title: "Duration", value: "\(String(format: "%.0f", session.duration))s", color: .purple)
                            
                            let avgROM = session.averageROM
                            if avgROM > 0 {
                                MetricCard(title: "Avg ROM", value: "\(String(format: "%.1f", avgROM))°", color: .cyan)
                            }
                            
                            // Average SPARC: use sparcHistory if available, else use sparcScore
                            if !session.sparcHistory.isEmpty {
                                let avg = session.sparcHistory.reduce(0, +) / Double(session.sparcHistory.count)
                                MetricCard(title: "Avg SPARC", value: String(format: "%.0f%%", avg), color: .orange)
                            } else if session.sparcScore > 0 {
                                MetricCard(title: "Avg SPARC", value: String(format: "%.0f%%", session.sparcScore * 100), color: .orange)
                            }
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(15)
                    
                    // Pain Assessment (if available)
                    if let painPre = session.painPre, let painPost = session.painPost {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Pain Assessment")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            HStack {
                                VStack {
                                    Text("Before")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(painPre)/10")
                                        .font(.title3)
                                        .fontWeight(.bold)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "arrow.right")
                                    .foregroundColor(.gray)
                                
                                Spacer()
                                
                                VStack {
                                    Text("After")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(painPost)/10")
                                        .font(.title3)
                                        .fontWeight(.bold)
                                }
                                
                                Spacer()
                                
                                VStack {
                                    Text("Change")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    let change = painPre - painPost
                                    Text(change > 0 ? "-\(change)" : "+\(abs(change))")
                                        .font(.title3)
                                        .fontWeight(.bold)
                                        .foregroundColor(change > 0 ? .green : change < 0 ? .red : .gray)
                                }
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(10)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.05))
                        .cornerRadius(15)
                    }
                    
                    
                    Spacer(minLength: 20)
                }
                .padding()
            }
            .navigationTitle("Session Details")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func colorForScore(_ score: Double) -> Color {
        switch score {
        case 80...100: return .green
        case 60...79: return .orange
        case 40...59: return .yellow
        default: return .red
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(10)
    }
}

#Preview {
    SessionDetailsPopupView(session: ExerciseSessionData(
        exerciseType: "Wall Climbers",
        score: 850,
        reps: 12,
        maxROM: 145.5,
        duration: 90,
        timestamp: Date(),
        romHistory: [120, 135, 140, 145, 142, 138],
        sparcHistory: [0.85, 0.92, 0.88],
        aiScore: 85,
        sparcScore: 0.88,
        aiFeedback: "Great job! Your range of motion improved throughout the session. Focus on maintaining consistent form for even better results."
    ))
    .environmentObject(GeminiService())
}
