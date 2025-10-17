import Foundation
import simd

/// Lightweight 3-axis Kalman-style filter that smooths accelerometer data,
/// compensates for gravity, and integrates to velocity for IMU rep detection.
struct ThreeDimensionalKalmanFilter {
    private var smoothedAcceleration: simd_float3 = .zero
    private var velocity: simd_float3 = .zero
    private var position: simd_float3 = .zero

    private let processNoise: Float
    private let measurementNoise: Float
    private let alpha: Float

    /// Gravity constant (m/s²). Z-axis points upward in ARKit coordinates, so subtract 1g downwards.
    private let gravityVector = simd_float3(0, 0, -9.80665)

    init(processNoise: Float, measurementNoise: Float) {
        self.processNoise = max(0.0001, processNoise)
        self.measurementNoise = max(0.0001, measurementNoise)
        let denominator = self.processNoise + self.measurementNoise
        self.alpha = self.processNoise / denominator
    }

    mutating func update(with acceleration: simd_float3, dt: Float) {
        guard dt > 0 else { return }

        // CMAcceleration delivers g-force units; convert to m/s²
        let g: Float = 9.80665
        let accelerationMS2 = acceleration * g

        // Remove gravity component
        let userAcceleration = accelerationMS2 - gravityVector

        // Exponential weighting between new measurement and previous smoothed value
        smoothedAcceleration = alpha * userAcceleration + (1.0 - alpha) * smoothedAcceleration

        // Integrate to velocity and position
        velocity += smoothedAcceleration * dt
        position += velocity * dt
    }

    mutating func reset() {
        smoothedAcceleration = .zero
        velocity = .zero
        position = .zero
    }

    func getVelocity() -> simd_float3 { velocity }
    func getPosition() -> simd_float3 { position }
}
