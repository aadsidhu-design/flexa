import Foundation
import Firebase
import FirebaseFirestore
import FirebaseAuth
import Combine

class FirebaseService: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    
    private let db = Firestore.firestore()
    private let auth = Auth.auth()
    
    init() {
        setupAuthStateListener()
        FlexaLog.firebase.info("FirebaseService initialized")
    }

    // MARK: - SessionFile JSON Upload
    func uploadSessionFile(_ file: SessionFile) async throws {
        guard let userId = auth.currentUser?.uid else { throw FirebaseError.notAuthenticated }
        let dict = file.toDictionary()
        FlexaLog.firebase.info("Upload SessionFile JSON — uid=\(FlexaLog.mask(userId)) type=\(file.exerciseType) reps=\(file.reps) roms=\(file.romPerRep.count) sparc=\(file.sparcHistory.count)")
        do {
            _ = try await db.collection("users").document(userId).collection("sessions_json").addDocument(data: dict)
            FlexaLog.firebase.info("Upload SessionFile JSON success")
        } catch {
            FlexaLog.firebase.error("Upload SessionFile JSON failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    // Count all session documents for current user
    func fetchSessionCount() async throws -> Int {
        guard let userId = auth.currentUser?.uid else { throw FirebaseError.notAuthenticated }
        let snapshot = try await db.collection("users").document(userId).collection("sessions").getDocuments()
        return snapshot.documents.count
    }
    
    private func setupAuthStateListener() {
        auth.addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                self?.isAuthenticated = user != nil
                self?.currentUser = user
                if let u = user {
                    FlexaLog.firebase.info("Auth state: signed in uid=\(FlexaLog.mask(u.uid))")
                } else {
                    FlexaLog.firebase.info("Auth state: signed out")
                }
            }
        }
    }
    
    func signInAnonymously() async throws {
        FlexaLog.firebase.info("Anonymous sign-in start")
        do {
            let result = try await auth.signInAnonymously()
            FlexaLog.firebase.info("Anonymous sign-in success uid=\(FlexaLog.mask(result.user.uid))")
        } catch {
            FlexaLog.firebase.error("Anonymous sign-in failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    func saveExerciseSession(_ session: ExerciseSessionData) async throws {
        guard let userId = auth.currentUser?.uid else { throw FirebaseError.notAuthenticated }
        FlexaLog.firebase.info("Save session start — uid=\(FlexaLog.mask(userId)) game=\(session.exerciseType) reps=\(session.reps) maxROM=\(Int(session.maxROM))")
        var sessionData: [String: Any] = [
            "gameType": session.exerciseType,
            "score": session.score,
            "reps": session.reps,
            "maxROM": session.maxROM,
            "duration": session.duration,
            "timestamp": Timestamp(date: session.timestamp),
            "romData": session.romData.map { ["angle": $0.angle, "timestamp": Timestamp(date: $0.timestamp)] },
            "romHistory": session.romHistory,
            "sparcHistory": session.sparcHistory
        ]
        if let ai = session.aiScore { sessionData["aiScore"] = ai }
        if let pre = session.painPre { sessionData["painPre"] = pre }
        if let post = session.painPost { sessionData["painPost"] = post }
        // Do NOT send accel/gyro fields; they are stored locally only.
        
        do {
            _ = try await db.collection("users").document(userId).collection("sessions").addDocument(data: sessionData)
            FlexaLog.firebase.info("Save session success")
        } catch {
            FlexaLog.firebase.error("Save session failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    func saveComprehensiveSession(_ session: ComprehensiveSessionData) async throws {
        guard let userId = auth.currentUser?.uid else { throw FirebaseError.notAuthenticated }
        FlexaLog.firebase.info("Save comprehensive session start — uid=\(FlexaLog.mask(userId)) name=\(session.exerciseName) reps=\(session.totalReps) dur=\(Int(session.duration))")
        let sessionDict = session.toDictionary()
        do {
            _ = try await db.collection("users").document(userId).collection("sessions").addDocument(data: sessionDict)
            FlexaLog.firebase.info("Save comprehensive session success")
        } catch {
            FlexaLog.firebase.error("Save comprehensive session failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    func fetchExerciseSessions() async throws -> [ExerciseSessionData] {
        guard let userId = auth.currentUser?.uid else { throw FirebaseError.notAuthenticated }
        FlexaLog.firebase.info("Fetch sessions start — uid=\(FlexaLog.mask(userId)) limit=50")
        // Attempt ordered query; if Firestore has mixed types for 'timestamp', fall back to unordered fetch.
        var snapshot: QuerySnapshot
        do {
            snapshot = try await db.collection("users").document(userId).collection("sessions")
                .order(by: "timestamp", descending: true)
                .limit(to: 50)
                .getDocuments()
        } catch {
            FlexaLog.firebase.error("Ordered fetch failed, falling back to unordered: \(error.localizedDescription)")
            snapshot = try await db.collection("users").document(userId).collection("sessions")
                .limit(to: 50)
                .getDocuments()
        }
        FlexaLog.firebase.info("Fetch sessions success — count=\(snapshot.documents.count)")
        let iso = ISO8601DateFormatter()
        
        func anyToDouble(_ any: Any?) -> Double? {
            if let d = any as? Double { return d }
            if let i = any as? Int { return Double(i) }
            if let s = any as? String, let d = Double(s) { return d }
            return nil
        }
        func anyToInt(_ any: Any?) -> Int? {
            if let i = any as? Int { return i }
            if let d = any as? Double { return Int(d) }
            if let s = any as? String, let i = Int(s) { return i }
            return nil
        }
        func parseDate(_ any: Any?) -> Date {
            if let ts = any as? Timestamp { return ts.dateValue() }
            if let s = any as? String, let d = iso.date(from: s) { return d }
            return Date()
        }
        
        let sessions: [ExerciseSessionData] = snapshot.documents.compactMap { doc in
            let data = doc.data()
            // Determine document shape: basic (gameType) or comprehensive (exerciseName)
            if let exerciseName = data["exerciseName"] as? String {
                // ComprehensiveSessionData shape
                let score = anyToInt(data["totalScore"]) ?? 0
                let reps = anyToInt(data["totalReps"]) ?? 0
                let maxROM = anyToDouble(data["maxROM"]) ?? 0
                let duration = anyToDouble(data["duration"]) ?? 0
                let timestamp = parseDate(data["timestamp"]) // ISO8601 string in comprehensive docs
                
                // ROM points derived from romPerRep + repTimestamps if available
                let romPerRep = data["romPerRep"] as? [Any] ?? []
                let repTsRaw = data["repTimestamps"] as? [Any] ?? []
                var repDates: [Date] = repTsRaw.map { parseDate($0) }
                if repDates.count != romPerRep.count {
                    // Fallback: synthesize timestamps spaced by 1s starting at session timestamp
                    repDates = (0..<romPerRep.count).map { i in timestamp.addingTimeInterval(Double(i)) }
                }
                let romPoints: [ROMPoint] = zip(romPerRep, repDates).compactMap { anyValue, date in
                    guard let v = anyToDouble(anyValue) else { return nil }
                    return ROMPoint(angle: v, timestamp: date)
                }
                
                // SPARC average from sparcDataOverTime if present
                var sparcAvg: Double? = nil
                if let sparcArray = data["sparcDataOverTime"] as? [[String: Any]] {
                    let values: [Double] = sparcArray.compactMap { anyToDouble($0["sparcValue"]) }
                    if !values.isEmpty { sparcAvg = values.reduce(0, +) / Double(values.count) }
                }
                
                // Pain levels from nested survey data
                var painPre: Int? = nil
                var painPost: Int? = nil
                if let pre = data["preSurveyData"] as? [String: Any] {
                    painPre = anyToInt(pre["painLevel"]) ?? painPre
                }
                if let post = data["postSurveyData"] as? [String: Any] {
                    painPost = anyToInt(post["painLevel"]) ?? painPost
                }
                
                let aiScore = anyToInt(data["aiScore"]) // May exist on comprehensive docs
                let accelAvg = anyToDouble(data["accelAvgMagnitude"]) 
                let accelPeak = anyToDouble(data["accelPeakMagnitude"]) 
                let gyroAvg = anyToDouble(data["gyroAvgMagnitude"]) 
                let gyroPeak = anyToDouble(data["gyroPeakMagnitude"]) 
                
                return ExerciseSessionData(
                    id: doc.documentID,
                    exerciseType: exerciseName,
                    score: score,
                    reps: reps,
                    maxROM: maxROM,
                    duration: duration,
                    timestamp: timestamp,
                    romHistory: romPerRep.compactMap { anyToDouble($0) },
                    sparcHistory: [],
                    romData: romPoints,
                    sparcData: [],
                    aiScore: aiScore,
                    painPre: painPre,
                    painPost: painPost,
                    sparcScore: sparcAvg ?? 0.0,
                    accelAvgMagnitude: accelAvg,
                    accelPeakMagnitude: accelPeak,
                    gyroAvgMagnitude: gyroAvg,
                    gyroPeakMagnitude: gyroPeak
                )
            } else if let gameType = data["gameType"] as? String {
                // Basic shape saved by saveExerciseSession
                let score = anyToInt(data["score"]) ?? 0
                let reps = anyToInt(data["reps"]) ?? 0
                let maxROM = anyToDouble(data["maxROM"]) ?? 0
                let duration = anyToDouble(data["duration"]) ?? 0
                let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() ?? Date()
                let romHistory = (data["romHistory"] as? [Any] ?? []).compactMap { anyToDouble($0) }
                let sparcHistory = (data["sparcHistory"] as? [Any] ?? []).compactMap { anyToDouble($0) }
                // Legacy romData
                var romPoints: [ROMPoint] = []
                if let rawRomData = data["romData"] as? [[String: Any]] {
                    romPoints = rawRomData.compactMap { d in
                        guard let angle = anyToDouble(d["angle"]) else { return nil }
                        let ts = (d["timestamp"] as? Timestamp)?.dateValue() ?? timestamp
                        return ROMPoint(angle: angle, timestamp: ts)
                    }
                }
                let aiScore = anyToInt(data["aiScore"]) 
                let painPre = anyToInt(data["painPre"]) 
                let painPost = anyToInt(data["painPost"]) 
                let accelAvg = anyToDouble(data["accelAvgMagnitude"]) 
                let accelPeak = anyToDouble(data["accelPeakMagnitude"]) 
                let gyroAvg = anyToDouble(data["gyroAvgMagnitude"]) 
                let gyroPeak = anyToDouble(data["gyroPeakMagnitude"]) 
                return ExerciseSessionData(
                    id: doc.documentID,
                    exerciseType: gameType,
                    score: score,
                    reps: reps,
                    maxROM: maxROM,
                    duration: duration,
                    timestamp: timestamp,
                    romHistory: romHistory,
                    sparcHistory: sparcHistory,
                    romData: romPoints,
                    sparcData: [],
                    aiScore: aiScore,
                    painPre: painPre,
                    painPost: painPost,
                    sparcScore: 0.0,
                    accelAvgMagnitude: accelAvg,
                    accelPeakMagnitude: accelPeak,
                    gyroAvgMagnitude: gyroAvg,
                    gyroPeakMagnitude: gyroPeak
                )
            } else {
                return nil
            }
        }
        
        // Sort client-side by timestamp ascending for consistent graphing
        FlexaLog.firebase.debug("Parsed sessions count=\(sessions.count)")
        return sessions.sorted(by: { $0.timestamp < $1.timestamp })
    }
    
    func saveUserGoals(_ goals: UserGoals) async throws {
        guard let userId = auth.currentUser?.uid else { throw FirebaseError.notAuthenticated }
        FlexaLog.firebase.info("Save user goals start — uid=\(FlexaLog.mask(userId)) daily=\(goals.dailyReps) weekly=\(goals.weeklyMinutes) targetROM=\(Int(goals.targetROM))")
        let goalsData: [String: Any] = [
            "dailyReps": goals.dailyReps,
            "weeklyMinutes": goals.weeklyMinutes,
            "targetROM": goals.targetROM,
            "preferredGames": goals.preferredGames,
            "lastUpdated": Timestamp(date: Date())
        ]
        
        do {
            try await db.collection("users").document(userId).setData(["goals": goalsData], merge: true)
            FlexaLog.firebase.info("Save user goals success")
        } catch {
            FlexaLog.firebase.error("Save user goals failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    func fetchUserGoals() async throws -> UserGoals? {
        guard let userId = auth.currentUser?.uid else { throw FirebaseError.notAuthenticated }
        FlexaLog.firebase.info("Fetch user goals start — uid=\(FlexaLog.mask(userId))")
        let doc = try await db.collection("users").document(userId).getDocument()
        guard let data = doc.data(),
              let goalsData = data["goals"] as? [String: Any] else { return nil }
        FlexaLog.firebase.info("Fetch user goals success")
        return UserGoals(
            dailyReps: goalsData["dailyReps"] as? Int ?? 50,
            weeklyMinutes: goalsData["weeklyMinutes"] as? Int ?? 150,
            targetROM: goalsData["targetROM"] as? Double ?? 90,
            preferredGames: goalsData["preferredGames"] as? [String] ?? []
        )
    }
    
    func updateStreak(_ streak: StreakData) async throws {
        guard let userId = auth.currentUser?.uid else { throw FirebaseError.notAuthenticated }
        FlexaLog.firebase.info("Update streak start — uid=\(FlexaLog.mask(userId)) current=\(streak.currentStreak) longest=\(streak.longestStreak)")
        let streakData: [String: Any] = [
            "currentStreak": streak.currentStreak,
            "longestStreak": streak.longestStreak,
            "lastExerciseDate": Timestamp(date: streak.lastExerciseDate),
            "totalDays": streak.totalDays
        ]
        
        do {
            try await db.collection("users").document(userId).setData(["streak": streakData], merge: true)
            FlexaLog.firebase.info("Update streak success")
        } catch {
            FlexaLog.firebase.error("Update streak failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    func fetchStreak() async throws -> StreakData {
        guard let userId = auth.currentUser?.uid else { throw FirebaseError.notAuthenticated }
        FlexaLog.firebase.info("Fetch streak start — uid=\(FlexaLog.mask(userId))")
        let doc = try await db.collection("users").document(userId).getDocument()
        guard let data = doc.data(),
              let streakData = data["streak"] as? [String: Any] else {
            FlexaLog.firebase.info("Fetch streak: none found, returning defaults")
            return StreakData()
        }
        FlexaLog.firebase.info("Fetch streak success")
        return StreakData(
            currentStreak: streakData["currentStreak"] as? Int ?? 0,
            longestStreak: streakData["longestStreak"] as? Int ?? 0,
            lastExerciseDate: (streakData["lastExerciseDate"] as? Timestamp)?.dateValue() ?? Date.distantPast,
            totalDays: streakData["totalDays"] as? Int ?? 0
        )
    }
    
    func clearAllUserData() async throws {
        guard let userId = auth.currentUser?.uid else { throw FirebaseError.notAuthenticated }
        let userRef = db.collection("users").document(userId)
        
        // Delete all session documents
        let sessionsSnapshot = try await userRef.collection("sessions").getDocuments()
        FlexaLog.firebase.info("Clear user data — deleting \(sessionsSnapshot.documents.count) sessions for uid=\(FlexaLog.mask(userId))")
        for doc in sessionsSnapshot.documents {
            try await userRef.collection("sessions").document(doc.documentID).delete()
        }
        
        // Remove goals and streak fields
        try await userRef.updateData([
            "goals": FieldValue.delete(),
            "streak": FieldValue.delete()
        ])
        FlexaLog.firebase.info("Clear user data success")
    }
}

enum FirebaseError: Error {
    case notAuthenticated
    case invalidData
}

struct ExerciseSessionData: Identifiable, Codable {
    let id: String
    let exerciseType: String // Renamed from gameType for clarity
    let score: Int
    let reps: Int
    let maxROM: Double
    let averageROM: Double // Average ROM across all reps
    let duration: TimeInterval
    let timestamp: Date
    let romHistory: [Double] // ROM per individual rep
    var sparcHistory: [Double] // SPARC per individual rep
    let romData: [ROMPoint] // For backwards compatibility
    let sparcData: [SPARCPoint] // For backwards compatibility
    let aiScore: Int?
    let painPre: Int?
    let painPost: Int?
    var sparcScore: Double // Overall SPARC score
    let formScore: Double
    let consistency: Double
    let peakVelocity: Double
    let motionSmoothnessScore: Double
    // Optional sensor aggregates
    let accelAvgMagnitude: Double?
    let accelPeakMagnitude: Double?
    let gyroAvgMagnitude: Double?
    let gyroPeakMagnitude: Double?

    init(id: String = UUID().uuidString, exerciseType: String, score: Int, reps: Int, maxROM: Double, averageROM: Double = 0, duration: TimeInterval, timestamp: Date = Date(), romHistory: [Double] = [], sparcHistory: [Double] = [], romData: [ROMPoint] = [], sparcData: [SPARCPoint] = [], aiScore: Int? = nil, painPre: Int? = nil, painPost: Int? = nil, sparcScore: Double = 0, formScore: Double = 0, consistency: Double = 0, peakVelocity: Double = 0, motionSmoothnessScore: Double = 0, accelAvgMagnitude: Double? = nil, accelPeakMagnitude: Double? = nil, gyroAvgMagnitude: Double? = nil, gyroPeakMagnitude: Double? = nil) {
        self.id = id
        self.exerciseType = exerciseType
        self.score = score
        self.reps = reps
        self.maxROM = maxROM
        self.averageROM = averageROM
        self.duration = duration
        self.timestamp = timestamp
        self.romHistory = romHistory
        self.sparcHistory = sparcHistory
        self.romData = romData
        self.sparcData = sparcData
        self.aiScore = aiScore
        self.painPre = painPre
        self.painPost = painPost
        self.sparcScore = sparcScore
        self.formScore = formScore
        self.consistency = consistency
        self.peakVelocity = peakVelocity
        self.motionSmoothnessScore = motionSmoothnessScore
        self.accelAvgMagnitude = accelAvgMagnitude
        self.accelPeakMagnitude = accelPeakMagnitude
        self.gyroAvgMagnitude = gyroAvgMagnitude
        self.gyroPeakMagnitude = gyroPeakMagnitude
    }
}

struct ROMPoint: Codable {
    let angle: Double
    let timestamp: Date
}

struct SPARCPoint: Codable {
    let sparc: Double
    let timestamp: Date
}

struct UserGoals: Codable {
    let dailyReps: Int
    let weeklyMinutes: Int
    let targetROM: Double
    let preferredGames: [String]
    
    init(dailyReps: Int = 50, weeklyMinutes: Int = 150, targetROM: Double = 90, preferredGames: [String] = []) {
        self.dailyReps = dailyReps
        self.weeklyMinutes = weeklyMinutes
        self.targetROM = targetROM
        self.preferredGames = preferredGames
    }
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
