import Foundation


final class FirebaseService: ObservableObject {
    struct FirebaseUser {
        let uid: String
    }

    struct FirestoreDocument {
        let name: String
        let fields: [String: Any]
        let createTime: Date?
        let updateTime: Date?
    }

    @Published private(set) var isAuthenticated = false
    @Published private(set) var currentUser: FirebaseUser?

    private let session: URLSession
    private let apiKey: String
    private let projectId: String
    private let firestoreBaseURL: URL?
    private let identityBaseURL = URL(string: "https://identitytoolkit.googleapis.com/v1")!
    private let secureTokenURL = URL(string: "https://securetoken.googleapis.com/v1/token")!
    private let refreshTokenKey = "FIREBASE_REFRESH_TOKEN"

    private var idToken: String?
    private var tokenExpiry: Date?
    private var refreshToken: String? {
        didSet {
            if let token = refreshToken {
                _ = KeychainManager.shared.store(token, for: refreshTokenKey)
            } else {
                _ = KeychainManager.shared.delete(for: refreshTokenKey)
            }
        }
    }

    // Cache session payloads so repeated writes send full data.
    private var sessionDocumentCache: [String: [String: Any]] = [:]
    private let cacheQueue = DispatchQueue(label: "com.flexa.firebaseSessionCache")

    init(session: URLSession = .shared) {
        self.session = session
        self.apiKey = SecureConfig.shared.firebaseAPIKey
        self.projectId = SecureConfig.shared.firebaseProjectId
        if !projectId.isEmpty {
            self.firestoreBaseURL = URL(string: "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/(default)/documents")
        } else {
            self.firestoreBaseURL = nil
        }

        if let storedRefresh = KeychainManager.shared.getString(for: refreshTokenKey) {
            self.refreshToken = storedRefresh
        }
    }

    // MARK: - Authentication

    func signInAnonymously(existingUserId: String?) async throws -> FirebaseUser {
        if let user = currentUser, tokenIsValid() {
            return user
        }

        if let refreshToken = refreshToken {
            do {
                let refreshedUser = try await refreshIdToken(refreshToken: refreshToken)
                await updateAuthState(user: refreshedUser)
                return refreshedUser
            } catch {
                FlexaLog.backend.error("Firebase refresh token failed: \(error.localizedDescription)")
                self.refreshToken = nil
            }
        }

        let url = identityBaseURL.appendingPathComponent("accounts:signUp")
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw FirebaseServiceError.invalidConfiguration
        }
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let finalURL = components.url else { throw FirebaseServiceError.invalidConfiguration }

        var request = URLRequest(url: finalURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "returnSecureToken": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data, context: "signInAnonymously")

    let signUp = try JSONDecoder().decode(SignUpResponse.self, from: data)
    self.idToken = signUp.idToken
    self.refreshToken = signUp.refreshToken
    let expiresSeconds = Double(signUp.expiresIn ?? "3600") ?? 3600
    self.tokenExpiry = Date().addingTimeInterval(expiresSeconds - 60)
        let user = FirebaseUser(uid: signUp.localId)
    await updateAuthState(user: user)
        return user
    }

    private func refreshIdToken(refreshToken: String) async throws -> FirebaseUser {
        guard var components = URLComponents(url: secureTokenURL, resolvingAgainstBaseURL: false) else {
            throw FirebaseServiceError.invalidConfiguration
        }
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else { throw FirebaseServiceError.invalidConfiguration }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let bodyString = "grant_type=refresh_token&refresh_token=\(refreshToken)"
        request.httpBody = bodyString.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data, context: "refreshIdToken")

    let refresh = try JSONDecoder().decode(RefreshResponse.self, from: data)
    self.idToken = refresh.idToken
    self.refreshToken = refresh.refreshToken
    let expires = Double(refresh.expiresIn ?? "3600") ?? 3600
    self.tokenExpiry = Date().addingTimeInterval(expires - 60)
        let user = FirebaseUser(uid: refresh.userId)
        await updateAuthState(user: user)
        return user
    }

    private func ensureAuthenticated() async throws {
        if tokenIsValid() { return }
        if let refreshToken = refreshToken {
            _ = try await refreshIdToken(refreshToken: refreshToken)
            return
        }
    _ = try await signInAnonymously(existingUserId: currentUser?.uid)
    }

    private func tokenIsValid() -> Bool {
        if let token = idToken, !token.isEmpty,
           let expiry = tokenExpiry, expiry > Date() {
            return true
        }
        return false
    }

    @MainActor
    private func updateAuthState(user: FirebaseUser) {
        self.currentUser = user
        self.isAuthenticated = true
    }

    // MARK: - Diagnostics

    func runDiagnostics(existingUserId: String?) async -> FirebaseHealthDiagnostics {
        let hasAPIKey = !apiKey.isEmpty
        let hasProjectId = !projectId.isEmpty

        var authStatus: FirebaseHealthDiagnostics.StageStatus = .notRun
        var firestoreStatus: FirebaseHealthDiagnostics.StageStatus = .notRun

        guard hasAPIKey && hasProjectId else {
            return FirebaseHealthDiagnostics(
                hasAPIKey: hasAPIKey,
                hasProjectId: hasProjectId,
                authStatus: authStatus,
                firestoreStatus: firestoreStatus,
                checkedAt: Date()
            )
        }

        do {
            let user = try await signInAnonymously(existingUserId: existingUserId)
            authStatus = .success(details: "uid=\(FlexaLog.mask(user.uid))")
            do {
                let reachable = try await performDiagnosticsPing(userId: user.uid)
                firestoreStatus = reachable ? .success(details: "users/\(user.uid)") : .failure(message: "Ping returned false")
            } catch {
                firestoreStatus = .failure(message: error.localizedDescription)
            }
        } catch {
            authStatus = .failure(message: error.localizedDescription)
        }

        return FirebaseHealthDiagnostics(
            hasAPIKey: hasAPIKey,
            hasProjectId: hasProjectId,
            authStatus: authStatus,
            firestoreStatus: firestoreStatus,
            checkedAt: Date()
        )
    }

    // MARK: - Public APIs

    func saveSession(userId: String, sessionId: String, sessionData: [String: Any]) async throws {
        try await ensureAuthenticated()
        let key = cacheKey(userId: userId, sessionId: sessionId)
        let merged = cacheQueue.sync { () -> [String: Any] in
            var existing = sessionDocumentCache[key] ?? [:]
            sessionData.forEach { existing[$0.key] = $0.value }
            let sanitized = FirebasePayloadSanitizer.sanitizeDictionary(existing)
            sessionDocumentCache[key] = sanitized
            return sanitized
        }
        try await upsertDocument(path: "users/\(userId)/sessions/\(sessionId)", fields: merged)
    }

    func saveUserGoals(userId: String, goals: UserGoals) async throws {
        try await ensureAuthenticated()
        let path = "users/\(userId)"
        guard var goalFields = encodeEncodable(goals) else {
            throw FirebaseServiceError.serializationFailed
        }
        goalFields["updatedAt"] = Date()
        let payload: [String: Any] = [
            "goals": goalFields
        ]
        try await upsertDocument(path: path, fields: payload)
    }

    func updateStreak(userId: String, streak: StreakData) async throws {
        try await ensureAuthenticated()
        let path = "users/\(userId)"
        guard let streakFields = encodeEncodable(streak) else {
            throw FirebaseServiceError.serializationFailed
        }
        let payload: [String: Any] = [
            "streak": streakFields
        ]
        try await upsertDocument(path: path, fields: payload)
    }

    func updateSessionMetadata(userId: String, latestSessionNumber: Int?) async throws {
        try await ensureAuthenticated()
        var fields: [String: Any] = [
            "lastSessionSync": Date()
        ]
        if let latestSessionNumber {
            fields["latestSessionNumber"] = latestSessionNumber
        }
        try await upsertDocument(path: "users/\(userId)", fields: fields)
    }

    func fetchUserDocument(userId: String) async throws -> FirestoreDocument? {
        return try await fetchDocument(path: "users/\(userId)", context: "fetchUserDocument")
    }

    func fetchUserSessions(userId: String, limit: Int = 50) async throws -> [FirestoreDocument] {
        return try await listDocuments(path: "users/\(userId)/sessions", limit: limit, context: "fetchUserSessions")
    }

    // MARK: - Firestore Helpers

    private func upsertDocument(path: String, fields: [String: Any]) async throws {
        guard let baseURL = firestoreBaseURL else { throw FirebaseServiceError.invalidConfiguration }
        let documentURL = baseURL.appendingPathComponent(path)
        var createComponents = URLComponents(url: documentURL, resolvingAgainstBaseURL: false)
        createComponents?.queryItems = [URLQueryItem(name: "currentDocument.exists", value: "false")]

        let sanitizedFields = FirebasePayloadSanitizer.sanitizeDictionary(fields)
        let body = try firestoreBody(from: sanitizedFields)
        var request = URLRequest(url: createComponents?.url ?? documentURL)
        request.httpMethod = "PATCH"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = idToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 409 {
            var updateComponents = URLComponents(url: documentURL, resolvingAgainstBaseURL: false)
            var items = sanitizedFields.keys.map { URLQueryItem(name: "updateMask.fieldPaths", value: $0) }
            items.append(URLQueryItem(name: "currentDocument.exists", value: "true"))
            updateComponents?.queryItems = items
            var updateRequest = URLRequest(url: updateComponents?.url ?? documentURL)
            updateRequest.httpMethod = "PATCH"
            updateRequest.httpBody = body
            updateRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let token = idToken {
                updateRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let (updateData, updateResponse) = try await session.data(for: updateRequest)
            try validate(response: updateResponse, data: updateData, context: "upsertDocument-update")
            return
        }
        try validate(response: response, data: data, context: "upsertDocument-create")
    }

    private func fetchDocument(path: String, context: String) async throws -> FirestoreDocument? {
        try await ensureAuthenticated()
    let (request, _) = try makeFirestoreGETRequest(path: path, queryItems: nil)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FirebaseServiceError.invalidResponse }
        if http.statusCode == 404 { return nil }
        try validate(response: response, data: data, context: context)
        return try decodeDocumentJSON(data: data)
    }

    private func listDocuments(path: String, limit: Int, context: String) async throws -> [FirestoreDocument] {
        try await ensureAuthenticated()
        let queryItems: [URLQueryItem] = [URLQueryItem(name: "pageSize", value: String(limit))]
        let (request, _) = try makeFirestoreGETRequest(path: path, queryItems: queryItems)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FirebaseServiceError.invalidResponse }
        if http.statusCode == 404 { return [] }
        try validate(response: response, data: data, context: context)
        return try decodeDocumentsListJSON(data: data)
    }

    private func firestoreBody(from fields: [String: Any]) throws -> Data {
        let encodedFields = encodeFields(fields)
        let payload = ["fields": encodedFields]
        return try JSONSerialization.data(withJSONObject: payload, options: [])
    }

    private func encodeFields(_ dictionary: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in dictionary {
            if let encoded = encodeValue(value) {
                result[key] = encoded
            }
        }
        return result
    }

    private func encodeValue(_ value: Any) -> [String: Any]? {
        switch value {
        case let string as String:
            return ["stringValue": string]
        case let bool as Bool:
            return ["booleanValue": bool]
        case let int as Int:
            return ["integerValue": String(int)]
        case let int as Int64:
            return ["integerValue": String(int)]
        case let double as Double:
            guard !double.isNaN, !double.isInfinite else { return nil }
            return ["doubleValue": double]
        case let float as Float:
            return encodeValue(Double(float))
        case let date as Date:
            return ["timestampValue": isoFormatter.string(from: date)]
        case let array as [Any]:
            let values = array.compactMap { encodeValue($0) }
            return ["arrayValue": ["values": values]]
        case let dict as [String: Any]:
            let encoded = encodeFields(dict)
            return ["mapValue": ["fields": encoded]]
        case let data as Data:
            return ["bytesValue": data.base64EncodedString()]
        case Optional<Any>.none:
            return nil
        case let optional as Optional<Any>:
            if let value = optional {
                return encodeValue(value)
            }
            return nil
        default:
            if let encodable = value as? Encodable {
                return encodeEncodable(encodable).flatMap { encodeValue($0) }
            }
            return nil
        }
    }

    private func encodeEncodable<T: Encodable>(_ value: T) -> [String: Any]? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(Wrapper(value)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let wrapped = object["value"] as? [String: Any] else {
            return nil
        }
        return wrapped
    }

    private func makeFirestoreGETRequest(path: String, queryItems: [URLQueryItem]?) throws -> (URLRequest, URL) {
        guard let baseURL = firestoreBaseURL else { throw FirebaseServiceError.invalidConfiguration }
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if let queryItems, !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        guard let url = components?.url else { throw FirebaseServiceError.invalidConfiguration }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = idToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return (request, url)
    }

    private func decodeDocumentJSON(data: Data) throws -> FirestoreDocument? {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return decodeDocument(dict: json)
    }

    private func decodeDocumentsListJSON(data: Data) throws -> [FirestoreDocument] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        let documents = json["documents"] as? [[String: Any]] ?? []
        return documents.compactMap { decodeDocument(dict: $0) }
    }

    private func decodeDocument(dict: [String: Any]) -> FirestoreDocument? {
        let name = dict["name"] as? String ?? ""
        let createTimeString = dict["createTime"] as? String
        let updateTimeString = dict["updateTime"] as? String
        let createTime = createTimeString.flatMap { isoFormatter.date(from: $0) }
        let updateTime = updateTimeString.flatMap { isoFormatter.date(from: $0) }
        guard let rawFields = dict["fields"] as? [String: Any] else {
            return FirestoreDocument(name: name, fields: [:], createTime: createTime, updateTime: updateTime)
        }
        let decodedFields = decodeFields(rawFields)
        return FirestoreDocument(name: name, fields: decodedFields, createTime: createTime, updateTime: updateTime)
    }

    private func decodeFields(_ fields: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, rawValue) in fields {
            guard let map = rawValue as? [String: Any] else { continue }
            if let decoded = decodeValue(map) {
                result[key] = decoded
            }
        }
        return result
    }

    private func decodeValue(_ value: [String: Any]) -> Any? {
        if let string = value["stringValue"] as? String {
            return string
        }
        if let bool = value["booleanValue"] as? Bool {
            return bool
        }
        if let intNumber = value["integerValue"] as? NSNumber {
            let int64 = intNumber.int64Value
            if int64 <= Int64(Int.max) && int64 >= Int64(Int.min) {
                return Int(int64)
            }
            return int64
        }
        if let intString = value["integerValue"] as? String, let int64 = Int64(intString) {
            if int64 <= Int64(Int.max) && int64 >= Int64(Int.min) {
                return Int(int64)
            }
            return int64
        }
        if let doubleNumber = value["doubleValue"] as? NSNumber {
            return doubleNumber.doubleValue
        }
        if let double = value["doubleValue"] as? Double {
            return double
        }
        if let doubleString = value["doubleValue"] as? String, let double = Double(doubleString) {
            return double
        }
        if let timestamp = value["timestampValue"] as? String {
            return isoFormatter.date(from: timestamp)
        }
        if let bytes = value["bytesValue"] as? String, let data = Data(base64Encoded: bytes) {
            return data
        }
        if let map = value["mapValue"] as? [String: Any], let nested = map["fields"] as? [String: Any] {
            return decodeFields(nested)
        }
        if let array = value["arrayValue"] as? [String: Any] {
            let values = array["values"] as? [[String: Any]] ?? []
            return values.compactMap { decodeValue($0) }
        }
        if value["nullValue"] != nil {
            return nil
        }
        if let reference = value["referenceValue"] as? String {
            return reference
        }
        if let geoPoint = value["geoPointValue"] {
            return geoPoint
        }
        return nil
    }

    private func performDiagnosticsPing(userId: String) async throws -> Bool {
        try await ensureAuthenticated()
        let (request, _) = try makeFirestoreGETRequest(path: "users/\(userId)", queryItems: nil)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FirebaseServiceError.invalidResponse }
        if http.statusCode == 404 { return true }
        try validate(response: response, data: data, context: "diagnosticsPing")
        return true
    }

    private func validate(response: URLResponse, data: Data, context: String) throws {
        guard let http = response as? HTTPURLResponse else {
            throw FirebaseServiceError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw FirebaseServiceError.apiError(status: http.statusCode, message: message, context: context)
        }
    }

    private func cacheKey(userId: String, sessionId: String) -> String {
        return "\(userId)|\(sessionId)"
    }

    // MARK: - DTOs & Helpers

    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private struct Wrapper<T: Encodable>: Encodable {
        let value: T
        init(_ value: T) { self.value = value }
    }

    private struct SignUpResponse: Decodable {
        let idToken: String
        let email: String?
        let refreshToken: String
        let expiresIn: String?
        let localId: String
    }

    private struct RefreshResponse: Decodable {
        let accessToken: String
        let expiresIn: String?
        let tokenType: String?
        let refreshToken: String
        let idToken: String
        let userId: String
        let projectId: String?
    }
}

enum FirebaseServiceError: Error {
    case invalidConfiguration
    case apiError(status: Int, message: String, context: String)
    case serializationFailed
    case invalidResponse
}

struct FirebaseHealthDiagnostics {
    enum StageStatus {
        case notRun
        case success(details: String? = nil)
        case failure(message: String)

        var isSuccess: Bool {
            switch self {
            case .success:
                return true
            default:
                return false
            }
        }

        var description: String {
            switch self {
            case .notRun:
                return "not-run"
            case .success(let details):
                if let details, !details.isEmpty {
                    return "success (\(details))"
                }
                return "success"
            case .failure(let message):
                return "failed — \(message)"
            }
        }
    }

    let hasAPIKey: Bool
    let hasProjectId: Bool
    let authStatus: StageStatus
    let firestoreStatus: StageStatus
    let checkedAt: Date

    var configurationIssues: [String] {
        var issues: [String] = []
        if !hasAPIKey { issues.append("Firebase API key missing") }
        if !hasProjectId { issues.append("Firebase Project ID missing") }
        return issues
    }

    var isHealthy: Bool {
        return hasAPIKey && hasProjectId && authStatus.isSuccess && firestoreStatus.isSuccess
    }

    var logSummary: String {
        let config = configurationIssues.isEmpty ? "configuration OK" : "configuration issues: \(configurationIssues.joined(separator: ", "))"
        return "\(config); auth=\(authStatus.description); firestore=\(firestoreStatus.description)"
    }
}
