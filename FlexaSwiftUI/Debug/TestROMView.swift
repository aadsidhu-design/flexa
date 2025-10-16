//
//  TestROMView.swift
//  FlexaSwiftUI
//
//  Created by Copilot on 10/6/25.
//
//  🔬 Interactive ROM testing harness for handheld ARKit tracking.
//  Allows choosing a motion pattern, capturing ARKit transforms, and inspecting the
//  fitted plane + 2D projection metrics.
//

import SwiftUI
import simd

struct TestROMView: View {
    @ObservedObject private var motionService = SimpleMotionService.shared
    @State private var selectedPattern: TestROMPattern = .circle
    @State private var isCapturing = false
    @State private var capturedPositions: [SIMD3<Float>] = []
    @State private var metrics: TestROMMetrics?
    @State private var lastCaptureTime: Date?
    @State private var showAlert = false

    private let processor = TestROMProcessor()

    var body: some View {
        VStack(spacing: 24) {
            Text("Test ROM Harness")
                .font(.largeTitle.bold())
                .padding(.top, 16)

            Picker("Pattern", selection: $selectedPattern) {
                ForEach(TestROMPattern.allCases) { pattern in
                    Text(pattern.rawValue.capitalized).tag(pattern)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Capturing:")
                    Spacer()
                    Circle()
                        .fill(isCapturing ? Color.green : Color.red)
                        .frame(width: 12, height: 12)
                }
                Text("Samples captured: \(capturedPositions.count)")
                if let metrics {
                    metricsView(metrics)
                } else {
                    Text("No results yet. Tap Start, move through the motion, then tap Stop.")
                        .foregroundColor(.secondary)
                        .font(.callout)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
            .padding(.horizontal)

            HStack(spacing: 16) {
                Button(action: startCapture) {
                    Label("Start ROM", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCapturing)

                Button(action: stopCapture) {
                    Label("Stop ROM", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!isCapturing)
            }
            .padding(.horizontal)

            Spacer()
        }
        .onAppear(perform: setup)
        .onDisappear(perform: teardown)
        .onReceive(motionService.arkitTracker.$currentPosition.compactMap { $0 }) { position in
            guard isCapturing else { return }
            capturedPositions.append(position)
            if capturedPositions.count > 1200 {
                capturedPositions.removeFirst(capturedPositions.count - 1200)
            }
            lastCaptureTime = Date()
        }
        .alert("Not enough samples", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Move through the motion for at least a few seconds before stopping.")
        }
    }

    private func metricsView(_ metrics: TestROMMetrics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pattern: \(metrics.pattern.rawValue.capitalized)")
                .font(.headline)
            Text(String(format: "Average radius: %.2f m", metrics.averageRadius))
            Text(String(format: "Radius σ: %.2f", metrics.radiusStdDev))
            Text(String(format: "Coverage: %.1f°", metrics.coverageDegrees))
            Text(String(format: "Plane normal: [%.2f, %.2f, %.2f]",
                        metrics.projection.normal.x,
                        metrics.projection.normal.y,
                        metrics.projection.normal.z))
            Text(String(format: "Samples: %d", metrics.projection.projectedPoints.count))
        }
    }

    private func startCapture() {
        motionService.activateInstantARKitTracking(source: "TestROMView.startCapture")

        capturedPositions.removeAll()
        metrics = nil
        isCapturing = true
        lastCaptureTime = nil
    }

    private func stopCapture() {
        guard isCapturing else { return }
        isCapturing = false
        guard capturedPositions.count >= 10 else {
            showAlert = true
            return
        }
        metrics = processor.process(points: capturedPositions, pattern: selectedPattern)
    }

    private func setup() {
        // Ensure ARKit session is alive for preview/testing
        motionService.activateInstantARKitTracking(source: "TestROMView")
    }

    private func teardown() {
        isCapturing = false
        capturedPositions.removeAll()
        motionService.deactivateInstantARKitTracking(source: "TestROMView.teardown")
    }
}

struct TestROMView_Previews: PreviewProvider {
    static var previews: some View {
        TestROMView()
    }
}
