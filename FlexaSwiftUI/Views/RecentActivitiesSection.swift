import SwiftUI

struct RecentActivitiesSection: View {
    let sessions: [ExerciseSessionData]
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Recent Activities")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Spacer()
                
                Button("See All") {
                    // Navigate to full activity list
                }
                .font(.subheadline)
                .foregroundColor(.green)
            }
            .padding(.horizontal)
            
            VStack(spacing: 8) {
                ForEach(sessions) { session in
                    RecentActivityRow(session: session)
                }
            }
            .padding(.horizontal)
        }
    }
}

struct RecentActivityRow: View {
    let session: ExerciseSessionData
    
    var body: some View {
        HStack(spacing: 12) {
            // Game icon
            Image(systemName: gameIcon(for: session.exerciseType))
                .font(.title2)
                .foregroundColor(gameColor(for: session.exerciseType))
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(gameColor(for: session.exerciseType).opacity(0.2))
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(session.exerciseType.capitalized)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text(timeAgo(from: session.timestamp))
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(session.reps) reps")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                
                Text("\(Int(session.maxROM))° ROM")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.1))
        )
    }
    
    private func gameIcon(for gameType: String) -> String {
        switch gameType.lowercased() {
        case "fruit slicer", "fruitSlicer": return "scissors"
        case "arm raise", "armRaise": return "arrow.up"
        case "balloon pop", "balloonPop": return "balloon.2"
        case "potion mixer", "potionMixer": return "flask"
        case "charge battery", "chargeBattery": return "battery.100"
        case "factory belt", "factoryBelt": return "conveyor.belt"
        case "wall climbers", "wallClimbers": return "mountain.2"
        case "hammer time", "hammerTime": return "hammer"
        default: return "gamecontroller"
        }
    }
    
    private func gameColor(for gameType: String) -> Color {
        switch gameType.lowercased() {
        case "fruit slicer", "fruitSlicer": return .orange
        case "arm raise", "armRaise": return .blue
        case "balloon pop", "balloonPop": return .red
        case "potion mixer", "potionMixer": return .purple
        case "charge battery", "chargeBattery": return .green
        case "factory belt", "factoryBelt": return .gray
        case "wall climbers", "wallClimbers": return .brown
        case "hammer time", "hammerTime": return .yellow
        default: return .blue
        }
    }
    
    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    RecentActivitiesSection(sessions: [
        ExerciseSessionData(
            exerciseType: "fruitSlicer",
            score: 1250,
            reps: 25,
            maxROM: 87.5,
            duration: 300,
            timestamp: Date().addingTimeInterval(-3600)
        ),
        ExerciseSessionData(
            exerciseType: "armRaise",
            score: 800,
            reps: 40,
            maxROM: 92.0,
            duration: 480,
            timestamp: Date().addingTimeInterval(-7200)
        )
    ])
    .background(Color.black)
}
