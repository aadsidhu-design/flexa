import SwiftUI
import Charts

struct ROMLineChartView: View {
    let sessionData: ExerciseSessionData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !sessionData.romHistory.isEmpty {
                let yMax = max(sessionData.maxROM, (sessionData.romHistory.max() ?? 0))
                let paddedMax = max(10.0, yMax * 1.1)
                
                Chart {
                    ForEach(Array(sessionData.romHistory.enumerated()), id: \.offset) { index, rom in
                        LineMark(
                            x: .value("Rep", index + 1),
                            y: .value("ROM", rom)
                        )
                        .foregroundStyle(.blue)
                        .lineStyle(StrokeStyle(lineWidth: 3))
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
                                Text("\(v)")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                        }
                    }
                }
            } else {
                Text("No ROM data available")
                    .foregroundColor(.gray)
                    .frame(height: 200)
            }
        }
    }
}
