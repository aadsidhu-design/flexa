import SwiftUI
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject var backendService: BackendService
    @State private var notificationsEnabled = true
    @State private var soundEnabled = true
    @State private var cameraPermission = false
    @State private var motionPermission = false
    @State private var showingDataAlert = false
    @State private var showingDownloadConfirmation = false
    @State private var showingClearAlert = false
    @State private var isExportingData = false
    @State private var shareURL: URL? = nil
    @State private var exportMessage = ""
    
    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
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
                    
                    // Data Management Section
                    SettingsSection(title: "Data Management") {
                        SettingsRow(
                            icon: "arrow.down.circle.fill",
                            title: "Download Data",
                            subtitle: "Export all your exercise data",
                            action: {
                                showingDownloadConfirmation = true
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
                        Button(action: {
                            CalibrationCheckService.shared.resetCalibration()
                            // Force show onboarding
                            NotificationCenter.default.post(name: NSNotification.Name("ShowCalibrationOnboarding"), object: nil)
                        }) {
                            SettingsRowContent(
                                icon: "arrow.clockwise",
                                title: "Reset Calibration",
                                subtitle: "Clear calibration data and recalibrate"
                            )
                        }
                        .foregroundColor(.orange)
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
        .alert("Download Your Data?", isPresented: $showingDownloadConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Download") {
                downloadData()
            }
        } message: {
            Text("This will export all your exercise data including sessions, ROM measurements, SPARC scores, and progress metrics to a JSON file that you can save and share.")
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
            Button("OK") {
                // Clear export message
                exportMessage = ""
            }
        } message: {
            Text(exportMessage)
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
        exportMessage = "Preparing your data export..."
        
        // Run export on background thread to prevent UI lag
        Task.detached(priority: .userInitiated) {
            // Get all user data
            guard let exportURL = DataExportService.shared.exportAllUserData() else {
                await MainActor.run {
                    self.isExportingData = false
                    self.exportMessage = "Export failed. Please try again."
                    self.showingDataAlert = true
                }
                return
            }
            
            // Get file size and session count for info
            let sessionCount = LocalDataManager.shared.getCachedComprehensiveSessions().count
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: exportURL.path)[.size] as? Int64) ?? 0
            let fileSizeMB = Double(fileSize) / 1_048_576.0
            
            await MainActor.run {
                self.isExportingData = false
                self.exportMessage = """
                Export Complete!
                
                📊 \(sessionCount) sessions exported
                💾 File size: \(String(format: "%.2f", fileSizeMB)) MB
                
                The file will open in a share sheet. You can:
                • Save to Files app
                • Share via AirDrop
                • Email to yourself
                • Upload to cloud storage
                
                File location: Documents/Flexa/
                """
                self.showingDataAlert = true
                
                // Show share sheet after alert
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.shareURL = exportURL
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
                // 1) Clear cloud data (sessions/goals/streaks) via BackendService
                try await backendService.clearAllUserData()
                // Local caches and session numbering handled by BackendService
                // 3) Exercise number preserved via BackendService.refreshSessionSequenceBaseFromCloud()
                print("All data cleared successfully")
                
                // 4) Post notification to refresh all views
                await MainActor.run {
                    NotificationCenter.default.post(name: NSNotification.Name("DataCleared"), object: nil)
                }
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
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Privacy Policy")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Last Updated: December 2024")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Text("Flexa is committed to protecting your privacy and personal information. This comprehensive privacy policy explains how we collect, use, store, and protect your data when you use our physiotherapy rehabilitation application.")
                    .font(.body)
                
                Group {
                    Text("1. Information We Collect")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("1.1 Personal Health Information")
                        .font(.headline)
                    
                    Text("• Pain level assessments (pre and post exercise)\n• Exercise performance metrics (ROM, reps, duration)\n• Movement quality scores and smoothness data\n• Exercise history and progress tracking\n• User preferences and settings")
                    
                    Text("1.2 Device and Sensor Data")
                        .font(.headline)
                    
                    Text("• Accelerometer data for motion tracking\n• Gyroscope data for orientation detection\n• Camera data for pose estimation (processed locally)\n• Device motion and user acceleration data\n• Calibration data for personalized tracking")
                    
                    Text("1.3 Usage and Analytics Data")
                        .font(.headline)
                    
                    Text("• App usage patterns and session duration\n• Feature usage statistics\n• Performance metrics and error logs\n• Device information (model, OS version)\n• Network connectivity status")
                }
                
                Group {
                    Text("2. How We Use Your Information")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("2.1 Primary Purposes")
                        .font(.headline)
                    
                    Text("• Provide personalized physiotherapy exercises\n• Track rehabilitation progress and improvements\n• Generate AI-powered feedback and recommendations\n• Monitor exercise form and technique\n• Calculate range of motion and movement quality\n• Store exercise history for progress tracking")
                    
                    Text("2.2 Secondary Purposes")
                        .font(.headline)
                    
                    Text("• Improve app functionality and user experience\n• Develop new features and exercises\n• Conduct research on rehabilitation outcomes (anonymized)\n• Provide technical support and troubleshooting\n• Ensure app security and prevent abuse")
                }
                
                Group {
                    Text("3. Data Storage and Security")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("3.1 Local Storage")
                        .font(.headline)
                    
                    Text("• All personal health data is stored locally on your device\n• Data is encrypted using iOS Keychain services\n• No personal data is transmitted to external servers\n• You maintain full control over your data")
                    
                    Text("3.2 Cloud Storage (Optional)")
                        .font(.headline)
                    
                    Text("• Anonymous usage analytics may be stored in secure cloud services\n• No personally identifiable information is included\n• Data is encrypted in transit and at rest\n• Cloud storage is optional and can be disabled")
                    
                    Text("3.3 Security Measures")
                    .font(.headline)
                    
                    Text("• End-to-end encryption for all data transmission\n• Regular security audits and updates\n• Access controls and authentication\n• Data backup and recovery procedures\n• Compliance with healthcare data standards")
                }
                
                Group {
                    Text("4. Data Sharing and Third Parties")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("4.1 No Personal Data Sharing")
                        .font(.headline)
                    
                    Text("• We do not sell, rent, or share your personal health data\n• No third-party access to your exercise information\n• Data is not used for advertising or marketing\n• No data mining or profiling activities")
                    
                    Text("4.2 Service Providers")
                        .font(.headline)
                    
                    Text("• We may use trusted service providers for app functionality\n• All providers are bound by strict confidentiality agreements\n• Providers only access data necessary for their services\n• No personal health data is shared with service providers")
                }
                
                Group {
                    Text("5. Your Rights and Controls")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("5.1 Data Access and Portability")
                        .font(.headline)
                    
                    Text("• Export all your data at any time\n• View and download your exercise history\n• Access your information\n• Request data in a portable format")
                    
                    Text("5.2 Data Deletion")
                        .font(.headline)

                    Text("• Delete all data with a single action\n• Selective deletion of specific sessions\n• Permanent removal from your devices\n• No data retention on your device after deletion")

                    Text("5.3 Privacy Controls")
                    .font(.headline)
                    
                }
                
                Group {
                    Text("6. Children's Privacy")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("• Our app is not intended for children under 5\n• We do not knowingly collect data from children under 5\n• Parents should supervise app usage by children under 5\n• Contact us if you believe a child's data was collected")
                }
                
                Group {
                    Text("7. International Data Transfers")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("• Data is primarily processed on your device\n• Any cloud processing occurs in secure, compliant facilities\n• We comply with international data protection laws\n• Adequate safeguards are in place for data transfers")
                }
                
                Group {
                    Text("8. Changes to This Policy")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("• We may update this policy periodically\n• Significant changes will be communicated to users\n• Continued use constitutes acceptance of changes\n• Previous versions are available upon request")
                }
                
                Group {
                    Text("9. Contact Information")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("For privacy-related questions or concerns:\n\nEmail: aadjotsidhu@gmail.com\nPhone: 1-669-377-4224")
                }
                
                Text("This privacy policy is effective as of September 2025 and applies to all users of the Flexa application.")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.top)
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TermsOfServiceView: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Terms of Service")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Last Updated: September 2025")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Text("Welcome to Flexa. These Terms of Service ('Terms') govern your use of our physiotherapy rehabilitation application and services. By accessing or using Flexa, you agree to be bound by these Terms.")
                    .font(.body)
                
                Group {
                    Text("1. Acceptance of Terms")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("By downloading, installing, or using the Flexa application, you acknowledge that you have read, understood, and agree to be bound by these Terms. If you do not agree to these Terms, you may not use our services.")
                    
                    Text("1.1 Eligibility")
                        .font(.headline)
                    
                    Text("• You must be at least 5 years old to use this application\n• Users under 5 must have parental supervision\n• You must have the legal capacity to enter into this agreement\n• You must not be prohibited from using the app under applicable law")
                }
                
                Group {
                    Text("2. Description of Service")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Flexa is a digital physiotherapy rehabilitation application that provides:\n\n• Interactive exercise games and activities\n• Motion tracking and analysis\n• AI-powered feedback and recommendations\n• Progress monitoring and reporting\n• Educational content and guidance")
                    
                    Text("2.1 Service Availability")
                        .font(.headline)
                    
                    Text("• Services are provided on an 'as is' and 'as available' basis\n• We reserve the right to modify or discontinue services\n• Service availability may be affected by technical issues\n• We do not guarantee uninterrupted access to the application")
                }
                
                Group {
                    Text("3. Medical Disclaimer and Limitations")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("3.1 Not a Medical Device")
                        .font(.headline)
                    
                    Text("• Flexa is NOT a medical device or diagnostic tool\n• The application is for rehabilitation assistance only\n• It should not replace professional medical advice\n• Always consult healthcare providers for medical decisions")
                    
                    Text("3.2 No Medical Advice")
                        .font(.headline)
                    
                    Text("• We do not provide medical advice, diagnosis, or treatment\n• Information provided is for educational purposes only\n• Exercise recommendations are general guidelines\n• Individual medical conditions may require different approaches")
                    
                    Text("3.3 User Responsibility")
                        .font(.headline)
                    
                    Text("• You are responsible for your own health and safety\n• Stop exercising if you experience pain or discomfort\n• Consult healthcare providers before starting new exercises\n• Use the app only as directed by your healthcare team")
                }
                
                Group {
                    Text("4. User Obligations and Prohibited Uses")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("4.1 Proper Use")
                        .font(.headline)
                    
                    Text("• Use the app in a safe, appropriate environment\n• Follow all exercise instructions carefully\n• Provide accurate information when prompted\n• Report any technical issues or concerns promptly")
                    
                    Text("4.2 Prohibited Activities")
                        .font(.headline)
                    
                    Text("• Do not use the app while driving or operating machinery\n• Do not attempt to reverse engineer or modify the app\n• Do not share your account with others\n• Do not use the app for any illegal or unauthorized purpose\n• Do not interfere with the app's security features")
                }
                
                Group {
                    Text("5. Privacy and Data Protection")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("5.1 Data Collection")
                        .font(.headline)
                    
                    Text("• We collect data as described in our Privacy Policy\n• Your health data is stored locally on your device and on the cloud\n• We implement appropriate security measures\n• You control your data and can delete it at any time. You can also request to delete your data that is stored on the cloud through the email: aadjotsidhu@gmail.com.")
                    
                    Text("5.2 Data Usage")
                        .font(.headline)
                    
                    Text("• Data is used to provide personalized rehabilitation services\n• We do not sell or share your personal health information\n• Anonymous data may be used for research and improvement\n•")
                }
                
                Group {
                    Text("6. Intellectual Property Rights")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("6.1 Our Rights")
                        .font(.headline)
                    
                    Text("• Flexa and all related content are protected by intellectual property laws\n• We retain all rights to the application and its content\n• You may not copy, modify, or distribute our content\n• Unauthorized use may result in legal action")
                    
                    Text("6.2 User Content")
                        .font(.headline)

                    Text("• You retain ownership of your personal data\n• You grant us limited rights to use your data for service provision\n• We do not claim ownership of your health information\n• You can revoke these rights by deleting your data and requesting to delete your cloud-stored data through the email: aadjotsidhu@gmail.com.")
                }
                
                Group {
                    Text("7. Disclaimers and Limitations of Liability")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("7.1 Service Disclaimers")
                        .font(.headline)
                    
                    Text("• The app is provided 'as is' without warranties of any kind\n• We do not guarantee the accuracy of exercise tracking\n• Results may vary based on individual circumstances\n• We are not responsible for any injuries or health issues")
                    
                    Text("7.2 Limitation of Liability")
                    .font(.headline)
                    
                    Text("• Our liability is limited to the maximum extent permitted by law\n• We are not liable for indirect, incidental, or consequential damages\n• Total liability shall not exceed the amount paid for the service\n• Some jurisdictions may not allow these limitations")
                }
                
                Group {
                    Text("8. Indemnification")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("You agree to indemnify and hold harmless Flexa, its officers, directors, employees, and agents from any claims, damages, or expenses arising from:\n\n• Your use of the application\n• Your violation of these Terms\n• Your violation of any third-party rights\n• Any content you submit or transmit through the app")
                }
                
                Group {
                    Text("9. Termination")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("9.1 Termination by You")
                        .font(.headline)
                    
                    Text("• You may stop using the app at any time\n• You can delete your account and data\n• Termination does not affect your data export rights\n• Some provisions may survive termination")
                    
                    Text("9.2 Termination by Us")
                        .font(.headline)
                    
                    Text("• We may suspend or terminate your access for violations\n• We will provide notice when reasonably possible\n• We may discontinue the service with appropriate notice\n• Termination does not affect your data ownership rights")
                }
                
                Group {
                    Text("10. Governing Law and Dispute Resolution")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("10.1 Governing Law")
                        .font(.headline)
                    
                    Text("• These Terms are governed by the laws of California, USA\n• Any disputes will be resolved in California courts\n• International users may have additional rights under local law")
                    
                    Text("10.2 Dispute Resolution")
                    .font(.headline)
                    
                    Text("• We encourage resolving disputes through direct communication\n• Mediation may be required before litigation\n• Class action waivers may apply in some jurisdictions\n• Individual arbitration may be required for certain disputes")
                }
                
                Group {
                    Text("11. Changes to Terms")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("• We may update these Terms from time to time\n• Material changes will be communicated to users\n• Continued use constitutes acceptance of new Terms\n• Previous versions are available upon request")
                }
                
                Group {
                    Text("12. Contact Information")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("For questions about these Terms:\n\nEmail: aadjotsidhu@gmail.com\nPhone: 1-669-377-4224")
                }
                
                Group {
                    Text("13. Severability")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("If any provision of these Terms is found to be unenforceable, the remaining provisions will remain in full force and effect. We will replace unenforceable provisions with enforceable ones that achieve the same purpose.")
                }
                
                Text("By using Flexa, you acknowledge that you have read and understood these Terms of Service and agree to be bound by them.")
                    .font(.body)
                    .fontWeight(.semibold)
                    .padding(.top)
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
