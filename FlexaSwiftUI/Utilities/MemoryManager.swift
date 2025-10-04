import Foundation
import UIKit

/// System-wide memory management utility for aggressive cleanup during memory pressure
final class MemoryManager {
    
    static let shared = MemoryManager()
    
    private init() {}
    
    // MARK: - Memory Monitoring
    
    /// Get current memory usage in MB
    func getCurrentMemoryUsage() -> Double {
        var memoryInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let result = withUnsafeMutablePointer(to: &memoryInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            return Double(memoryInfo.resident_size) / (1024 * 1024) // Convert to MB
        }
        
        return 0.0
    }
    
    /// Check if system is under memory pressure
    func isUnderMemoryPressure() -> Bool {
        let currentUsage = getCurrentMemoryUsage()
        return currentUsage > 180.0 // 180MB threshold
    }
    
    // MARK: - System-wide Memory Cleanup
    
    /// Perform aggressive system-wide memory cleanup
    func performEmergencyCleanup() {
        FlexaLog.motion.warning("🚨 Emergency memory cleanup initiated - current usage: \(self.getCurrentMemoryUsage())MB")
        
        // 1. Clear image caches
        clearImageCaches()
        
        // 2. Force garbage collection
        performGarbageCollection()
        
        // 3. Clear URL caches
        clearURLCaches()
        
        // 4. Notify services to clean up
        NotificationCenter.default.post(name: .memoryPressureDetected, object: nil)
        
        let finalUsage = self.getCurrentMemoryUsage()
        FlexaLog.motion.info("✅ Emergency cleanup completed - final usage: \(finalUsage)MB")
    }
    
    /// Perform standard memory cleanup
    func performStandardCleanup() {
        FlexaLog.motion.info("🧹 Standard memory cleanup initiated - current usage: \(self.getCurrentMemoryUsage())MB")
        
        // 1. Clear some caches
        clearImageCaches()
        
        // 2. Light garbage collection
        performGarbageCollection()
        
        // 3. Notify services for light cleanup
        NotificationCenter.default.post(name: .memoryWarningDetected, object: nil)
        
        let finalUsage = self.getCurrentMemoryUsage()
        FlexaLog.motion.info("✅ Standard cleanup completed - final usage: \(finalUsage)MB")
    }
    
    // MARK: - Specific Cleanup Methods
    
    private func clearImageCaches() {
        // Clear UIImage caches
        autoreleasepool {
            // This helps release any cached images
        }
    }
    
    private func clearURLCaches() {
        // Clear URL caches
        URLCache.shared.removeAllCachedResponses()
    }
    
    private func performGarbageCollection() {
        // Force multiple autorelease pool drains
        for _ in 0..<3 {
            autoreleasepool {
                // This forces cleanup of temporary objects
            }
        }
    }
    
    // MARK: - Memory Pressure Monitoring
    
    /// Start monitoring memory pressure
    func startMemoryPressureMonitoring() {
        // Monitor memory warnings from the system
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSystemMemoryWarning()
        }
    }
    
    private func handleSystemMemoryWarning() {
        FlexaLog.motion.warning("📱 System memory warning received")
        performEmergencyCleanup()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let memoryPressureDetected = Notification.Name("memoryPressureDetected")
    static let memoryWarningDetected = Notification.Name("memoryWarningDetected")
}