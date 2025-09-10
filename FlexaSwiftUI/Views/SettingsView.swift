import SwiftUI
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject var firebaseService: FirebaseService
    @State private var notificationsEnabled = true
    @State private var soundEnabled = true
    @State private var hapticFeedback = true
    @State private var cameraPermission = false
    @State private var motionPermission = false
    @State private var showingDataAlert = false
    @State private var showingClearAlert = false
    @State private var isExportingData = false
    @State private var shareURL: URL? = nil
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Profile Header
                    VStack(spacing: 16) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 80, height: 80)
                            .overlay(
                                Text("👤")
                                    .font(.system(size: 40))
                            )
                        
                        VStack(spacing: 4) {
                            Text("Flexa User")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text("Physiotherapy Rehabilitation")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.top, 20)
                    
                    // Data Management Section
                    SettingsSection(title: "Data Management") {
                        SettingsRow(
                            icon: "arrow.down.circle.fill",
                            title: "Download Data",
                            subtitle: "Export your exercise data",
                            action: {
                                downloadData()
                            }
                        )
                        
                        SettingsRow(
                            icon: "trash.circle.fill",
                            title: "Clear All Data",
                            subtitle: "Delete all stored exercise data",
                            isDestructive: true,
                            action: {
                                showingClearAlert = true
                            }
                        )
                    }
                    
                    // App Preferences Section
                    SettingsSection(title: "App Preferences") {
                        SettingsToggleRow(
                            icon: "bell.fill",
                            title: "Notifications",
                            subtitle: "Exercise reminders and achievements",
                            isOn: $notificationsEnabled
                        )
                        
                        SettingsToggleRow(
                            icon: "speaker.wave.2.fill",
                            title: "Sound Effects",
                            subtitle: "Game sounds and feedback",
                            isOn: $soundEnabled
                        )
                        
                        SettingsToggleRow(
                            icon: "iphone.radiowaves.left.and.right",
                            title: "Haptic Feedback",
                            subtitle: "Vibration feedback during exercises",
                            isOn: $hapticFeedback
                        )
                    }
                    
                    // Permissions Section
                    SettingsSection(title: "Permissions") {
                        SettingsStatusRow(
                            icon: "camera.fill",
                            title: "Camera Access",
                            subtitle: "Required for pose detection",
                            isGranted: cameraPermission
                        )
                        
                        SettingsStatusRow(
                            icon: "gyroscope",
                            title: "Motion Sensors",
                            subtitle: "Required for motion tracking",
                            isGranted: motionPermission
                        )
                    }
                    
                    // Exercise Settings Section
                    SettingsSection(title: "Exercise Settings") {
                        NavigationLink(destination: CalibrationIntroView().environmentObject(SimpleMotionService.shared)) {
                            SettingsRowContent(
                                icon: "figure.strengthtraining.traditional",
                                title: "ROM Calibration",
                                subtitle: "Accurate 0° / 90° / 180° calibration with AR + IMU"
                            )
                        }
                    }
                    
                    // Privacy & Legal Section
                    SettingsSection(title: "Privacy & Legal") {
                        NavigationLink(destination: PrivacyPolicyView()) {
                            SettingsRowContent(
                                icon: "hand.raised.fill",
                                title: "Privacy Policy",
                                subtitle: "How we protect your data"
                            )
                        }
                        
                        NavigationLink(destination: AboutUsView()) {
                            SettingsRowContent(
                                icon: "info.circle.fill",
                                title: "About Us",
                                subtitle: "Learn about Flexa"
                            )
                        }
                        
                        NavigationLink(destination: TermsOfServiceView()) {
                            SettingsRowContent(
                                icon: "doc.text.fill",
                                title: "Terms of Service",
                                subtitle: "Usage terms and conditions"
                            )
                        }
                    }
                    
                    // App Info
                    VStack(spacing: 8) {
                        Text("Flexa v1.0.0")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        Text("Built with ❤️ for rehabilitation")
                            .font(.caption2)
                            .foregroundColor(.gray.opacity(0.7))
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 100) // Bottom padding for floating nav
                }
                .padding(.horizontal, 20)
            }
            .background(Color.black)
            .navigationBarHidden(true)
        }
        .alert("Clear All Data", isPresented: $showingClearAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                clearAllData()
            }
        } message: {
            Text("This will permanently delete all your exercise data. This action cannot be undone.")
        }
        .alert("Data Export", isPresented: $showingDataAlert) {
            Button("OK") { }
        } message: {
            Text(isExportingData ? "Exporting your data..." : "Export complete. A share sheet will open. You can also find the file in the Files app → On My iPhone → Flexa.")
        }
        .onAppear {
            checkPermissions()
        }
        // Share sheet after export completes
        .sheet(isPresented: Binding<Bool>(
            get: { shareURL != nil },
            set: { if !$0 { shareURL = nil } }
        )) {
            if let url = shareURL {
                ActivityView(url: url)
            }
        }
    }
    
    private func checkPermissions() {
        // Check camera permission
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraPermission = true
        default:
            cameraPermission = false
        }
        
        // Check motion permission (simplified)
        motionPermission = true // Would check CMMotionManager in real implementation
    }
    
    private func downloadData() {
        // Immediate haptic feedback before processing
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        
        isExportingData = true
        showingDataAlert = true
        
        // Run export on background thread to prevent UI lag
        Task.detached(priority: .userInitiated) {
            let exportURL = DataExportService.shared.exportAllUserData()
            
            await MainActor.run {
                self.isExportingData = false
                
                if let exportURL = exportURL {
                    // Dismiss alert first; then present share sheet after a short delay
                    self.showingDataAlert = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        self.shareURL = exportURL
                    }
                } else {
                    // Keep alert; user can acknowledge
                }
            }
        }
    }

    // MARK: - UIKit Share Sheet bridge
    struct ActivityView: UIViewControllerRepresentable {
        let url: URL
        func makeUIViewController(context: Context) -> UIActivityViewController {
            let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            return vc
        }
        func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
    }
    
    private func clearAllData() {
        // Immediate haptic feedback before processing
        HapticFeedbackService.shared.destructiveActionHaptic()
        
        // Run on background thread to prevent UI lag
        Task.detached(priority: .userInitiated) {
            do {
                // 1) Clear Firebase data (sessions/goals/streaks)
                try await firebaseService.clearAllUserData()
                // 2) Clear local caches (sessions/goals/streaks/timelines/sequence)
                await MainActor.run {
                    LocalDataManager.shared.clearLocalData()
                }
                // 3) Optionally refresh session sequence base from server count (now likely 0)
                do {
                    let count = try await firebaseService.fetchSessionCount()
                    await MainActor.run {
                        LocalDataManager.shared.setSessionSequenceBase(count)
                    }
                } catch {
                    // If count fails, leave base unset (defaults to 0)
                }
                print("All data cleared successfully")
            } catch {
                print("Error clearing data: \(error)")
            }
        }
    }
}

struct DifficultySettingsView: View {
    @State private var selectedDifficulty = Difficulty.medium
    
    var body: some View {
        Form {
            Section("Game Difficulty") {
                Picker("Difficulty Level", selection: $selectedDifficulty) {
                    ForEach(Difficulty.allCases, id: \.self) { difficulty in
                        Text(difficulty.displayName).tag(difficulty)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            
            Section("Difficulty Description") {
                Text(selectedDifficulty.description)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Difficulty")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ROMCalibrationView: View {
    @State private var isCalibrating = false
    @State private var calibrationStep = 0
    
    var body: some View {
        VStack(spacing: 30) {
            Text("ROM Calibration")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Calibrate your range of motion for more accurate exercise tracking")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            if !isCalibrating {
                Button("Start Calibration") {
                    startCalibration()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                VStack(spacing: 20) {
                    Text("Step \(calibrationStep + 1) of 3")
                        .font(.headline)
                    
                    Text(calibrationInstructions[calibrationStep])
                        .multilineTextAlignment(.center)
                    
                    Button("Next") {
                        nextCalibrationStep()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private let calibrationInstructions = [
        "Raise your arms to your maximum comfortable height",
        "Lower your arms to your natural resting position",
        "Move your arms in a full circle motion"
    ]
    
    private func startCalibration() {
        isCalibrating = true
        calibrationStep = 0
    }
    
    private func nextCalibrationStep() {
        if calibrationStep < 2 {
            calibrationStep += 1
        } else {
            isCalibrating = false
            calibrationStep = 0
        }
    }
}

struct ExerciseHistoryView: View {
    var body: some View {
        List {
            ForEach(sampleExerciseHistory, id: \.id) { session in
                ExerciseHistoryRow(session: session)
            }
        }
        .navigationTitle("Exercise History")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ExerciseHistoryRow: View {
    let session: ExerciseSession
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.gameName)
                    .font(.headline)
                Spacer()
                Text(session.date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Label("\(session.duration) min", systemImage: "clock")
                Spacer()
                Label("\(session.reps) reps", systemImage: "repeat")
                Spacer()
                Label("\(session.maxROM)° ROM", systemImage: "arrow.up.and.down")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Privacy Policy")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Your privacy is important to us. This app collects motion and camera data solely for exercise tracking and analysis.")
                
                Text("Data Collection")
                    .font(.headline)
                
                Text("• Camera data is processed locally on your device\n• Motion sensor data is used for exercise tracking\n• No personal data is shared with third parties")
                
                Text("Data Storage")
                    .font(.headline)
                
                Text("• Exercise data is stored locally on your device\n• You can delete your data at any time\n• No cloud storage of personal information")
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TermsOfServiceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Terms of Service")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("By using Flexa, you agree to these terms of service.")
                
                Text("Medical Disclaimer")
                    .font(.headline)
                
                Text("This app is for rehabilitation assistance only and should not replace professional medical advice.")
                
                Text("Usage Guidelines")
                    .font(.headline)
                
                Text("• Use the app in a safe environment\n• Follow exercise instructions carefully\n• Stop if you experience pain or discomfort\n• Consult healthcare providers for medical advice")
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

enum Difficulty: String, CaseIterable {
    case easy, medium, hard
    
    var displayName: String {
        switch self {
        case .easy: return "Easy"
        case .medium: return "Medium"
        case .hard: return "Hard"
        }
    }
    
    var description: String {
        switch self {
        case .easy: return "Slower movements, larger targets, more forgiving timing"
        case .medium: return "Balanced difficulty for most users"
        case .hard: return "Faster movements, smaller targets, precise timing required"
        }
    }
}

struct ExerciseSession {
    let id = UUID()
    let gameName: String
    let date: String
    let duration: Int
    let reps: Int
    let maxROM: Int
}

let sampleExerciseHistory = [
    ExerciseSession(gameName: "Fruit Slicer", date: "Today", duration: 5, reps: 25, maxROM: 92),
    ExerciseSession(gameName: "Arm Raises", date: "Yesterday", duration: 8, reps: 40, maxROM: 87),
    ExerciseSession(gameName: "Balloon Pop", date: "2 days ago", duration: 6, reps: 30, maxROM: 85),
    ExerciseSession(gameName: "Potion Mixer", date: "3 days ago", duration: 7, reps: 35, maxROM: 90)
]

#Preview {
    SettingsView()
}
