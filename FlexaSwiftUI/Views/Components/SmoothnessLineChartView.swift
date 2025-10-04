import SwiftUI
import Charts

struct SmoothnessLineChartView: View {
    let sessionData: ExerciseSessionData
    @EnvironmentObject var motionService: SimpleMotionService
    
    var body: some View {
        let sparcDataPoints = motionService.sparcService.getSPARCDataPoints()
        let sessionStartTime = motionService.sparcService.getSessionStartTime()
        let timeValues = sparcDataPoints.map { $0.timestamp.timeIntervalSince(sessionStartTime) }
        let minTime = timeValues.min() ?? 0
        let maxTime = timeValues.max() ?? 0
        let xAxisMax = max(1.0, ceil(maxTime * 10) / 10.0)
        let sparcValues = sparcDataPoints.map { $0.sparcValue }
        let maxSPARC = sparcValues.max() ?? 0

        if !sparcDataPoints.isEmpty {
            FlexaLog.ui.debug("📊 [SmoothnessChart] Displaying \(sparcDataPoints.count) points | X-axis range: \(String(format: "%.1f", minTime))s to \(String(format: "%.1f", maxTime))s | SPARC range: 0–\(String(format: "%.1f", maxSPARC))")
        }

        return VStack(alignment: .leading, spacing: 12) {
            if !sparcDataPoints.isEmpty {
                Chart {
                    ForEach(sparcDataPoints, id: \.timestamp) { dataPoint in
                        // Calculate time from session start using sessionStartTime from SPARC service
                        let timeFromStart = dataPoint.timestamp.timeIntervalSince(sessionStartTime)
                        LineMark(
                            x: .value("Time (s)", timeFromStart),
                            y: .value("Smoothness", dataPoint.sparcValue)
                        )
                        .foregroundStyle(.green)
                        .lineStyle(StrokeStyle(lineWidth: 3))
                    }
                }
                .frame(height: 200)
                .chartYScale(domain: 0...100)
                .chartXScale(domain: 0...xAxisMax)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .stride(by: 20)) { value in
                        AxisGridLine().foregroundStyle(.white.opacity(0.1))
                        AxisTick().foregroundStyle(.white)
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(String(format: "%.0f%%", v))
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(position: .bottom) { value in
                        AxisGridLine().foregroundStyle(.white.opacity(0.1))
                        AxisTick().foregroundStyle(.white)
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(String(format: "%.0fs", v))
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                        }
                    }
                }
                .accessibilityLabel("Smoothness over time")
                .accessibilityHint("Shows SPARC smoothness values across the session duration.")
            } else {
                Text("No smoothness data available")
                    .foregroundColor(.gray)
                    .frame(height: 200)
            }
        }
    }
}
