import Foundation

extension Notification.Name {
    /// Posted when a shared capture session is ready and available for observers.
    static let SharedCaptureSessionReady = Notification.Name("SharedCaptureSessionReady")

    /// Backwards-compatible alias (if other code uses different casing)
    static let sharedCaptureSessionReady = Notification.Name("SharedCaptureSessionReady")
}
