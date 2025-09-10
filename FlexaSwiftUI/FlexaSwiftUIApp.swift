import SwiftUI
import AVFoundation
import Firebase

@main
struct FlexaSwiftUIApp: App {
    @StateObject private var firebaseService = FirebaseService()
    @StateObject private var streaksService = GoalsAndStreaksService()
    @StateObject private var goalsService = GoalsService()
    @StateObject private var geminiService = GeminiService()
    @StateObject private var recommendationsEngine = RecommendationsEngine()
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var motionService = SimpleMotionService.shared
    @StateObject private var coreMotionSensorService = CoreMotionSensorService()
    @StateObject private var navigationCoordinator = NavigationCoordinator()
    
    init() {
        FlexaLog.lifecycle.info("App init — configuring services")
        // Configure Firebase
        FirebaseApp.configure()
        FlexaLog.lifecycle.info("Firebase configured")
        
        // Setup secure API keys (env preferred)
        KeychainManager.shared.setupInitialKeys()
        
        // Validate security configuration
        SecureConfig.shared.logSecurityStatus()
        
        // Setup notifications on app launch
        NotificationService.shared.setupDefaultNotifications()
        FlexaLog.lifecycle.info("Notifications configured")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(firebaseService)
                .environment(\.firebaseService, firebaseService)
                .environmentObject(goalsService)
                .environmentObject(streaksService)
                .environmentObject(geminiService)
                .environmentObject(recommendationsEngine)
                .environmentObject(themeManager)
                .environmentObject(motionService)
                .environmentObject(coreMotionSensorService)
                .environmentObject(navigationCoordinator)
                .environment(\.theme, themeManager)
                .preferredColorScheme(.dark)
                .onAppear {
                    // Sign in anonymously and load user data
                    Task {
                        FlexaLog.lifecycle.info("Startup — anonymous sign-in start")
                        do {
                            try await firebaseService.signInAnonymously()
                            FlexaLog.lifecycle.info("Startup — anonymous sign-in success")
                        } catch {
                            FlexaLog.lifecycle.error("Startup — anonymous sign-in failed: \(error.localizedDescription)")
                        }
                        
                        // Preload all data to prevent UI lag
                        FlexaLog.lifecycle.info("🚀 [PRELOAD] Starting background data loading...")
                        
                        // Load user data and goals
                        streaksService.loadUserData()
                        goalsService.loadGoals()
                        
                        // Preload motion service and camera permissions
                        requestPermissions()
                        
                        await recommendationsEngine.generatePersonalizedRecommendations()
                        
                        FlexaLog.lifecycle.info("✅ [PRELOAD] Background data loading complete")
                    }
                }
        }
    }
    
    private func requestPermissions() {
        // Only request camera permission, don't start camera
        AVCaptureDevice.requestAccess(for: .video) { granted in
            FlexaLog.lifecycle.info("Camera permission: \(granted ? "granted" : "denied")")
            // Camera will only start when needed for exercises
        }
    }
}
