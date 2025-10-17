
import SwiftUI
import Charts

struct SmoothnessTrendChartView: View {
    let sparcData: [SPARCPoint]
    let title: String // Keep for API compatibility, but won't be displayed

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
                Chart(Array(sparcData.enumerated()), id: \.offset) { index, point in
                    LineMark(
                        x: .value("Repetition", index + 1),
                        y: .value("SPARC", point.sparc)
                    )
                    .foregroundStyle(.green)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .symbol(Circle().strokeBorder(lineWidth: 2))
                }
                .chartYAxis { // Hide Y-axis grid lines
                    AxisMarks(position: .leading) { _ in
                        AxisValueLabel()
                        AxisTick()
                    }
                }
                .chartXAxis { // Hide X-axis grid lines
                    AxisMarks { _ in
                        AxisValueLabel()
                        AxisTick()
                    }
                }
                .frame(height: 200)
                .padding(.top, 12)
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
