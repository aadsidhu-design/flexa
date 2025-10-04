import SwiftUI

struct RecentActivitiesSection: View {
    let sessions: [ExerciseSessionData]
    let onSeeAll: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Recent Activities")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Spacer()
                
                if sessions.count > 3 {
                    Button("See more") {
                        onSeeAll()
                    }
                    .font(.subheadline)
                    .foregroundColor(.green)
                }
            }
            .padding(.horizontal)
            
            VStack(spacing: 8) {
                ForEach(sessions.prefix(3)) { session in
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
                
                // Prefer average ROM; fallback to per-rep average; then max ROM; then 0
                let displayROM: Double = {
                    if session.averageROM > 0 {
                        return session.averageROM
                    }
                    if !session.romHistory.isEmpty {
                        let avg = session.romHistory.reduce(0.0, +) / Double(session.romHistory.count)
                        if avg > 0 { return avg }
                    }
                    if session.maxROM > 0 { return session.maxROM }
                    return 0
                }()
                Text("\(Int(displayROM))° ROM")
                    .font(.caption)
                    .foregroundColor(displayROM > 0 ? .blue : .gray)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.1))
        )
    }
    
    private func gameIcon(for gameType: String) -> String {
        if let type = GameType.fromDisplayName(gameType) {
            switch type {
            case .fruitSlicer: return "figure.walk.motion"
            case .followCircle: return "circle.dotted"
            case .fanOutFlame: return "flame"
            case .balloonPop: return "bolt.circle"
            case .wallClimbers: return "mountain.2"
            case .constellationMaker: return "sparkles"
            case .makeYourOwn: return "gearshape"
            }
        }

        switch gameType.lowercased() {
        case "fruit slicer", "fruitslicer": return "scissors"
        case "arm raise", "armraise": return "arrow.up"
        case "balloon pop", "balloonpop": return "balloon.2"
        case "potion mixer", "potionmixer": return "flask"
        case "charge battery", "chargebattery": return "battery.100"
        case "factory belt", "factorybelt": return "conveyor.belt"
        case "wall climbers", "wallclimbers": return "mountain.2"
        case "hammer time", "hammertime": return "hammer"
        default: return "gamecontroller"
        }
    }
    
    private func gameColor(for gameType: String) -> Color {
        if let type = GameType.fromDisplayName(gameType) {
            switch type {
            case .fruitSlicer: return .orange
            case .followCircle: return .blue
            case .fanOutFlame: return .red
            case .balloonPop: return .pink
            case .wallClimbers: return .brown
            case .constellationMaker: return .purple
            case .makeYourOwn: return .orange
            }
        }

        switch gameType.lowercased() {
        case "fruit slicer", "fruitslicer": return .orange
        case "arm raise", "armraise": return .blue
        case "balloon pop", "balloonpop": return .red
        case "potion mixer", "potionmixer": return .purple
        case "charge battery", "chargebattery": return .green
        case "factory belt", "factorybelt": return .gray
        case "wall climbers", "wallclimbers": return .brown
        case "hammer time", "hammertime": return .yellow
        default: return .blue
        }
    }
    
    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// Full list view presented from Home — shows all recent activities
struct AllActivitiesListView: View {
    @Environment(\.dismiss) var dismiss
    @State private var sessions: [ExerciseSessionData] = []
    
    var body: some View {
        NavigationView {
            List {
                ForEach(sessions) { s in
                    RecentActivityRow(session: s)
                        .listRowBackground(Color.black)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("Recent Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.green)
                }
            }
        }
        .onAppear(perform: loadAllSessions)
    }
    
    private func loadAllSessions() {
        // Prefer comprehensive sessions for richer data
        let comps = LocalDataManager.shared.getCachedComprehensiveSessions()
        var result: [ExerciseSessionData] = comps.map { c in
            ExerciseSessionData(
                id: c.id,
                exerciseType: c.exerciseName,
                score: c.totalScore,
                reps: c.totalReps,
                maxROM: c.maxROM,
                averageROM: c.avgROM,
                duration: c.duration,
                timestamp: c.timestamp,
                romHistory: c.romPerRep,
                repTimestamps: c.repTimestamps,
                sparcHistory: [],
                romData: [],
                sparcData: [],
                aiScore: c.aiScore,
                painPre: c.preSurveyData.painLevel,
                painPost: c.postSurveyData?.painLevel,
                sparcScore: c.sparcScore,
                formScore: 0,
                consistency: c.consistencyScore,
                peakVelocity: 0
            )
        }
        result.sort { $0.timestamp > $1.timestamp }
        sessions = result
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
    ], onSeeAll: {})
    .background(Color.black)
}
