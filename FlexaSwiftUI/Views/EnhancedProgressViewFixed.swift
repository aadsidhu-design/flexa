import Charts
import SwiftUI

struct EnhancedProgressViewFixed: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedGraphType: GraphType = .aiScore
    @State private var selectedSession: ExerciseSessionData?
    @State private var sessions: [ExerciseSessionData] = []
    @State private var isLoading = true
    @State private var showingMetricPicker = false
    @State private var showingSessionPicker = false
    @State private var showingSessionDetails = false

    var body: some View {
        VStack(spacing: 0) {
            // Header with dropdowns
            HStack {
                // Metric dropdown (left)
                Button(action: { showingMetricPicker = true }) {
                    HStack {
                        Text(selectedGraphType.displayName)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        Image(systemName: "chevron.down")
                            .foregroundColor(.gray)
                    }
                }
                .confirmationDialog("Select Metric", isPresented: $showingMetricPicker) {
                    ForEach(GraphType.allCases, id: \.self) { type in
                        Button(type.displayName) {
                            selectedGraphType = type
                            if type.requiresSession && selectedSession == nil {
                                selectedSession = sessions.first
                            }
                        }
                    }
                }

                Spacer()

                // Session dropdown (right) - only show for session-based metrics
                if selectedGraphType.requiresSession {
                    Button(action: { showingSessionPicker = true }) {
                        HStack {
                            Text(
                                selectedSession != nil
                                    ? formatSessionTitle(selectedSession!) : "Select Session"
                            )
                            .font(.caption)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .foregroundColor(.gray)
                        }
                    }
                    .confirmationDialog("Select Session", isPresented: $showingSessionPicker) {
                        ForEach(sessions, id: \.id) { session in
                            Button(formatSessionTitle(session)) {
                                selectedSession = session
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 10)
            .padding(.bottom, 50)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // Chart section
                    let sortedPoints = getDataPoints(for: selectedGraphType)
                    let xVals: [Double] = {
                        switch selectedGraphType {
                        case .rom:
                            // 1-based indices for reps
                            return sortedPoints.enumerated().map { Double($0.offset + 1) }
                        case .sparc:
                            // For SPARC, use time in seconds from start of session
                            guard let firstPoint = sortedPoints.first else { return [] }
                            return sortedPoints.map { $0.date.timeIntervalSince(firstPoint.date) }
                        case .aiScore, .pain:
                            return sortedPoints.map { $0.date.timeIntervalSince1970 }
                        }
                    }()
                    let yVals = sortedPoints.map { $0.value }
                    let fit = linearFit(x: xVals, y: yVals)

                    VStack(spacing: 8) {
                        let periodLabel: String = {
                            if selectedGraphType == .rom || selectedGraphType == .sparc {
                                return "Session"
                            }
                            return "Week"
                        }()
                        Text("\(selectedGraphType.displayName) over \(periodLabel)")
                            .font(.headline)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)

                        AppleFitnessChart(
                            points: sortedPoints,
                            graphType: selectedGraphType,
                            trendLine: fit,
                            xValues: xVals
                        )
                        .frame(height: 350)  // Increased height for better symbol visibility
                        .padding(.horizontal)
                        .padding(.vertical, 20)  // More balanced padding
                    }
                }

                // View Details button - only show for session-based metrics
                if selectedGraphType.requiresSession && selectedSession != nil {
                    Button("View Details") {
                        showingSessionDetails = true
                    }
                    .foregroundColor(.green)
                    .padding()
                    .sheet(isPresented: $showingSessionDetails) {
                        if let session = selectedSession {
                            SessionDetailsPopupView(session: session)
                        }
                    }
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            loadData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sessionUploadCompleted)) { _ in
            loadData()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DataCleared"))) {
            _ in
            loadData()
        }
        .navigationBarHidden(true)
    }

    private func loadData() {
        // Sort sessions by newest first
        let latest = LocalDataManager.shared.getCachedSessions().sorted {
            $0.timestamp > $1.timestamp
        }
        sessions = latest
        if selectedGraphType.requiresSession {
            if let current = selectedSession,
                let newest = sessions.first,
                newest.timestamp > current.timestamp
            {
                // Auto-advance to newest when a fresh session arrives
                selectedSession = newest
            } else if selectedSession == nil {
                selectedSession = sessions.first
            }
        }
        isLoading = false
    }

    private func formatSessionTitle(_ session: ExerciseSessionData) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        let dateString = formatter.string(from: session.timestamp)
        return "\(session.exerciseType) - \(dateString)"
    }

    private func getDataPoints(for type: GraphType) -> [MetricPoint] {
        switch type {
        case .rom:
            guard let session = selectedSession else { return [] }
            // Prefer per-rep ROM history; fallback to legacy romData
            let baseSeries: [Double] =
                !session.romHistory.isEmpty ? session.romHistory : session.romData.map { $0.angle }
            // Clamp to recorded reps to avoid mismatched plotting
            let repCount = max(1, session.reps)
            let romSeries = Array(baseSeries.prefix(repCount))
            return romSeries.enumerated().map { index, rom in
                let timestamp = session.timestamp.addingTimeInterval(Double(index))
                return MetricPoint(date: timestamp, value: rom)
            }
        case .sparc:
            guard let session = selectedSession else { return [] }
            let comp = findComprehensive(for: session)
            var sparcData = comp?.sparcDataOverTime.map { $0.sparcValue } ?? []
            if sparcData.isEmpty { sparcData = session.sparcHistory }
            
            // Safety check: ensure session duration is reasonable
            let safeDuration = min(max(session.duration, 0), 86400) // Max 24 hours
            
            return sparcData.enumerated().map { index, sparc in
                // Calculate time in seconds based on session duration and data points
                let timeInSeconds =
                    (Double(index) / Double(max(1, sparcData.count - 1))) * safeDuration
                let timestamp = session.timestamp.addingTimeInterval(timeInSeconds)
                return MetricPoint(date: timestamp, value: sparc)
            }
        case .aiScore:
            let comps = LocalDataManager.shared.getCachedComprehensiveSessions()
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            // Compute Monday of current week (fixed Mon..Sun ordering)
            let wkday = cal.component(.weekday, from: today)  // 1=Sun..7=Sat
            let daysToMonday = (wkday + 5) % 7  // maps Sun->6, Mon->0, Tue->1, ...
            let start = cal.startOfDay(
                for: cal.date(byAdding: .day, value: -daysToMonday, to: today) ?? today)
            let end = cal.date(byAdding: .day, value: 6, to: start) ?? today
            let grouped = Dictionary(grouping: comps) { cal.startOfDay(for: $0.timestamp) }
            var result: [MetricPoint] = []
            var day = start
            while day <= end {
                if let sessions = grouped[day] {
                    let scores = sessions.map { Double($0.aiScore) }
                    let avg = scores.isEmpty ? 0.0 : scores.reduce(0.0, +) / Double(scores.count)
                    result.append(MetricPoint(date: day, value: avg))
                } else {
                    result.append(MetricPoint(date: day, value: 0.0))
                }
                day = cal.date(byAdding: .day, value: 1, to: day) ?? day
            }
            return result
        case .pain:
            let comps = LocalDataManager.shared.getCachedComprehensiveSessions()
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            // Monday..Sunday fixed week
            let wkday = cal.component(.weekday, from: today)
            let daysToMonday = (wkday + 5) % 7
            let start = cal.startOfDay(
                for: cal.date(byAdding: .day, value: -daysToMonday, to: today) ?? today)
            let end = cal.date(byAdding: .day, value: 6, to: start) ?? today
            let grouped = Dictionary(grouping: comps) { cal.startOfDay(for: $0.timestamp) }
            var result: [MetricPoint] = []
            var day = start
            while day <= end {
                if let sessions = grouped[day] {
                    let diffs = sessions.compactMap { s -> Double? in
                        let pre = s.preSurveyData.painLevel
                        guard let post = s.postSurveyData?.painLevel else { return nil }
                        return Double(post - pre)
                    }
                    let avg = diffs.isEmpty ? 0.0 : diffs.reduce(0, +) / Double(diffs.count)
                    result.append(MetricPoint(date: day, value: avg))
                } else {
                    result.append(MetricPoint(date: day, value: 0.0))
                }
                day = cal.date(byAdding: .day, value: 1, to: day) ?? day
            }
            return result
        }
    }

    private func getAIScoreDayCount() -> Int {
        let comps = LocalDataManager.shared.getCachedComprehensiveSessions()
        let cal = Calendar.current
        let uniqueDays = Set(comps.map { cal.startOfDay(for: $0.timestamp) })
        return uniqueDays.count
    }

    private func colorForMetric(_ metric: GraphType) -> Color {
        switch metric {
        case .rom: return .blue
        case .sparc: return .orange
        case .aiScore: return .green
        case .pain: return .red
        }
    }

    private func gradientColorForMetric(_ metric: GraphType) -> Color {
        switch metric {
        case .rom: return Color(red: 0.0, green: 0.48, blue: 1.0)
        case .sparc: return Color(red: 1.0, green: 0.58, blue: 0.0)
        case .aiScore: return Color(red: 0.2, green: 0.8, blue: 0.4)
        case .pain: return Color(red: 1.0, green: 0.27, blue: 0.23)
        }
    }

    // Linear regression y = m*x + b
    private func linearFit(x: [Double], y: [Double]) -> (Double, Double)? {
        guard x.count == y.count, x.count >= 2 else { return nil }
        let n = Double(x.count)
        let sumX = x.reduce(0, +)
        let sumY = y.reduce(0, +)
        let sumXY = zip(x, y).reduce(0) { $0 + $1.0 * $1.1 }
        let sumX2 = x.reduce(0) { $0 + $1 * $1 }
        let denom = (n * sumX2 - sumX * sumX)
        guard abs(denom) > 1e-10 else { return nil }
        let m = (n * sumXY - sumX * sumY) / denom
        let b = (sumY - m * sumX) / n
        return (m, b)
    }

    private func findComprehensive(for session: ExerciseSessionData) -> ComprehensiveSessionData? {
        let comps = LocalDataManager.shared.getCachedComprehensiveSessions()
        let candidates = comps.filter {
            $0.exerciseName.lowercased() == session.exerciseType.lowercased()
        }
        guard !candidates.isEmpty else { return nil }
        let best = candidates.min { a, b in
            abs(a.timestamp.timeIntervalSince(session.timestamp))
                < abs(b.timestamp.timeIntervalSince(session.timestamp))
        }
        return best
    }
}

// MARK: - Apple Fitness Style Chart
struct AppleFitnessChart: View {
    let points: [MetricPoint]
    let graphType: GraphType
    let trendLine: (Double, Double)?
    let xValues: [Double]

    private var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"  // Mon, Tue, Wed, etc.
        return formatter
    }

    private var chartYDomain: ClosedRange<Double> {
        guard !points.isEmpty else { return 0...100 }

        let minValue = points.map { $0.value }.min() ?? 0
        let maxValue = points.map { $0.value }.max() ?? 100
        let valueRange = maxValue - minValue

        // Generous padding to prevent symbol cutoff - especially for large dots
        let basePadding = max(valueRange * 0.35, 10.0)  // Increased to 35% with minimum 10 units

        // Extra padding for graphs with large symbols (AI Score, Pain)
        let hasLargeSymbols = graphType == .aiScore || graphType == .pain
        let symbolPadding = hasLargeSymbols ? max(valueRange * 0.15, 5.0) : 0

        let totalPadding = basePadding + symbolPadding

        let paddedMin = max(0, minValue - totalPadding)
        let paddedMax = maxValue + totalPadding

        // Ensure reasonable bounds for each graph type
        switch graphType {
        case .aiScore:
            return paddedMin...max(paddedMax, 100)
        case .rom:
            return paddedMin...max(paddedMax, 180)  // ROM typically 0-180°
        case .sparc:
            return 0...100  // Always show full 0-100 scale for accurate smoothness representation
        case .pain:
            return max(-10, paddedMin)...min(10, paddedMax)  // Pain change -10 to +10
        }
    }

    var body: some View {
        // Precompute index mapping for stable x positions
        let indexMap: [UUID: Int] = Dictionary(
            uniqueKeysWithValues: points.enumerated().map { ($1.id, $0) })
        Chart {
            // Data series with Apple Fitness styling
            ForEach(points) { item in
                switch graphType {
                case .rom:
                    let repIndex = (indexMap[item.id] ?? 0) + 1
                    AppleFitnessAreaMark(
                        x: .value("Rep", repIndex),
                        y: .value("ROM (°)", item.value),
                        color: Color(red: 0.0, green: 0.48, blue: 1.0)
                    )
                case .sparc:
                    // Render SPARC (smoothness) as line only (no dots)
                    let idx = indexMap[item.id] ?? 0
                    let timeInSeconds: Double =
                        (idx < xValues.count)
                        ? xValues[idx]
                        : (points.first.map { item.date.timeIntervalSince($0.date) } ?? 0)
                    
                    // Line connecting points
                    LineMark(
                        x: .value("Time (s)", timeInSeconds),
                        y: .value("Smoothness", item.value)
                    )
                    .foregroundStyle(Color(red: 1.0, green: 0.58, blue: 0.0))
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.linear)
                case .aiScore, .pain:
                    AppleFitnessAreaMark(
                        x: .value("Day", item.date, unit: .day),
                        y: .value(graphType.yAxisTitle, item.value),
                        color: gradientColorForMetric(graphType)
                    )

                    PointMark(
                        x: .value("Day", item.date, unit: .day),
                        y: .value(graphType.yAxisTitle, item.value)
                    )
                    .foregroundStyle(gradientColorForMetric(graphType))
                    .symbolSize(50)
                    .symbol(.circle)
                }
            }
        }
        .chartPlotStyle { plot in
            plot
                .background(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.95),
                            Color.black.opacity(0.85),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(16)
        }
        .chartBackground { chartProxy in
            // Add invisible padding to prevent symbol cutoff
            Rectangle()
                .fill(Color.clear)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .chartXAxis {
            if graphType == .aiScore || graphType == .pain {
                // Custom axis marks for day names across the week
                AxisMarks(position: .bottom, values: .stride(by: .day)) { value in
                    AxisGridLine()
                        .foregroundStyle(.white.opacity(0.1))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(dayFormatter.string(from: date))
                                .foregroundStyle(.white.opacity(0.7))
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                        }
                    }
                }
            } else if graphType == .rom {
                // Integer rep labels with automatic tick placement
                AxisMarks(position: .bottom, values: .automatic) { value in
                    AxisGridLine()
                        .foregroundStyle(.white.opacity(0.1))
                    AxisValueLabel {
                        if let d = value.as(Double.self) {
                            Text("\(Int(d.rounded()))")
                                .foregroundStyle(.white.opacity(0.7))
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                        }
                    }
                }
            } else {
                // Default for SPARC (time)
                AxisMarks(position: .bottom, values: .automatic) { _ in
                    AxisGridLine()
                        .foregroundStyle(.white.opacity(0.1))
                    AxisValueLabel()
                        .foregroundStyle(.white.opacity(0.7))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                }
            }
        }
        .chartXAxisLabel(graphType.xAxisTitle, position: .bottom)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic) { _ in
                AxisGridLine()
                    .foregroundStyle(.white.opacity(0.1))
                AxisValueLabel()
                    .foregroundStyle(.white.opacity(0.7))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
            }
        }
        .chartYScale(domain: chartYDomain)
        .chartYAxisLabel(graphType.yAxisTitle, position: .leading)
        .modifier(SinglePointXDomain(points: points, graphType: graphType))
    }

    // MARK: - Single Point X Domain Helper
    private struct SinglePointXDomain: ViewModifier {
        let points: [MetricPoint]
        let graphType: GraphType

        func body(content: Content) -> some View {
            switch graphType {
            case .aiScore, .pain:
                // Always show the current week anchored Mon..Sun
                let cal = Calendar.current
                let today = Date()
                let wkday = cal.component(.weekday, from: today)
                let daysToMonday = (wkday + 5) % 7
                let start = cal.startOfDay(
                    for: cal.date(byAdding: .day, value: -daysToMonday, to: today) ?? today)
                let end =
                    cal.date(
                        byAdding: .day, value: 1,
                        to: cal.date(byAdding: .day, value: 6, to: start) ?? start) ?? today
                return AnyView(content.chartXScale(domain: start...end))
            case .rom:
                // 1-based domain for reps
                if points.count == 1 {
                    return AnyView(content.chartXScale(domain: 1.0...2.0))
                } else if points.count > 1 {
                    let lastRep = Double(points.count)
                    return AnyView(content.chartXScale(domain: 1.0...lastRep))
                } else {
                    return AnyView(content)
                }
            case .sparc:
                if points.count == 1 {
                    return AnyView(content.chartXScale(domain: 0.0...1.0))
                }
                return AnyView(content)
            }
        }
    }

    private func gradientColorForMetric(_ metric: GraphType) -> Color {
        switch metric {
        case .rom: return Color(red: 0.0, green: 0.48, blue: 1.0)
        case .sparc: return Color(red: 1.0, green: 0.58, blue: 0.0)
        case .aiScore: return Color(red: 0.2, green: 0.8, blue: 0.4)
        case .pain: return Color(red: 1.0, green: 0.27, blue: 0.23)
        }
    }
}

// MARK: - Apple Fitness Area Mark Component
struct AppleFitnessAreaMark<X: Plottable>: ChartContent {
    let x: PlottableValue<X>
    let y: PlottableValue<Double>
    let color: Color

    var body: some ChartContent {
        // Gradient area fill
        AreaMark(
            x: x,
            yStart: .value("Base", 0.0 as Double),
            yEnd: y
        )
        .foregroundStyle(
            LinearGradient(
                colors: [
                    color.opacity(0.6),
                    color.opacity(0.1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .interpolationMethod(.catmullRom)

        // Smooth curved line
        LineMark(x: x, y: y)
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        color,
                        color.opacity(0.8),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            .interpolationMethod(.catmullRom)
    }
}

// MARK: - Supporting Views & Types
struct MetricPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

enum GraphType: String, CaseIterable {
    case aiScore = "aiScore"
    case rom = "rom"
    case sparc = "sparc"
    case pain = "pain"

    var displayName: String {
        switch self {
        case .rom: return "ROM"
        case .sparc: return "Smoothness"
        case .aiScore: return "AI Score"
        case .pain: return "Pain Change"
        }
    }

    var yAxisTitle: String {
        switch self {
        case .rom: return "ROM (°)"
        case .sparc: return "Smoothness"
        case .aiScore: return "AI Score"
        case .pain: return "Pain Change"
        }
    }

    var xAxisTitle: String {
        switch self {
        case .rom: return "Rep"
        case .sparc: return "Time (seconds)"
        case .aiScore, .pain: return "Day"
        }
    }

    var requiresSession: Bool {
        return self == .rom || self == .sparc
    }
}

struct SessionPickerView: View {
    let sessions: [ExerciseSessionData]
    @Binding var selectedSession: ExerciseSessionData?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                ForEach(sessions, id: \.id) { session in
                    Button(action: {
                        selectedSession = session
                        dismiss()
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.exerciseType)
                                    .foregroundColor(.white)
                                    .font(.headline)
                                Text(session.timestamp, style: .date)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("ROM \(Int(session.maxROM))°")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                                Text("\(session.reps) reps")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                            }
                            if selectedSession?.id == session.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.green)
                            }
                        }
                    }
                }
                .listRowBackground(Color.gray.opacity(0.1))
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("Select Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.green)
                }
            }
        }
    }
}
