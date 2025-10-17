import SwiftUI

struct TestROMCardView: View {
    @StateObject private var motionService = SimpleMotionService.shared
    @State private var isTestingRep = false
    @State private var lastRepROM: Double?
    @State private var statusText = "Ready"

    var body: some View {
        VStack(spacing: 16) {
            Text("🧪 Handheld ROM Rep Test")
                .font(.title2)
                .fontWeight(.bold)

            // Status and Results
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Status:")
                    Spacer()
                    Text(statusText)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(isTestingRep ? .yellow : .green)
                }

                if let rom = lastRepROM {
                    HStack {
                        Text("Last Rep ROM:")
                            .fontWeight(.bold)
                        Spacer()
                        Text(String(format: "%.1f°", rom))
                            .font(.system(.title, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    }
                } else {
                    Text("Perform a rep to see the ROM result.")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .padding()
            .background(Color.black.opacity(0.5))
            .cornerRadius(10)

            // Control buttons
            HStack(spacing: 12) {
                Button(action: startRep) {
                    Label("Start Rep", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(isTestingRep)

                Button(action: finishRep) {
                    Label("Finish Rep", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!isTestingRep)
            }
            
            Divider()

            // Instructions
            VStack(alignment: .leading, spacing: 8) {
                Text("Instructions:")
                    .font(.headline)
                Label("1. Press 'Start Rep'.", systemImage: "1.circle")
                Label("2. Perform a single, clear arc motion (like Fruit Slicer).", systemImage: "2.circle")
                Label("3. Press 'Finish Rep' to calculate and display the ROM.", systemImage: "3.circle")
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.black.opacity(0.3))
            .cornerRadius(10)


            Spacer()
        }
        .padding()
        .background(Color.black)
        .foregroundColor(.white)
        .onAppear(perform: setup)
        .onDisappear(perform: teardown)
    }

    private func setup() {
        // Use .fruitSlicer to engage the handheld arc-style ROM calculation.
        motionService.startSession(gameType: .fruitSlicer)
        motionService.activateInstantARKitTracking(source: "TestROMCardView")
        statusText = "Ready"
    }
    
    private func teardown() {
        motionService.stopSession()
        motionService.deactivateInstantARKitTracking(source: "TestROMCardView")
    }

    private func startRep() {
        lastRepROM = nil
        // Calling completeRep here clears any previously tracked points in the calculator,
        // effectively starting a new rep measurement.
        motionService.completeHandheldRep()
        isTestingRep = true
        statusText = "Recording..."
    }

    private func finishRep() {
        guard isTestingRep else { return }
        
        // Complete the rep, which triggers the ROM calculation.
        motionService.completeHandheldRep()
        
        // The result is not available instantaneously. We wait a moment for the
        // async calculations in the service to complete.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let rom = motionService.getLastHandheldRepROM()
            self.lastRepROM = rom
            self.statusText = "Finished"
            self.isTestingRep = false
            FlexaLog.game.info("📊 [TestROMCard] Rep finished. ROM: \(String(format: "%.1f", rom))°")
        }
    }
}

#Preview {
    TestROMCardView()
}