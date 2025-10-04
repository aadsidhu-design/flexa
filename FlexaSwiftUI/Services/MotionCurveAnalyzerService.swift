//
//  MotionCurveAnalyzerService.swift
//  FlexaSwiftUI
//
//  Created to support MakeYourOwnGameView and resolve compilation errors related to MotionCurveAnalyzerDelegate
//

import Foundation
import CoreMotion
import SwiftUI

// MARK: - Protocol Definition
protocol MotionCurveAnalyzerDelegate: AnyObject {
    func motionAnalyzerDidDetectPeak(amplitude: Double, timestamp: TimeInterval)
    func motionAnalyzerDidUpdateCurve(curve: [Double])
    func motionAnalyzerDidCompleteAnalysis(result: MotionAnalysisResult)
}

// MARK: - Analysis Result
struct MotionAnalysisResult {
    let maxAmplitude: Double
    let averageAmplitude: Double
    let peakCount: Int
    let duration: TimeInterval
    let curve: [Double]
}

// MARK: - Service Class
class MotionCurveAnalyzerService: ObservableObject {
    @Published var currentAmplitude: Double = 0.0
    @Published var peakCount: Int = 0

    weak var delegate: MotionCurveAnalyzerDelegate?

    private let motionManager = CMMotionManager()
    private var curveData: [Double] = []
    private var startTime: Date?

    func startAnalysis() {
        guard motionManager.isAccelerometerAvailable else { return }

        startTime = Date()
        curveData.removeAll()
        peakCount = 0
        currentAmplitude = 0.0

        motionManager.accelerometerUpdateInterval = 1.0 / 50.0
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
            guard let self = self,
                  let acceleration = data?.acceleration,
                  error == nil else { return }

            let amplitude = sqrt(acceleration.x * acceleration.x +
                               acceleration.y * acceleration.y +
                               acceleration.z * acceleration.z)

            self.currentAmplitude = amplitude
            self.curveData.append(amplitude)

            // Detect peaks
            if self.isPeak(in: self.curveData) {
                self.peakCount += 1
                let timestamp = Date().timeIntervalSince(self.startTime!)
                self.delegate?.motionAnalyzerDidDetectPeak(amplitude: amplitude, timestamp: timestamp)
            }

            self.delegate?.motionAnalyzerDidUpdateCurve(curve: self.curveData)
        }
    }

    func stopAnalysis() {
        motionManager.stopAccelerometerUpdates()

        guard let startTime = startTime else { return }

        let duration = Date().timeIntervalSince(startTime)
        let maxAmplitude = curveData.max() ?? 0.0
        let averageAmplitude = curveData.reduce(0, +) / Double(curveData.count)

        let result = MotionAnalysisResult(
            maxAmplitude: maxAmplitude,
            averageAmplitude: averageAmplitude,
            peakCount: peakCount,
            duration: duration,
            curve: curveData
        )

        delegate?.motionAnalyzerDidCompleteAnalysis(result: result)
    }

    private func isPeak(in data: [Double]) -> Bool {
        guard data.count >= 3 else { return false }

        let last3 = data.suffix(3)
        let middle = last3[last3.index(last3.startIndex, offsetBy: 1)]
        let before = last3.first!
        let after = last3.last!

        return middle > before && middle > after && middle > 0.5 // Threshold for motion detection
    }
}
