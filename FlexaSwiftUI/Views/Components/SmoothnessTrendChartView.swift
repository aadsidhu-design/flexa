import SwiftUI
import Charts

struct SmoothnessTrendChartView: View {
    let sparcHistory: [Double]
    let title: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .fontWeight(.bold)
            
            if sparcHistory.isEmpty {
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
                Chart {
                    // Trend line (curved through data)
                    let trendLine = calculateTrendLine(sparcHistory)
                    TrendLineChart(trendLine: trendLine)
                    
                    // Actual data points
                    ForEach(Array(sparcHistory.enumerated()), id: \.offset) { index, value in
                        PointMark(
                            x: .value("Rep", index + 1),
                            y: .value("Smoothness", value)
                        )
                        .foregroundStyle(.blue)
                        .opacity(0.6)
                        .symbolSize(80)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXAxis {
                    AxisMarks()
                }
                .frame(height: 200)
                .padding(.vertical, 8)
                
                // Stats
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Average")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(String(format: "%.1f", sparcHistory.reduce(0, +) / Double(sparcHistory.count)))
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.bold)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Peak")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(String(format: "%.1f", sparcHistory.max() ?? 0))
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Low")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(String(format: "%.1f", sparcHistory.min() ?? 0))
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Trend")
                            .font(.caption)
                            .foregroundColor(.gray)
                        let trend = calculateTrendDirection(sparcHistory)
                        HStack(spacing: 2) {
                            Image(systemName: trend > 0 ? "arrow.up" : trend < 0 ? "arrow.down" : "minus")
                                .font(.caption)
                            Text(String(format: "%.1f%", abs(trend)))
                                .font(.system(.caption, design: .monospaced))
                        }
                        .fontWeight(.bold)
                        .foregroundColor(trend > 0 ? .green : trend < 0 ? .red : .gray)
                    }
                }
                .padding()
                .background(Color.black.opacity(0.3))
                .cornerRadius(8)
            }
        }
    }
    
    /// Calculate smooth trend line using exponential moving average
    private func calculateTrendLine(_ data: [Double]) -> [Double] {
        guard data.count >= 1 else { return [] }
        
        var trendLine: [Double] = []
        let alpha: Double = 0.25  // Exponential smoothing factor (0-1, lower = smoother)
        var smoothed = data[0]
        trendLine.append(smoothed)
        
        for i in 1..<data.count {
            smoothed = alpha * data[i] + (1 - alpha) * smoothed
            trendLine.append(smoothed)
        }
        
        return trendLine
    }
    
    /// Calculate trend direction as percentage change
    private func calculateTrendDirection(_ data: [Double]) -> Double {
        guard data.count >= 2 else { return 0 }
        
        let firstQuarter = data.prefix(max(1, data.count / 4)).reduce(0, +) / Double(max(1, data.count / 4))
        let lastQuarter = data.suffix(max(1, data.count / 4)).reduce(0, +) / Double(max(1, data.count / 4))
        
        guard firstQuarter > 0 else { return 0 }
        return ((lastQuarter - firstQuarter) / firstQuarter) * 100
    }
}

struct TrendLineChart: ChartContent {
    let trendLine: [Double]
    
    var body: some ChartContent {
        ForEach(0..<max(0, trendLine.count - 1), id: \.self) { i in
            LineMark(
                x: .value("Rep", Double(i + 1)),
                y: .value("Trend", trendLine[i])
            )
            .foregroundStyle(.green)
            .opacity(0.8)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
    }
}

#Preview {
    SmoothnessTrendChartView(
        sparcHistory: [45.0, 48.0, 52.0, 50.0, 55.0, 58.0, 60.0, 62.0],
        title: "📊 Smoothness Trend"
    )
    .padding()
    .background(Color.black)
    .foregroundColor(.white)
}
