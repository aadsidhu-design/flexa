
import SwiftUI
import Charts

struct SmoothnessTrendChartView: View {
    let sparcData: [SPARCPoint]
    let title: String // Keep for API compatibility, but won't be displayed
    
    // Compute smoothed average over time to remove repetitive up-and-down patterns
    private var smoothedData: [(seconds: Double, sparc: Double)] {
        guard sparcData.count > 2 else {
            // Convert to seconds from start
            let startTime = sparcData.first?.timestamp ?? Date()
            return sparcData.map { point in
                let seconds = point.timestamp.timeIntervalSince(startTime)
                return (seconds: seconds, sparc: point.sparc)
            }
        }
        
        // Apply moving average with window size of 5 to smooth out noise
        let windowSize = 5
        var smoothed: [(seconds: Double, sparc: Double)] = []
        let startTime = sparcData.first?.timestamp ?? Date()
        
        for i in 0..<sparcData.count {
            let start = max(0, i - windowSize / 2)
            let end = min(sparcData.count, i + windowSize / 2 + 1)
            let window = Array(sparcData[start..<end])
            
            let avgSparc = window.reduce(0.0) { $0 + $1.sparc } / Double(window.count)
            let seconds = sparcData[i].timestamp.timeIntervalSince(startTime)
            smoothed.append((seconds: seconds, sparc: avgSparc))
        }
        
        return smoothed
    }
    
    // Calculate Y-axis domain to fit data with some padding
    private var yAxisDomain: ClosedRange<Double> {
        guard !smoothedData.isEmpty else { return 0...100 }
        let values = smoothedData.map { $0.sparc }
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 100
        let padding = (maxValue - minValue) * 0.2 // 20% padding
        return max(0, minValue - padding)...min(100, maxValue + padding)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Title has been removed as per user request.
            
            if sparcData.isEmpty {
                VStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("No smoothness data")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)
            } else {
                // Use smoothed data to show average smoothness over time
                let maxSeconds = smoothedData.map { $0.seconds }.max() ?? 1
                Chart(Array(smoothedData.enumerated()), id: \.offset) { index, point in
                    LineMark(
                        x: .value("Time", point.seconds),
                        y: .value("SPARC", point.sparc)
                    )
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 3))
                }
                .frame(height: 300)
                .chartYScale(domain: yAxisDomain)
                .chartXScale(domain: 0...maxSeconds)
                .chartPlotStyle { plot in
                    plot.background(Color.black)
                }
                .chartXAxis {
                    AxisMarks(position: .bottom, values: .automatic(desiredCount: min(8, max(2, Int(maxSeconds) / 3)))) { value in
                        AxisGridLine().foregroundStyle(Color.gray.opacity(0.2))
                        AxisTick().foregroundStyle(Color.gray.opacity(0.6))
                        if let seconds = value.as(Double.self) {
                            AxisValueLabel {
                                Text("\(Int(seconds))s")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(Color.gray.opacity(0.2))
                        AxisTick().foregroundStyle(Color.gray.opacity(0.6))
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("\(String(format: "%.0f", v))")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                        }
                    }
                }
                .chartXAxisLabel("Time (seconds)", position: .bottom)
                .chartYAxisLabel("Smoothness", position: .leading)
            }
        }
    }
}

#Preview {
    SmoothnessTrendChartView(
        sparcData: [
            SPARCPoint(sparc: 45.0, timestamp: Date().addingTimeInterval(-10)),
            SPARCPoint(sparc: 48.0, timestamp: Date().addingTimeInterval(-8)),
            SPARCPoint(sparc: 52.0, timestamp: Date().addingTimeInterval(-6)),
            SPARCPoint(sparc: 50.0, timestamp: Date().addingTimeInterval(-4)),
            SPARCPoint(sparc: 55.0, timestamp: Date().addingTimeInterval(-2)),
            SPARCPoint(sparc: 58.0, timestamp: Date())
        ],
        title: ""
    )
    .padding()
    .background(Color.black)
    .foregroundColor(.white)
}
