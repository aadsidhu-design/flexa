
import Foundation
import simd

/// A 1D Kalman filter for smoothing sensor data.
struct OneDimensionalKalmanFilter {
    /// State vector [position, velocity]
    var x = simd_float2(0, 0)
    
    /// Covariance matrix
    var P = matrix_float2x2(rows: [simd_float2(1, 0), simd_float2(0, 1)])
    
    /// State transition matrix
    private var F = matrix_float2x2(rows: [simd_float2(1, 0), simd_float2(0, 1)])
    
    /// Process noise covariance matrix
    private var Q: matrix_float2x2
    
    /// Measurement matrix
    private let H = matrix_float2x2(rows: [simd_float2(1, 0), simd_float2(0, 0)])
    
    /// Measurement noise covariance matrix
    private let R: matrix_float2x2
    
    /// Identity matrix
    private let I = matrix_identity_float2x2
    
    /// Initializes the Kalman filter.
    /// - Parameters:
    ///   - processNoise: The process noise, representing the uncertainty in the model.
    ///   - measurementNoise: The measurement noise, representing the uncertainty of the sensor.
    init(processNoise: Float, measurementNoise: Float) {
        self.Q = matrix_float2x2(rows: [simd_float2(processNoise, 0), simd_float2(0, processNoise)])
        self.R = matrix_float2x2(rows: [simd_float2(measurementNoise, 0), simd_float2(0, measurementNoise)])
    }
    
    /// Updates the filter with a new measurement.
    /// - Parameters:
    ///   - measurement: The new measurement from the sensor.
    ///   - dt: The time delta since the last update.
    mutating func update(with measurement: Float, dt: Float) {
        F[0][1] = dt
        
        // Prediction
        let x_p = F * x
        let P_p = F * P * F.transpose + Q
        
        // Update
        let y = simd_float2(measurement, 0) - H * x_p
        let S = H * P_p * H.transpose + R
        let K = P_p * H.transpose * S.inverse
        
        x = x_p + K * y
        P = (I - K * H) * P_p
    }
}
