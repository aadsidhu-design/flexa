import SwiftUI
import Charts

struct UnifiedMetricPoint: Identifiable {
    let id = UUID()
    let x: Double
    let y: Double
}

struct SPARCChartView: View {
    let sessionData: ExerciseSessionData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Movement Smoothness Analysis")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            // Legend
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Circle().fill(Color.orange).frame(width: 10, height: 10)
                    Text("SPARC Score").font(.caption).foregroundColor(.white.opacity(0.8))
                }
                Spacer()
            }
            
            if let points = buildSparcSeries() {
                let yMin = 0.0
                let xMax = max(1.0, points.map { $0.x }.max() ?? 0)
                Chart {
                    ForEach(points, id: \.id) { p in
                        AreaMark(
                            x: .value("t", p.x),
                            y: .value("SPARC", p.y)
                        )
                        .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.orange.opacity(0.3), .clear]), startPoint: .top, endPoint: .bottom))
                        LineMark(
                            x: .value("t", p.x),
                            y: .value("SPARC", p.y)
                        )
                        .foregroundStyle(.orange)
                    }
                }
                .frame(height: 200)
                .chartYScale(domain: yMin...100)
                .chartXScale(domain: 0...xMax)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .stride(by: 20)) { value in
                        AxisGridLine().foregroundStyle(.white.opacity(0.1))
                        AxisTick().foregroundStyle(.white)
                        AxisValueLabel {
                            if let d = value.as(Double.self) { 
                                Text(String(format: "%.0f%%", d))
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
                            if let d = value.as(Double.self) { 
                                Text("\(String(format: "%.0f", d))s")
                                    .font(.caption)
                                    .foregroundColor(.white) 
                            } 
                        }
                    }
                }
                // Stats
                let latestSPARC = sessionData.sparcHistory.last ?? sessionData.sparcScore

                HStack {
                    VStack(alignment: .leading) {
                        Text("Average SPARC")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.0f%%", sessionData.sparcScore))
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("Latest Smoothness")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.0f%%", latestSPARC))
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                }
                .padding(.top)
            } else {
                VStack {
                    Text("No SPARC data available")
                        .foregroundColor(.gray)
                    Text("SPARC measures movement smoothness")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(height: 200)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
    private func buildSparcSeries() -> [UnifiedMetricPoint]? {
        // Try to use sparcData (SPARCPoint) with real timestamps first
        if !sessionData.sparcData.isEmpty {
            let sessionStart = sessionData.sparcData.first?.timestamp ?? Date()
            return sessionData.sparcData.map { dataPoint in
                let elapsedSeconds = dataPoint.timestamp.timeIntervalSince(sessionStart)
                return UnifiedMetricPoint(
                    x: elapsedSeconds,
                    y: max(0, dataPoint.sparc)
                )
            }
        }
        
        // Fallback to sparcHistory with actual session duration
        guard !sessionData.sparcHistory.isEmpty else { return nil }
        
        // Use actual session duration from the session
        let actualDuration = sessionData.duration
        return sessionData.sparcHistory.enumerated().map { index, sparcValue in
            UnifiedMetricPoint(
                x: Double(index) * (actualDuration / Double(sessionData.sparcHistory.count)),
                y: max(0, sparcValue)
            )
        }
    }
}
