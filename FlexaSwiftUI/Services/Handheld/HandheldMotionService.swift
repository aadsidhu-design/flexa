import Foundation
import ARKit
import Combine

/// Lightweight service that owns ARKit-related responsibilities for handheld games.
/// This keeps ARKit out of `SimpleMotionService` while preserving a compatibility
/// surface (the underlying `InstantARKitTracker`) for existing call sites.
final class HandheldMotionService: ObservableObject {
    static let shared = HandheldMotionService()

    /// Underlying ARKit tracker (kept public for compatibility where needed)
    let arkitTracker = InstantARKitTracker()

    /// Convenience closures that consumers can set to receive ARKit updates.
    /// These mirror the callbacks that used to be assigned directly on `arkitTracker`.
    var onPositionUpdate: ((SIMD3<Float>, TimeInterval) -> Void)?
    var onTransformUpdate: ((simd_float4x4, TimeInterval) -> Void)?

    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Forward InstantARKitTracker's callbacks into the local closures so
        // other services (like SimpleMotionService) can set a single handler point.
        arkitTracker.onPositionUpdate = { [weak self] position, timestamp in
            self?.onPositionUpdate?(position, timestamp)
        }

        arkitTracker.onTransformUpdate = { [weak self] transform, timestamp in
            self?.onTransformUpdate?(transform, timestamp)
        }
    }

    /// Start ARKit.
    func start() {
        // Surface logs for debugging/diagnostics
        FlexaLog.motion.debug("📍 [HandheldMotionService] Starting ARKit tracker")
        arkitTracker.start()
        FlexaLog.motion.info("📍 [HandheldMotionService] ARKit tracker started")
    }

    /// Stop ARKit tracker.
    func stop() {
        FlexaLog.motion.debug("📍 [HandheldMotionService] Stopping ARKit tracker")
        arkitTracker.stop()
        FlexaLog.motion.info("📍 [HandheldMotionService] ARKit tracker stopped")
    }
}
