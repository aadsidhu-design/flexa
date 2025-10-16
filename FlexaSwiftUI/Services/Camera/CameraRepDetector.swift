import Foundation

/// Handles rep validation logic for camera-based games to prevent duplicate counts.
final class CameraRepDetector {
    enum Evaluation {
        case accept
        case belowThreshold
        case cooldown(elapsed: TimeInterval, required: TimeInterval)
    }

    private let minimumInterval: TimeInterval
    private var lastRepTimestamp: TimeInterval = 0

    init(minimumInterval: TimeInterval) {
        self.minimumInterval = minimumInterval
    }

    func reset() {
        lastRepTimestamp = 0
    }

    func evaluateRepCandidate(rom: Double, threshold: Double, timestamp: TimeInterval) -> Evaluation {
        guard rom >= threshold else { return .belowThreshold }

        if lastRepTimestamp > 0 {
            let elapsed = timestamp - lastRepTimestamp
            if elapsed < minimumInterval {
                return .cooldown(elapsed: elapsed, required: minimumInterval)
            }
        }

        lastRepTimestamp = timestamp
        return .accept
    }
}
