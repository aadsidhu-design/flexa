import SwiftUI

struct TestROMCardView: View {
    @StateObject private var motionService = SimpleMotionService.shared
    @State private var isTracking = false
    @State private var romResults: [String: Double] = [:]
    @State private var startTime: Date?
    @State private var trackingStatus = "Ready"
    
    var body: some View {
        VStack(spacing: 16) {
            Text("📊 Test ROM Calculation")
                .font(.title2)
                .fontWeight(.bold)
            
            // Status section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Status:")
                    Spacer()
                    Text(trackingStatus)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(isTracking ? .green : .gray)
                }
                
                if let startTime = startTime {
                    let elapsed = Date().timeIntervalSince(startTime)
                    HStack {
                        Text("Elapsed:")
                        Spacer()
                        Text(String(format: "%.1fs", elapsed))
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }
            .padding()
            .background(Color.black.opacity(0.5))
            .cornerRadius(10)
            
            // Control buttons
            HStack(spacing: 12) {
                Button(action: startTracking) {
                    Label("Start", systemImage: "record.circle.fill")
                        .font(.system(.body, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(isTracking ? Color.gray.opacity(0.5) : Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .disabled(isTracking)
                
                Button(action: stopTracking) {
                    Label("Stop", systemImage: "stop.circle.fill")
                        .font(.system(.body, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(isTracking ? Color.red : Color.gray.opacity(0.5))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .disabled(!isTracking)
                
                Button(action: reset) {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .font(.system(.body, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            
            Divider()
            
            // Results section
            if !romResults.isEmpty {
                Text("ROM Calculations")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                VStack(alignment: .leading, spacing: 12) {
                    // Handheld ROM (Arc-based) - PRIMARY
                    ROMResultRow(
                        title: "✅ Handheld ROM (Arc-based)",
                        value: romResults["handheld"] ?? 0,
                        description: "From HandheldROMCalculator - arc length / arm length",
                        isHighlight: true
                    )
                    
                    Divider()
                    
                    // ROM Audit (Debug) - for comparison
                    if let auditROM = romResults["audit"] {
                        ROMResultRow(
                            title: "📐 ROM Audit",
                            value: auditROM,
                            description: "Debug method - for verification",
                            isHighlight: false
                        )
                    }
                    
                    // Current ROM (mixed sources)
                    if let currentROM = romResults["current"] {
                        ROMResultRow(
                            title: "⚡️ Current ROM",
                            value: currentROM,
                            description: "motionService.currentROM - may include IMU",
                            isHighlight: false
                        )
                    }
                }
                .padding()
                .background(Color.black.opacity(0.3))
                .cornerRadius(10)
                
                // Info section
                VStack(alignment: .leading, spacing: 8) {
                    Text("How to test:")
                        .font(.caption)
                        .fontWeight(.bold)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Label("1. Tap 'Start' to begin ARKit tracking", systemImage: "1.circle.fill")
                        Label("2. Hold device stable and perform one clear motion", systemImage: "2.circle.fill")
                        Label("3. Tap 'Stop' to complete the rep", systemImage: "3.circle.fill")
                        Label("4. Compare ROM values below to find accurate method", systemImage: "4.circle.fill")
                    }
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(10)
                
            } else {
                VStack {
                    Image(systemName: "chart.bar")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("No ROM data yet")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.black)
        .foregroundColor(.white)
    }
    
    private func startTracking() {
        isTracking = true
        trackingStatus = "Tracking..."
        startTime = Date()
        romResults.removeAll()
        
        // Start session and calibrate baseline
        motionService.startSession(gameType: .makeYourOwn)
    }
    
    private func stopTracking() {
        guard isTracking else { return }
        isTracking = false
        trackingStatus = "Processing..."
        
        // Complete the rep and capture ROM values
        motionService.completeHandheldRep()
        
        let handheldROM = motionService.getLastHandheldRepROM()
        let currentROM = motionService.currentROM
        
        romResults = [
            "handheld": handheldROM,
            "current": currentROM,
            "audit": handheldROM  // Same as handheld for audit display
        ]
        
        trackingStatus = "Done! Compare values above"
        
        FlexaLog.game.info("📊 [TestROM] Handheld: \(String(format: "%.1f", handheldROM))° | Current: \(String(format: "%.1f", currentROM))°")
    }
    
    private func reset() {
        isTracking = false
        trackingStatus = "Ready"
        startTime = nil
        romResults.removeAll()
        motionService.stopSession()
    }
}

struct ROMResultRow: View {
    let title: String
    let value: Double
    let description: String
    let isHighlight: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isHighlight ? .bold : .regular)
                Spacer()
                Text(String(format: "%.1f°", value))
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(isHighlight ? .green : .yellow)
            }
            Text(description)
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
}

#Preview {
    TestROMCardView()
}
