//
//  IMURepDetectorTestCard.swift
//  FlexaSwiftUI
//
//  Simple test card for IMU rep detection
//

import SwiftUI
import CoreMotion

struct IMURepDetectorTestCard: View {
    @StateObject private var testController = IMURepTestController()
    
    var body: some View {
        VStack(spacing: 24) {
            // Title
            Text("IMU Rep Detector Test")
                .font(.title2)
                .fontWeight(.bold)
            
            // Rep Counter
            VStack(spacing: 8) {
                Text("Reps Detected")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("\(testController.repCount)")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundColor(.blue)
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(16)
            
            // ROM Display
            VStack(spacing: 8) {
                Text("Current ROM")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("\(String(format: "%.1f", testController.currentROM))°")
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .foregroundColor(.green)
            }
            
            // Status
            HStack {
                Circle()
                    .fill(testController.isRunning ? Color.green : Color.gray)
                    .frame(width: 12, height: 12)
                
                Text(testController.isRunning ? "Detecting..." : "Stopped")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Last Rep Info
            if let lastRep = testController.lastRepInfo {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last Rep:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("ROM: \(String(format: "%.1f", lastRep.rom))° | Velocity: \(String(format: "%.2f", lastRep.velocity)) m/s")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
            
            Spacer()
            
            // Control Buttons
            HStack(spacing: 16) {
                Button(action: {
                    if testController.isRunning {
                        testController.stop()
                    } else {
                        testController.start()
                    }
                }) {
                    HStack {
                        Image(systemName: testController.isRunning ? "stop.fill" : "play.fill")
                        Text(testController.isRunning ? "Stop" : "Start")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(testController.isRunning ? Color.red : Color.blue)
                    .cornerRadius(12)
                }
                
                Button(action: {
                    testController.reset()
                }) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .cornerRadius(12)
                }
            }
        }
        .padding(24)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
        .padding()
    }
}

// MARK: - Test Controller

class IMURepTestController: ObservableObject {
    @Published var repCount: Int = 0
    @Published var currentROM: Double = 0
    @Published var isRunning: Bool = false
    @Published var lastRepInfo: RepInfo?
    
    struct RepInfo {
        let rom: Double
        let velocity: Double
        let timestamp: TimeInterval
    }
    
    private let motionManager = CMMotionManager()
    private let detector = IMUDirectionRepDetector()
    private var startTime: TimeInterval = 0
    
    init() {
        setupDetector()
    }
    
    private func setupDetector() {
        detector.onRepDetected = { [weak self] count, timestamp in
            DispatchQueue.main.async {
                self?.repCount = count
                // Store last rep info (mock velocity for now)
                self?.lastRepInfo = RepInfo(
                    rom: self?.currentROM ?? 0,
                    velocity: 0.5, // Mock value
                    timestamp: timestamp
                )
            }
        }
        
        detector.romProvider = { [weak self] in
            return self?.currentROM ?? 0
        }
    }
    
    func start() {
        guard !isRunning else { return }
        isRunning = true
        startTime = Date().timeIntervalSince1970
        
        detector.startSession()
        
        // Start motion updates
        guard motionManager.isDeviceMotionAvailable else {
            print("❌ Device motion not available")
            return
        }
        
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0 // 60 Hz
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self, let motion = motion else { return }
            
            let timestamp = Date().timeIntervalSince1970 - self.startTime
            self.detector.processDeviceMotion(motion, timestamp: timestamp)
            
            // Mock ROM calculation (in real app, this comes from ARKit)
            // Simulate ROM growing during movement
            self.currentROM = min(self.currentROM + Double.random(in: 0...2), 45)
        }
    }
    
    func stop() {
        guard isRunning else { return }
        isRunning = false
        
        motionManager.stopDeviceMotionUpdates()
        detector.stopSession()
    }
    
    func reset() {
        stop()
        repCount = 0
        currentROM = 0
        lastRepInfo = nil
        detector.resetState()
    }
}

// MARK: - Preview

struct IMURepDetectorTestCard_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray.opacity(0.2).ignoresSafeArea()
            IMURepDetectorTestCard()
        }
    }
}
