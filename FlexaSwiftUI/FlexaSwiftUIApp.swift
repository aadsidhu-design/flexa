import SwiftUI
import AVFoundation

@main
struct FlexaSwiftUIApp: App {
    @StateObject private var backendService: BackendService
    @StateObject private var streaksService: GoalsAndStreaksService
    @StateObject private var navigationCoordinator = NavigationCoordinator()
    @StateObject private var motionService = SimpleMotionService.shared
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var geminiService = GeminiService()
    @StateObject private var goalsService = GoalsService()
    
    init() {
        let backend = BackendService()
        _backendService = StateObject(wrappedValue: backend)
        _streaksService = StateObject(wrappedValue: GoalsAndStreaksService(backendService: backend))
        FlexaLog.lifecycle.info("App init — configuring services")
    // Backend service initialization (Appwrite)
    FlexaLog.lifecycle.info("Backend/Firebase service configured")
        
        // Setup secure API keys (env preferred)
        KeychainManager.shared.setupInitialKeys()
        
        // Validate security configuration
        SecureConfig.shared.logSecurityStatus()
        
        // Setup notifications on app launch
        NotificationService.shared.setupDefaultNotifications()
        FlexaLog.lifecycle.info("Notifications configured")
        
        // Start memory pressure monitoring
        MemoryManager.shared.startMemoryPressureMonitoring()
        FlexaLog.lifecycle.info("Memory monitoring started")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(backendService)
                .environment(\.backendService, backendService)
                .environmentObject(motionService)
                .environmentObject(navigationCoordinator)
                .environmentObject(themeManager) // Inject ThemeManager as EnvironmentObject
                .environmentObject(streaksService)
                .environmentObject(geminiService)
                .environmentObject(goalsService)
                .preferredColorScheme(.dark)
                .onAppear {
                    // Load user data and goals (local first, Azure in background)
                    FlexaLog.lifecycle.info("🚀 [PRELOAD] Starting background data loading...")

                    // One concise calibration summary at startup (reduces conflicting logs)
                    let calMgr = CalibrationDataManager.shared
                    let storedValid = calMgr.isCalibrated && (calMgr.currentCalibration?.isCalibrationValid ?? false)
                    let armLen = calMgr.currentCalibration?.armLength
                    let isARKit = calMgr.isCalibrated // ARKit calibration same as CalibrationDataManager
                    CalibrationCheckService.shared.checkCalibrationStatus()
                    let needsOnboarding = CalibrationCheckService.shared.shouldShowOnboarding
                    let armLenStr = armLen != nil ? String(format: "%.2f", armLen!) + "m" : "none"
                    print("🦾 [Startup] Calibration summary → StoredValid=\(storedValid), ARKit=\(isARKit), Onboarding=\(needsOnboarding), ArmLen=\(armLenStr)")

                    // Load user data and goals from local cache first (instant)
                    streaksService.loadUserData()
                    goalsService.loadGoals()
                    
                    // Preload motion service and camera permissions
                    requestPermissions()
                    
                    // Azure sign-in in background (non-blocking)
                    Task.detached {
                        FlexaLog.lifecycle.info("Startup — anonymous sign-in start")
                        do {
                            try await backendService.signInAnonymously()
                            FlexaLog.lifecycle.info("Startup — anonymous sign-in success")
                            await backendService.seedSessionSequenceIfNeeded()
                        } catch {
                            FlexaLog.lifecycle.error("Startup — anonymous sign-in failed: \(error.localizedDescription)")
                        }
                        await backendService.runFirebaseDiagnostics()
                    }
                    
                    
                    FlexaLog.lifecycle.info("✅ [PRELOAD] Background data loading complete")
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

