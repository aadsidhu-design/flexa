import Foundation
import Combine

class AppwriteService: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: AppwriteUser?

    private let endpoint: URL?
    private let apiKey: String?
    private let projectId: String?
    private let databaseId: String
    private let networkMonitor = NetworkMonitor()
    private var collectionIdMap: [String: String] = [:]

    init() {
        // Read endpoint and api key from Info.plist or environment (matches SecureConfig approach)
        if let ep = Bundle.main.object(forInfoDictionaryKey: "APPWRITE_ENDPOINT") as? String {
            self.endpoint = URL(string: ep)
        } else if let env = ProcessInfo.processInfo.environment["APPWRITE_ENDPOINT"] {
            self.endpoint = URL(string: env)
        } else {
            self.endpoint = nil
        }

        // Prefer a server key stored in Keychain (APPWRITE_SERVER_KEY), fall back to APPWRITE_API_KEY in Keychain / env / Info.plist
        if let serverKey = KeychainManager.shared.getString(for: "APPWRITE_SERVER_KEY") {
            self.apiKey = serverKey
        } else if let keychainKey = KeychainManager.shared.getString(for: "APPWRITE_API_KEY") {
            self.apiKey = keychainKey
        } else if let envKey = ProcessInfo.processInfo.environment["APPWRITE_API_KEY"] {
            self.apiKey = envKey
        } else if let plistKey = Bundle.main.object(forInfoDictionaryKey: "APPWRITE_API_KEY") as? String {
            self.apiKey = plistKey
        } else {
            self.apiKey = nil
        }

        if endpoint != nil && apiKey != nil {
            self.isAuthenticated = true
            self.currentUser = AppwriteUser(uid: UUID().uuidString)
        }

        // Read optional project and database id (defaults to "default")
        if let env = ProcessInfo.processInfo.environment["APPWRITE_PROJECT_ID"] {
            self.projectId = env
        } else if let proj = Bundle.main.object(forInfoDictionaryKey: "APPWRITE_PROJECT_ID") as? String {
            self.projectId = proj
        } else {
            self.projectId = "68d2402e00145561045b" // Flexatest project ID
        }

        if let envdb = ProcessInfo.processInfo.environment["APPWRITE_DATABASE_ID"] {
            self.databaseId = envdb
        } else if let db = Bundle.main.object(forInfoDictionaryKey: "APPWRITE_DATABASE_ID") as? String {
            self.databaseId = db
        } else {
            self.databaseId = "68d3628b0022f1b6e78b" // FlexaTestDatabase id (provided)
        }

        // Load optional explicit collection IDs from Info.plist so deployments can
        // configure real Appwrite collection GUIDs without changing code.
        var map: [String: String] = [:]
        if let sessionsId = Bundle.main.object(forInfoDictionaryKey: "APPWRITE_COLLECTION_SESSIONS") as? String {
            map["sessions"] = sessionsId
        }
        if let sessionsJsonId = Bundle.main.object(forInfoDictionaryKey: "APPWRITE_COLLECTION_SESSIONS_JSON") as? String {
            map["sessions_json"] = sessionsJsonId
        }
        if let goalsId = Bundle.main.object(forInfoDictionaryKey: "APPWRITE_COLLECTION_USER_GOALS") as? String {
            map["user_goals"] = goalsId
        }
        if let streaksId = Bundle.main.object(forInfoDictionaryKey: "APPWRITE_COLLECTION_USER_STREAKS") as? String {
            map["user_streaks"] = streaksId
        }
        self.collectionIdMap = map

        FlexaLog.backend.info("AppwriteService initialized; endpoint configured=\(self.endpoint != nil) database=\(self.databaseId)")
    }

    func uploadSessionFile(_ file: SessionFile) async throws {
        let payload: [String: Any] = [
            "userId": UserDefaults.standard.string(forKey: "backend_anonymous_user_id") ?? "",
            "exerciseType": file.exerciseType,
            "timestamp": file.timestamp.timeIntervalSince1970,
            "romPerRep": file.romPerRep,
            "sparcHistory": file.sparcHistory,
            "romHistory": file.romHistory,
            "maxROM": file.maxROM,
            "reps": file.reps,
            "sparcDataPoints": file.sparcDataPoints.map { point in
                [
                    "timestamp": point.timestamp.timeIntervalSince1970,
                    "sparc": point.sparc
                ]
            }
        ]

        try await postDocument(collection: "sessions_json", data: payload)
    }

    func saveExerciseSession(_ session: ExerciseSessionData) async {
        var sessionData: [String: Any] = [
            "userId": UserDefaults.standard.string(forKey: "backend_anonymous_user_id") ?? "",
            "exerciseName": session.exerciseType,
            "gameType": session.exerciseType,
            "score": session.score,
            "reps": session.reps,
            "maxROM": session.maxROM,
            "averageROM": session.averageROM,
            "duration": session.duration,
            "timestamp": session.timestamp.timeIntervalSince1970,
            "romData": session.romData.map { ["angle": $0.angle, "timestamp": $0.timestamp.timeIntervalSince1970] },
            "romHistory": session.romHistory,
            "sparcHistory": session.sparcHistory,
            "sparcScore": session.sparcScore
        ]

        if let ai = session.aiScore { sessionData["aiScore"] = ai }
        if let feedback = session.aiFeedback { sessionData["aiFeedback"] = feedback }
        if let pre = session.painPre { sessionData["painPre"] = pre }
        if let post = session.painPost { sessionData["painPost"] = post }
        if let goals = session.goalsAfter {
            sessionData["goalsAfter"] = [
                "dailyReps": goals.dailyReps,
                "weeklyMinutes": goals.weeklyMinutes,
                "targetROM": goals.targetROM,
                "preferredGames": goals.preferredGames
            ]
        }

        do {
            try await postDocument(collection: "sessions", data: sessionData)
            FlexaLog.backend.info("Appwrite: saved exercise session uid=")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .sessionUploadCompleted, object: nil, userInfo: ["session": session])
            }
        } catch {
            FlexaLog.backend.error("Appwrite: failed to save exercise session: \(error.localizedDescription)")
        }
    }

    func saveComprehensiveSession(_ session: ComprehensiveSessionData) async throws {
        var dict = session.toDictionary()
        dict["userId"] = UserDefaults.standard.string(forKey: "backend_anonymous_user_id") ?? ""
        try await postDocument(collection: "sessions", data: dict)
    }

    // Save user goals to Appwrite (used by GoalsAndStreaksService/Azure shim)
    func saveUserGoals(_ goals: UserGoals) async throws {
        let userId = UserDefaults.standard.string(forKey: "backend_anonymous_user_id") ?? ""
        let goalsData: [String: Any] = [
            "userId": userId,
            "dailyReps": goals.dailyReps,
            "weeklyMinutes": goals.weeklyMinutes,
            "targetROM": goals.targetROM,
            "preferredGames": goals.preferredGames,
            "lastUpdated": Date().timeIntervalSince1970
        ]

        try await postDocument(collection: "user_goals", data: goalsData)
    }

    // MARK: - HTTP helpers
    func postDocument(collection: String, data: [String: Any]) async throws {
        // If network is down or endpoint not configured, use offline queue
        guard networkMonitor.isConnected, let endpoint = endpoint, let apiKey = apiKey else {
            FlexaLog.backend.warning("AppwriteService offline or not configured; dropping payload for collection=\(collection)")
            return
        }
        // Support a small mapping from legacy logical collection names to actual Appwrite collection IDs
        let collectionName: String
        // If an explicit collection ID is configured, prefer that mapping
        if let mapped = collectionIdMap[collection] {
            collectionName = mapped
        } else {
            switch collection {
            case "sessions", "sessions_json":
                collectionName = "maintable" // mapped to the MainTable created in FlexaTestDatabase
            default:
                collectionName = collection
            }
        }
        // Build URL robustly so endpoint may or may not include the /v1 path
        // e.g. endpoint = https://sfo.cloud.appwrite.io or https://sfo.cloud.appwrite.io/v1
        let url = endpoint
            .appendingPathComponent("databases")
            .appendingPathComponent(databaseId)
            .appendingPathComponent("collections")
            .appendingPathComponent(collectionName)
            .appendingPathComponent("documents")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // apiKey is bound by the guard above and is non-optional in this scope
        request.setValue(apiKey, forHTTPHeaderField: "X-Appwrite-API-Key")
        // If a project id is configured, include it (some Appwrite setups require X-Appwrite-Project)
        if let proj = projectId {
            request.setValue(proj, forHTTPHeaderField: "X-Appwrite-Project")
        }

        // Compose the Appwrite document envelope. Include optional per-document permissions
        var sanitizedData = data
        var explicitId: String?
        if let provided = sanitizedData.removeValue(forKey: "documentId") as? String {
            explicitId = provided
        } else if let provided = sanitizedData.removeValue(forKey: "$id") as? String {
            explicitId = provided
        }
        var payload: [String: Any] = [
            "documentId": explicitId ?? "unique()",
            "data": sanitizedData
        ]

        // If the app has a configured service user id in Keychain, assign read/write to that user
        if let serviceUser = KeychainManager.shared.getString(for: "APPWRITE_SERVICE_USER_ID"), !serviceUser.isEmpty {
            payload["read"] = ["user:\(serviceUser)"]
            payload["write"] = ["user:\(serviceUser)"]
        }

        let bodyData = try JSONSerialization.data(withJSONObject: payload, options: [])
        request.httpBody = bodyData

        let (dataResp, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            if !(200...299).contains(http.statusCode) {
                let msg = String(data: dataResp, encoding: .utf8) ?? ""
                FlexaLog.backend.error("Appwrite: bad status \(http.statusCode) for collection=\(collectionName) body=\(msg)")
                // If route not found (404) or other error, safely enqueue to offline queue so data isn't lost
                if http.statusCode == 404 {
                    FlexaLog.backend.warning("Appwrite: 404 route not found; payload not persisted: collection=\(collectionName)")
                }
                throw NSError(domain: "AppwriteService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Bad status \(http.statusCode): \(msg)"])
            } else {
                // Try to extract the created document id from Appwrite response (usually in "$id")
                if let json = try? JSONSerialization.jsonObject(with: dataResp, options: []) as? [String: Any] {
                    let docId = (json["$id"] as? String) ?? (json["id"] as? String)
                    if let id = docId {
                        FlexaLog.backend.info("Appwrite: posted document to \(collection) id=\(id)")
                    } else {
                        FlexaLog.backend.info("Appwrite: posted document to \(collection) (no id found in response)")
                    }
                } else {
                    FlexaLog.backend.info("Appwrite: posted document to \(collection) (non-json response)")
                }
            }
        }
    }
}

struct AppwriteUser { let uid: String }
