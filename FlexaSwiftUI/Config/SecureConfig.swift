import Foundation

struct SecureConfig {
    static let shared = SecureConfig()
    
    private init() {}
    
    // MARK: - Secure API Key Retrieval
    
    var geminiAPIKey: String {
        return getAPIKey(for: "GEMINI_API_KEY") ?? ""
    }
    
    var firebaseAPIKey: String {
        if let env = ProcessInfo.processInfo.environment["FIREBASE_WEB_API_KEY"] {
            return env
        }
        if let infoValue = Bundle.main.object(forInfoDictionaryKey: "FIREBASE_WEB_API_KEY") as? String {
            return infoValue
        }
        if let plistPath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: plistPath),
           let apiKey = dict["API_KEY"] as? String {
            return apiKey
        }
        return ""
    }

    var firebaseProjectId: String {
        if let env = ProcessInfo.processInfo.environment["FIREBASE_PROJECT_ID"] {
            return env
        }
        if let infoValue = Bundle.main.object(forInfoDictionaryKey: "FIREBASE_PROJECT_ID") as? String {
            return infoValue
        }
        if let plistPath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: plistPath),
           let projectId = dict["PROJECT_ID"] as? String {
            return projectId
        }
        return ""
    }

    var appwriteEndpoint: String {
        // Prefer environment, then Info.plist
        if let env = ProcessInfo.processInfo.environment["APPWRITE_ENDPOINT"] { return env }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "APPWRITE_ENDPOINT") as? String { return plist }
        return ""
    }
    
    // MARK: - Private Methods
    
    private func getAPIKey(for key: String) -> String? {
        // First try environment variables (for development)
        if let envValue = ProcessInfo.processInfo.environment[key] {
            return envValue
        }
        
        // Then try secure keychain storage
        return KeychainManager.shared.getString(for: key)
    }
    
    // Firebase configuration now sourced from environment -> Info.plist -> GoogleService-Info
    
    // MARK: - Validation
    
    func validateAPIKeys() -> Bool {
        let geminiValid = !geminiAPIKey.isEmpty && geminiAPIKey.hasPrefix("AIza")
        let firebaseValid = !firebaseAPIKey.isEmpty
        return geminiValid && firebaseValid
    }
    
    func logSecurityStatus() {
        FlexaLog.security.info("🔐 Security Status")
        if geminiAPIKey.isEmpty {
            FlexaLog.security.error("Gemini API Key: ❌ Missing")
        } else {
            FlexaLog.security.info("Gemini API Key: ✅ Configured \(FlexaLog.mask(geminiAPIKey))")
        }
        if firebaseAPIKey.isEmpty {
            FlexaLog.security.error("Firebase API Key: ❌ Missing")
        } else {
            FlexaLog.security.info("Firebase API Key: ✅ Configured \(FlexaLog.mask(firebaseAPIKey))")
        }
        if firebaseProjectId.isEmpty {
            FlexaLog.security.error("Firebase Project ID: ❌ Missing")
        } else {
            FlexaLog.security.info("Firebase Project ID: ✅ \(firebaseProjectId)")
        }
        if !validateAPIKeys() {
            FlexaLog.security.error("Warning: Some API keys are missing or invalid")
        }
    }
}
