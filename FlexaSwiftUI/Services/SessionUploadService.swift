import Foundation

enum UploadError: Error, LocalizedError {
    case invalidData([String])
    case serializationFailed(Error)
    case networkError(Error)
    case authenticationFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidData(let errors):
            return "Data validation failed: \(errors.joined(separator: ", "))"
        case .serializationFailed(let error):
            return "Data serialization failed: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .authenticationFailed(let error):
            return "Authentication failed: \(error.localizedDescription)"
        }
    }
}

class SessionUploadService: ObservableObject {
    private let firebaseService = FirebaseService()
    @Published var uploadProgress: Double = 0
    @Published var isUploading = false
    
    func uploadSessionData(
        _ sessionData: ComprehensiveSessionData,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        isUploading = true
        uploadProgress = 0
        
        Task {
            do {
                try await uploadInBackground(sessionData: sessionData)
                await MainActor.run {
                    self.isUploading = false
                    self.uploadProgress = 1.0
                    Logger.shared.info("Upload succeeded for session: \(sessionData.id)")
                    completion(.success(()))
                }
            } catch {
                await MainActor.run {
                    self.isUploading = false
                    self.uploadProgress = 0
                    Logger.shared.error("Upload failed for session: \(sessionData.id) error: \(error.localizedDescription)")
                    completion(.failure(error))
                }
            }
        }
    }
    
    private func uploadInBackground(sessionData: ComprehensiveSessionData) async throws {
        Logger.shared.info("Starting upload for session: \(sessionData.id)")
        await updateProgress(0.1)
        
        // Validate data before upload
        let validation = sessionData.validateData()
        if !validation.isValid {
            Logger.shared.error("Session data validation failed: \(validation.errors.joined(separator: ", "))")
            throw UploadError.invalidData(validation.errors)
        }
        Logger.shared.info("Session data validation passed")

        let userId: String
        if let existingId = UserDefaults.standard.string(forKey: "backend_anonymous_user_id"), !existingId.isEmpty {
            userId = existingId
        } else {
            let user = try await firebaseService.signInAnonymously(existingUserId: nil)
            userId = user.uid
            UserDefaults.standard.set(userId, forKey: "backend_anonymous_user_id")
        }

        var payload = sessionData.toDictionary()
        payload["uploadedAt"] = ISO8601DateFormatter().string(from: Date())
        payload["uploadVersion"] = "2.0"
        
        // Log payload structure for debugging
        Logger.shared.info("Upload payload structure - keys: \(payload.keys.sorted().joined(separator: ", "))")
        Logger.shared.info("Exercise: \(sessionData.exerciseName), Reps: \(sessionData.totalReps), Duration: \(sessionData.duration)")
        
        // Ensure payload is JSON serializable
        do {
            let _ = try JSONSerialization.data(withJSONObject: payload, options: [])
            Logger.shared.info("Payload JSON serialization check passed")
        } catch {
            Logger.shared.error("Payload serialization check failed: \(error)")
            throw UploadError.serializationFailed(error)
        }
        payload["sessionNumber"] = sessionData.sessionNumber

        try await firebaseService.saveSession(
            userId: userId,
            sessionId: sessionData.id,
            sessionData: ["comprehensive": payload]
        )

        try await firebaseService.updateSessionMetadata(
            userId: userId,
            latestSessionNumber: sessionData.sessionNumber
        )

        await updateProgress(1.0)
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
