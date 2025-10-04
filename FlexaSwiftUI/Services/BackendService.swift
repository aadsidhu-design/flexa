import Foundation
import Combine

/// Primary backend facade for Flexa, delegating persistence to `FirebaseService`.
class BackendService: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: BackendUser?
    @Published var firebaseDiagnostics: FirebaseHealthDiagnostics?

    private let uploadQueue = OfflineUploadQueue()
    private let firebaseService = FirebaseService()
    private let localDataManager = LocalDataManager.shared
    private var anonymousUserId: String?
    private let anonymousUserDefaultsKey = "backend_anonymous_user_id"

    init() {
        setupAnonymousUser()
        FlexaLog.backend.info("BackendService initialized; delegating to FirebaseService")
    }

    var currentUserId: String? {
        anonymousUserId
    }

    private func setupAnonymousUser() {
        if let existingId = UserDefaults.standard.string(forKey: anonymousUserDefaultsKey) {
            self.anonymousUserId = existingId
            self.currentUser = BackendUser(uid: existingId)
            self.isAuthenticated = false
        }
    }

    func ensureAuthenticated() async throws {
        let user = try await firebaseService.signInAnonymously(existingUserId: anonymousUserId)
        await MainActor.run {
            if self.anonymousUserId == nil {
                self.anonymousUserId = user.uid
                UserDefaults.standard.set(user.uid, forKey: self.anonymousUserDefaultsKey)
            }
            self.currentUser = BackendUser(uid: user.uid)
            self.isAuthenticated = true
        }
    }

    // MARK: - Authentication
    func signInAnonymously() async throws {
        let firebaseUser = try await firebaseService.signInAnonymously(existingUserId: anonymousUserId)
        UserDefaults.standard.set(firebaseUser.uid, forKey: anonymousUserDefaultsKey)
        await MainActor.run {
            self.anonymousUserId = firebaseUser.uid
            self.currentUser = BackendUser(uid: firebaseUser.uid)
            self.isAuthenticated = true
        }

        FlexaLog.backend.info("Backend anonymous sign-in uid=\(FlexaLog.mask(firebaseUser.uid))")
    }

    func runFirebaseDiagnostics() async {
        let diagnostics = await firebaseService.runDiagnostics(existingUserId: anonymousUserId)
        FlexaLog.backend.info("Firebase diagnostics → \(diagnostics.logSummary)")
        await MainActor.run {
            self.firebaseDiagnostics = diagnostics
        }
    }

    // MARK: - Session Upload
    func saveSession(_ session: ExerciseSessionData, sessionFile: SessionFile?, comprehensive: ComprehensiveSessionData?) async {
        do {
            try await ensureAuthenticated()
        } catch {
            FlexaLog.backend.error("Firebase upload skipped — authentication failed error=\(error.localizedDescription)")
            uploadQueue.queueForUpload(comprehensive ?? session.toComprehensiveFallback())
            return
        }

        guard let userId = anonymousUserId else {
            FlexaLog.backend.error("Firebase upload skipped — user not authenticated")
            uploadQueue.queueForUpload(comprehensive ?? session.toComprehensiveFallback())
            return
        }

        var payload: [String: Any] = [
            "userId": userId,
            "sessionId": session.id,
            "exerciseName": session.exerciseType,
            "score": session.score,
            "reps": session.reps,
            "maxROM": session.maxROM,
            "averageROM": session.averageROM,
            "duration": session.duration,
            "timestamp": session.timestamp,
            "sparcScore": session.sparcScore,
            "formScore": session.formScore,
            "consistency": session.consistency,
            "peakVelocity": session.peakVelocity,
            "motionSmoothnessScore": session.motionSmoothnessScore,
            "romPerRep": session.romHistory,
            "sparcHistory": session.sparcHistory,
            "romData": session.romData.map { ["angle": $0.angle, "timestamp": $0.timestamp] },
            "sparcTimeline": session.sparcData.map { ["timestamp": $0.timestamp, "sparc": $0.sparc] },
            "updatedAt": Date()
        ]

        if let aiScore = session.aiScore { payload["aiScore"] = aiScore }
        if let painPre = session.painPre { payload["painPre"] = painPre }
        if let painPost = session.painPost { payload["painPost"] = painPost }
        if let accelAvg = session.accelAvgMagnitude { payload["accelAvgMagnitude"] = accelAvg }
        if let accelPeak = session.accelPeakMagnitude { payload["accelPeakMagnitude"] = accelPeak }
        if let gyroAvg = session.gyroAvgMagnitude { payload["gyroAvgMagnitude"] = gyroAvg }
        if let gyroPeak = session.gyroPeakMagnitude { payload["gyroPeakMagnitude"] = gyroPeak }
        if let aiFeedback = session.aiFeedback { payload["aiFeedback"] = aiFeedback }
        if let goalsAfter = session.goalsAfter {
            payload["goalsAfter"] = encodeGoals(goalsAfter)
        }

        if let file = sessionFile {
            payload["rawSessionFile"] = file.toDictionary()
        }

        let sessionNumberForMetadata: Int
        if let comprehensive {
            payload["comprehensive"] = comprehensive.toDictionary()
            sessionNumberForMetadata = comprehensive.sessionNumber
        } else {
            sessionNumberForMetadata = localDataManager.getLastSessionNumber()
        }
        payload["sessionNumber"] = sessionNumberForMetadata

        let sanitizedPayload = FirebasePayloadSanitizer.sanitizeDictionary(payload)

        do {
            try await firebaseService.saveSession(userId: userId, sessionId: session.id, sessionData: sanitizedPayload)
            try await firebaseService.updateSessionMetadata(userId: userId, latestSessionNumber: sessionNumberForMetadata)
            FlexaLog.backend.info("Firebase: saved session id=\(session.id)")
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .sessionUploadCompleted,
                    object: nil,
                    userInfo: ["sessionId": session.id]
                )
            }
        } catch {
            FlexaLog.backend.error("Firebase: failed to save session id=\(session.id) error=\(error.localizedDescription)")
            uploadQueue.queueForUpload(comprehensive ?? session.toComprehensiveFallback())
        }
    }

    func fetchExerciseSessions() async throws -> [ExerciseSessionData] {
        return localDataManager.getStoredSessions()
    }

    func saveUserGoals(_ goals: UserGoals) async throws {
        try await ensureAuthenticated()
        guard let userId = anonymousUserId else { throw BackendError.notAuthenticated }
        try await firebaseService.saveUserGoals(userId: userId, goals: goals)
        localDataManager.saveGoals(goals)
    }

    func fetchUserGoals() async throws -> UserGoals? {
        return localDataManager.getStoredGoals()
    }

    func updateStreak(_ streak: StreakData) async throws {
        try await ensureAuthenticated()
        guard let userId = anonymousUserId else { throw BackendError.notAuthenticated }
        try await firebaseService.updateStreak(userId: userId, streak: streak)
        localDataManager.saveStreak(streak)
    }

    func fetchStreak() async throws -> StreakData {
        return localDataManager.getCachedStreak()
    }

    func clearAllUserData() async throws {
        localDataManager.clearLocalData()
        FlexaLog.backend.info("Backend clearAllUserData executed (local caches cleared)")
        do {
            try await refreshSessionSequenceBaseFromCloud()
        } catch {
            FlexaLog.backend.error("Failed to refresh session sequence base after clear: \(error.localizedDescription)")
        }
    }

    func seedSessionSequenceIfNeeded() async {
        guard localDataManager.shouldSeedSessionSequenceFromRemote() else { return }
        do {
            try await ensureAuthenticated()
            guard let userId = anonymousUserId else { throw BackendError.notAuthenticated }
            let document = try await firebaseService.fetchUserDocument(userId: userId)
            let latest = extractInt(document?.fields["latestSessionNumber"]) ?? 0
            localDataManager.markSessionSequenceSeeded(with: latest)
            FlexaLog.backend.info("Session numbering reseeded from cloud (latest=\(latest))")
        } catch {
            FlexaLog.backend.error("Failed to seed session numbering: \(error.localizedDescription)")
        }
    }

    func refreshSessionSequenceBaseFromCloud() async throws {
        try await ensureAuthenticated()
        guard let userId = anonymousUserId else { throw BackendError.notAuthenticated }
        let document = try await firebaseService.fetchUserDocument(userId: userId)
        let latest = extractInt(document?.fields["latestSessionNumber"]) ?? 0
        localDataManager.markSessionSequenceSeeded(with: latest)
        FlexaLog.backend.info("Session sequence base refreshed from cloud: \(latest)")
    }

    private func extractInt(_ value: Any?) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let int64 as Int64:
            return Int(int64)
        case let string as String:
            return Int(string)
        case let double as Double:
            return Int(double)
        default:
            return nil
        }
    }

}

private func encodeGoals(_ goals: UserGoals) -> [String: Any] {
    let encoder = JSONEncoder()
    if let data = try? encoder.encode(goals),
       let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        return object
    }
    return [:]
}

extension ExerciseSessionData {
    fileprivate func toComprehensiveFallback() -> ComprehensiveSessionData {
        let performance = ExercisePerformanceData(
            score: score,
            reps: reps,
            duration: duration,
            romData: romHistory,
            romPerRep: romHistory,
            repTimestamps: [],
            sparcDataPoints: sparcData.map { SPARCDataPoint(timestamp: $0.timestamp, sparcValue: $0.sparc, movementPhase: "", jointAngles: [:]) },
            movementQualityScores: sparcHistory,
            aiScore: aiScore ?? 0,
            aiFeedback: aiFeedback ?? "",
            sparcScore: sparcScore,
            gameSpecificData: exerciseType,
            accelAvg: accelAvgMagnitude,
            accelPeak: accelPeakMagnitude,
            gyroAvg: gyroAvgMagnitude,
            gyroPeak: gyroPeakMagnitude
        )

        return ComprehensiveSessionData(
            userID: "local",
            sessionNumber: 0,
            exerciseName: exerciseType,
            duration: duration,
            performanceData: performance,
            preSurvey: PreSurveyData(painLevel: painPre ?? 0, timestamp: timestamp, exerciseReadiness: nil, previousExerciseHours: nil),
            postSurvey: nil,
            goalsBefore: goalsAfter ?? UserGoals(),
            goalsAfter: goalsAfter ?? UserGoals()
        )
    }
}

// MARK: - Supporting Types
struct BackendUser {
    let uid: String
}

enum BackendError: Error {
    case notAuthenticated
    case invalidData
    case connectionFailed
}

struct StreakData: Codable {
    let currentStreak: Int
    let longestStreak: Int
    let lastExerciseDate: Date
    let totalDays: Int
    
    init(currentStreak: Int = 0, longestStreak: Int = 0, lastExerciseDate: Date = Date.distantPast, totalDays: Int = 0) {
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.lastExerciseDate = lastExerciseDate
        self.totalDays = totalDays
    }
}

extension Notification.Name {
    static let sessionUploadCompleted = Notification.Name("SessionUploadCompleted")
}
