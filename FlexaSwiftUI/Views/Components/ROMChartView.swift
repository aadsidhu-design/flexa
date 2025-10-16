import SwiftUI
import Charts

struct ROMChartView: View {
    let sessionData: ExerciseSessionData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Range of Motion Analysis")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            // Legend
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Circle().fill(LinearGradient(gradient: Gradient(colors: [.blue, .cyan]), startPoint: .bottom, endPoint: .top)).frame(width: 10, height: 10)
                    Text("ROM (degrees)").font(.caption).foregroundColor(.white.opacity(0.8))
                }
                Spacer()
            }
            
            if !sessionData.romHistory.isEmpty {
                let yMax = max(sessionData.maxROM, (sessionData.romHistory.max() ?? 0))
                let paddedMax = max(10.0, yMax * 1.1)
                Chart {
                    ForEach(Array(sessionData.romHistory.enumerated()), id: \.offset) { index, rom in
                        BarMark(
                            x: .value("Rep", index + 1),
                            y: .value("ROM", rom)
                        )
                        .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.blue, .cyan]), startPoint: .bottom, endPoint: .top))
                        .cornerRadius(4)
                    }
                    if avgROM > 0 {
                        RuleMark(y: .value("Avg", avgROM))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4,4]))
                            .foregroundStyle(.white.opacity(0.5))
                            .annotation(position: .leading) {
                                Text("Avg \(String(format: "%.1f°", avgROM))")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                    }
                }
                .frame(height: 200)
                .chartYScale(domain: 0...paddedMax)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .stride(by: max(1.0, paddedMax / 5))) { value in
                        AxisGridLine().foregroundStyle(.white.opacity(0.1))
                        AxisTick().foregroundStyle(.white)
                        AxisValueLabel {
                            if let v = value.as(Double.self), !v.isNaN, !v.isInfinite {
                                Text("\(Int(v))°")
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
                            if let v = value.as(Int.self) { 
                                Text("Rep \(v)")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                        }
                    }
                }
                
                // Stats
                HStack {
                    VStack(alignment: .leading) {
                        Text("Average ROM")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(String(format: "%.1f", avgROM))°")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text("Max ROM")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(String(format: "%.1f", sessionData.maxROM))°")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                }
                .padding(.top)
            } else {
                Text("No ROM data available")
                    .foregroundColor(.gray)
                    .frame(height: 200)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
    private var avgROM: Double {
        guard !sessionData.romHistory.isEmpty else { return 0 }
        return sessionData.romHistory.reduce(0,+) / Double(sessionData.romHistory.count)
    }
}
