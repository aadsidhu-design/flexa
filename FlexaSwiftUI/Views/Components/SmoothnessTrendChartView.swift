
import SwiftUI
import Charts

struct SmoothnessTrendChartView: View {
    let sparcData: [SPARCPoint]
    let title: String // Keep for API compatibility, but won't be displayed
    
    // Sample data at approximately 1-second intervals for clearer visualization
    private var sampledData: [(seconds: Double, sparc: Double)] {
        guard !sparcData.isEmpty else { return [] }
        
        let startTime = sparcData.first?.timestamp ?? Date()
        
        // If we have very few points, just return them all
        if sparcData.count <= 5 {
            return sparcData.map { point in
                let seconds = point.timestamp.timeIntervalSince(startTime)
                return (seconds: seconds, sparc: point.sparc)
            }
        }
        
        // Group data by 1-second buckets and average within each bucket
        var buckets: [Int: [Double]] = [:]
        
        for point in sparcData {
            let seconds = point.timestamp.timeIntervalSince(startTime)
            
            // Safety check: ignore invalid timestamps (too large or negative)
            guard seconds >= 0 && seconds < 86400 else { continue } // Max 24 hours
            
            let bucket = Int(round(seconds))
            if buckets[bucket] == nil {
                buckets[bucket] = []
            }
            buckets[bucket]?.append(point.sparc)
        }
        
        // Create averaged points for each second
        var result: [(seconds: Double, sparc: Double)] = []
        for (second, values) in buckets.sorted(by: { $0.key < $1.key }) {
            let avgSparc = values.reduce(0.0, +) / Double(values.count)
            result.append((seconds: Double(second), sparc: avgSparc))
        }
        
        return result
    }
    
    // Calculate Y-axis domain to fit data with some padding
    private var yAxisDomain: ClosedRange<Double> {
        // Always show full 0-100 scale for accurate smoothness representation
        return 0...100
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
                // Display smoothness as a line graph (no dots)
                let maxSeconds = sampledData.map { $0.seconds }.max() ?? 1
                Chart(Array(sampledData.enumerated()), id: \.offset) { index, point in
                    // Line connecting points
                    LineMark(
                        x: .value("Time", point.seconds),
                        y: .value("SPARC", point.sparc)
                    )
                    .foregroundStyle(Color(red: 1.0, green: 0.58, blue: 0.0))
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.linear)
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
