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
                    let trendLine = calculateTrendLine(sparcHistory)
                    TrendLineChart(trendLine: trendLine)
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXAxis {
                    AxisMarks()
                }
                .frame(height: 200)
                .padding(.vertical, 8)
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
