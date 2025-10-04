import SwiftUI

// EnvironmentKey wrapper for BackendService
struct BackendServiceKey: EnvironmentKey {
    static let defaultValue: BackendService? = nil
}

extension EnvironmentValues {
    var backendService: BackendService? {
        get { self[BackendServiceKey.self] }
        set { self[BackendServiceKey.self] = newValue }
    }
    
    // Keep only the unified backend service. Legacy keys removed.
}
