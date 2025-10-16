import Foundation
import os

// Centralized structured logger for the app
// Uses the system os.Logger to avoid colliding with the app's own Logger class.
// Usage examples:
//   FlexaLog.gemini.info("Starting analysis…")
// Always avoid logging raw secrets; use FlexaLog.mask(_:) when needed.
struct FlexaLog {
    static let subsystem: String = Bundle.main.bundleIdentifier ?? "com.flexa.app"

    // Explicitly reference os.Logger to avoid ambiguity with project Logger
    static let gemini = os.Logger(subsystem: subsystem, category: "Gemini")
    static let backend = os.Logger(subsystem: subsystem, category: "Backend")
    static let motion = os.Logger(subsystem: subsystem, category: "Motion")
    static let vision = os.Logger(subsystem: subsystem, category: "Vision")
    static let security = os.Logger(subsystem: subsystem, category: "Security")
    static let ui = os.Logger(subsystem: subsystem, category: "UI")
    static let notifications = os.Logger(subsystem: subsystem, category: "Notifications")
    static let game = os.Logger(subsystem: subsystem, category: "Game")
    static let lifecycle = os.Logger(subsystem: subsystem, category: "Lifecycle")

    // Mask potentially sensitive strings (e.g., API keys, user IDs)
    // Shows first N prefix and last M suffix characters
    static func mask(_ s: String, prefix: Int = 4, suffix: Int = 2) -> String {
        guard !s.isEmpty else { return "(empty)" }
        if s.count <= max(prefix, suffix) { return String(repeating: "*", count: s.count) }
        let start = s.prefix(prefix)
        let end = s.suffix(suffix)
        return "\(start)…\(end)"
    }

    static func maskOptional(_ s: String?) -> String { mask(s ?? "") }

    // Truncate long payloads to avoid overwhelming the console
    static func trunc(_ s: String, max: Int = 300) -> String {
        if s.count <= max { return s }
        let head = s.prefix(max)
        return String(head) + "…(truncated \(s.count) chars)"
    }
}
