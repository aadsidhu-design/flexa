import Foundation
import FirebaseFirestore
import FirebaseAuth

class SessionUploadService: ObservableObject {
    private let db = Firestore.firestore()
    @Published var uploadProgress: Double = 0
    @Published var isUploading = false
    
    func uploadSessionData(
        _ sessionData: ComprehensiveSessionData,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let userID = Auth.auth().currentUser?.uid else {
            completion(.failure(SessionUploadError.noUserAuthenticated))
            return
        }
        
        isUploading = true
        uploadProgress = 0
        
        Task {
            do {
                try await uploadInBackground(sessionData: sessionData, userID: userID)
                await MainActor.run {
                    self.isUploading = false
                    self.uploadProgress = 1.0
                    completion(.success(()))
                }
            } catch {
                await MainActor.run {
                    self.isUploading = false
                    self.uploadProgress = 0
                    completion(.failure(error))
                }
            }
        }
    }
    
    private func uploadInBackground(sessionData: ComprehensiveSessionData, userID: String) async throws {
        let sessionRef = db.collection("users").document(userID).collection("sessions").document(sessionData.id)
        
        // Update progress incrementally
        await updateProgress(0.1)
        
        // Upload main session data
        try await sessionRef.setData(sessionData.toDictionary())
        await updateProgress(0.4)
        
        // Upload detailed SPARC data separately for better performance
        try await uploadSPARCData(sessionData: sessionData, sessionRef: sessionRef)
        await updateProgress(0.6)
        
        // Upload ROM per rep data
        try await uploadROMData(sessionData: sessionData, sessionRef: sessionRef)
        await updateProgress(0.8)
        
        // Update user statistics
        try await updateUserStatistics(sessionData: sessionData, userID: userID)
        await updateProgress(1.0)
    }
    
    private func uploadSPARCData(sessionData: ComprehensiveSessionData, sessionRef: DocumentReference) async throws {
        let sparcCollection = sessionRef.collection("sparcData")
        
        for (index, sparcPoint) in sessionData.sparcDataOverTime.enumerated() {
            let sparcDoc = sparcCollection.document("point_\(index)")
            let sparcDict: [String: Any] = [
                "timestamp": sparcPoint.timestamp,
                "sparcValue": sparcPoint.sparcValue,
                "movementPhase": sparcPoint.movementPhase,
                "jointAngles": sparcPoint.jointAngles
            ]
            try await sparcDoc.setData(sparcDict)
        }
    }
    
    private func uploadROMData(sessionData: ComprehensiveSessionData, sessionRef: DocumentReference) async throws {
        let romCollection = sessionRef.collection("romData")
        
        for (index, romValue) in sessionData.romPerRep.enumerated() {
            let romDoc = romCollection.document("rep_\(index + 1)")
            let romDict: [String: Any] = [
                "repNumber": index + 1,
                "romValue": romValue,
                "timestamp": sessionData.repTimestamps.indices.contains(index) ? sessionData.repTimestamps[index] : Date(),
                "qualityScore": sessionData.movementQualityScores.indices.contains(index) ? sessionData.movementQualityScores[index] : 0
            ]
            try await romDoc.setData(romDict)
        }
    }
    
    private func updateUserStatistics(sessionData: ComprehensiveSessionData, userID: String) async throws {
        let userRef = db.collection("users").document(userID)
        let statsRef = userRef.collection("statistics").document("overall")
        
        // Get current stats
        let statsDoc = try await statsRef.getDocument()
        var currentStats = statsDoc.data() ?? [:]
        
        // Update cumulative statistics
        let totalSessions = (currentStats["totalSessions"] as? Int ?? 0) + 1
        let totalReps = (currentStats["totalReps"] as? Int ?? 0) + sessionData.totalReps
        let totalExerciseTime = (currentStats["totalExerciseTime"] as? Double ?? 0) + sessionData.duration
        let avgAIScore = calculateRunningAverage(
            current: currentStats["avgAIScore"] as? Double ?? 0,
            newValue: Double(sessionData.aiScore),
            count: totalSessions
        )
        let avgROM = calculateRunningAverage(
            current: currentStats["avgROM"] as? Double ?? 0,
            newValue: sessionData.avgROM,
            count: totalSessions
        )
        
        let updatedStats: [String: Any] = [
            "totalSessions": totalSessions,
            "totalReps": totalReps,
            "totalExerciseTime": totalExerciseTime,
            "avgAIScore": avgAIScore,
            "avgROM": avgROM,
            "lastSessionDate": sessionData.timestamp,
            "currentStreak": calculateStreak(lastSession: sessionData.timestamp, currentStats: currentStats),
            "bestAIScore": max(currentStats["bestAIScore"] as? Int ?? 0, sessionData.aiScore),
            "bestROM": max(currentStats["bestROM"] as? Double ?? 0, sessionData.maxROM)
        ]
        
        try await statsRef.setData(updatedStats, merge: true)
        
        // Update goals if needed
        try await updateGoalsIfNeeded(sessionData: sessionData, userRef: userRef)
    }
    
    private func updateGoalsIfNeeded(sessionData: ComprehensiveSessionData, userRef: DocumentReference) async throws {
        // Only update goals if there's a recommendation
        if sessionData.goalProgressMetrics.goalAdjustmentRecommendation != "Current goals are appropriate" {
            let goalsRef = userRef.collection("goals").document("current")
            try await goalsRef.setData(sessionData.goalsAfterSession.toDictionary(), merge: true)
        }
    }
    
    private func calculateRunningAverage(current: Double, newValue: Double, count: Int) -> Double {
        return ((current * Double(count - 1)) + newValue) / Double(count)
    }
    
    private func calculateStreak(lastSession: Date, currentStats: [String: Any]) -> Int {
        guard let lastSessionDate = currentStats["lastSessionDate"] as? Date else { return 1 }
        
        let calendar = Calendar.current
        let daysBetween = calendar.dateComponents([.day], from: lastSessionDate, to: lastSession).day ?? 0
        
        if daysBetween <= 1 {
            return (currentStats["currentStreak"] as? Int ?? 0) + 1
        } else {
            return 1 // Reset streak
        }
    }
    
    @MainActor
    private func updateProgress(_ progress: Double) {
        uploadProgress = progress
    }
}

enum SessionUploadError: Error, LocalizedError {
    case noUserAuthenticated
    case uploadFailed(String)
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .noUserAuthenticated:
            return "User not authenticated"
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        case .networkError:
            return "Network error occurred"
        }
    }
}

// MARK: - UserGoals Extension
extension UserGoals {
    func toDictionary() -> [String: Any] {
        return [
            "dailyReps": dailyReps,
            "weeklyMinutes": weeklyMinutes,
            "targetROM": targetROM,
            "preferredGames": preferredGames,
            "lastUpdated": Date()
        ]
    }
}
