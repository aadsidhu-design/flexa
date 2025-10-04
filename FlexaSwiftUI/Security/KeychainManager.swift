import Foundation
import Security

class KeychainManager {
    static let shared = KeychainManager()
    
    private init() {}
    
    private let service = "com.flexa.app.apikeys"
    
    // MARK: - Store API Key
    
    func store(_ value: String, for key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        var result: AnyObject?
        var status = SecItemCopyMatching(baseQuery as CFDictionary, &result)
        if status == errSecSuccess {
            if let existingData = result as? Data, existingData == data {
                FlexaLog.security.info("Keychain: \(key) already set (unchanged)")
                return true
            }
            let attributesToUpdate: [String: Any] = [kSecValueData as String: data]
            status = SecItemUpdate(baseQuery as CFDictionary, attributesToUpdate as CFDictionary)
            if status == errSecSuccess {
                FlexaLog.security.info("Keychain: \(key) updated")
                return true
            } else {
                FlexaLog.security.error("Keychain update failed for \(key): status=\(status)")
                return false
            }
        } else if status == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            status = SecItemAdd(addQuery as CFDictionary, nil)
            if status == errSecSuccess {
                FlexaLog.security.info("Keychain: \(key) added")
                return true
            } else {
                FlexaLog.security.error("Keychain add failed for \(key): status=\(status)")
                return false
            }
        } else {
            FlexaLog.security.error("Keychain lookup failed for \(key): status=\(status)")
            return false
        }
    }
    
    // MARK: - Retrieve API Key
    
    func getString(for key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return string
    }
    
    // MARK: - Delete API Key
    
    func delete(for key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        let ok = status == errSecSuccess
        if ok {
            FlexaLog.security.info("Keychain: \(key) deleted")
        } else {
            FlexaLog.security.error("Keychain delete failed for \(key): status=\(status)")
        }
        return ok
    }
    
    // MARK: - Setup Initial Keys (Call once during app setup)
    
    func setupInitialKeys() {
        ingestEnvKeyIfPresent("GEMINI_API_KEY")
        ingestEnvKeyIfPresent("APPWRITE_API_KEY")
    }

    private func ingestEnvKeyIfPresent(_ envKey: String) {
        let environment = ProcessInfo.processInfo.environment
        guard let value = environment[envKey], !value.isEmpty else {
            FlexaLog.security.info("Keychain: ℹ️ No environment value provided for \(envKey)")
            return
        }

        if store(value, for: envKey) {
            FlexaLog.security.info("Keychain: ✅ Stored \(envKey) (\(FlexaLog.mask(value)))")
        } else {
            FlexaLog.security.error("Keychain: ❌ Failed to store \(envKey)")
        }

        if getString(for: envKey) != nil {
            FlexaLog.security.info("Keychain: 🔐 Verification succeeded for \(envKey)")
        } else {
            FlexaLog.security.error("Keychain: ❌ Verification failed for \(envKey)")
        }
    }
    
    // MARK: - Clear All Keys (for security/logout)
    
    func clearAllKeys() {
        _ = delete(for: "GEMINI_API_KEY")
        _ = delete(for: "APPWRITE_API_KEY")
        FlexaLog.security.info("🗑️ All API keys cleared from Keychain")
    }
}
