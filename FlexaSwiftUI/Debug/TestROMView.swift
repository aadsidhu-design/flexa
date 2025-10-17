//
//  TestROMView.swift
//  FlexaSwiftUI
//
//  Created by Copilot on 10/6/25.
//
//  🔬 Interactive ROM testing harness for handheld ARKit tracking.
//  This view now automatically detects and counts repetitions using ARKit.
//

import SwiftUI
import simd

struct TestROMView: View {
    @ObservedObject private var motionService = SimpleMotionService.shared
    @State private var selectedPattern: TestROMPattern = .circle // This can be kept for future use if needed
    @State private var capturedPositions: [SIMD3<Float>] = []
    @State private var lastCaptureTime: Date?

    var body: some View {
        VStack(spacing: 24) {
            Text("Automatic ROM Test")
                .font(.largeTitle.bold())
                .padding(.top, 16)

            VStack(alignment: .leading, spacing: 12) {
                Text("Live Repetition Count")
                    .font(.headline)
                
                HStack {
                    Text("Reps:")
                        .font(.title2)
                    Text("\(motionService.currentReps)")
                        .font(.title2.bold())
                        .foregroundColor(.green)
                    Spacer()
                }
                
                Text("Move your device through the exercise pattern to see the rep count update automatically.")
                    .foregroundColor(.secondary)
                    .font(.callout)
                
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
            .padding(.horizontal)

            Spacer()
        }
        .onAppear(perform: startAutomaticCapture)
        .onDisappear(perform: stopAutomaticCapture)
        .onReceive(motionService.arkitTracker.$currentPosition.compactMap { $0 }) { position in
            // Data is now processed by the HandheldRepDetector automatically.
            // We can still capture positions for potential future debugging or visualization.
            capturedPositions.append(position)
            if capturedPositions.count > 1200 {
                capturedPositions.removeFirst(capturedPositions.count - 1200)
            }
            lastCaptureTime = Date()
        }
    }

    private func startAutomaticCapture() {
        // Use a gameType that enables the HandheldRepDetector which uses ARKit data.
        // .followCircle is a good candidate for this.
        motionService.startSession(gameType: .followCircle)
        motionService.activateInstantARKitTracking(source: "TestROMView.startAutomaticCapture")
        capturedPositions.removeAll()
        lastCaptureTime = nil
    }

    private func stopAutomaticCapture() {
        motionService.stopSession()
        motionService.deactivateInstantARKitTracking(source: "TestROMView.stopAutomaticCapture")
        capturedPositions.removeAll()
    }
}

struct TestROMView_Previews: PreviewProvider {
    static var previews: some View {
        TestROMView()
    }
}
