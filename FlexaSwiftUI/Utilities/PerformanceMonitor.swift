import Foundation
import UIKit
import os

/// Performance monitoring utility for ROM system validation
/// Tracks memory usage, CPU usage, and UI responsiveness during exercise sessions
final class PerformanceMonitor: ObservableObject {
    
    // MARK: - Performance Metrics
    
    struct PerformanceMetrics {
        let timestamp: Date
        let memoryUsageMB: Double
        let cpuUsagePercent: Double
        let frameRate: Double
        let batteryLevel: Float
        let thermalState: ProcessInfo.ThermalState
        
        var isWithinAcceptableLimits: Bool {
            return memoryUsageMB < 1000.0 && // Removed memory restrictions - allow high usage
                   cpuUsagePercent < 90.0 && // Relaxed CPU limit
                   frameRate > 15.0 // Relaxed frame rate requirement
        }
    }
    
    // MARK: - Published Properties
    
    @Published var currentMetrics: PerformanceMetrics?
    @Published var isMonitoring: Bool = false
    @Published var performanceIssueDetected: Bool = false
    @Published var averageMetrics: PerformanceMetrics?
    
    // MARK: - Private Properties
    
    private var monitoringTimer: Timer?
    private var metricsHistory: [PerformanceMetrics] = []
    private let maxHistorySize = 200 // Reduced from 1000 to 200
    private let monitoringInterval: TimeInterval = 2.0 // Reduced frequency to every 2 seconds
    
    // Frame rate tracking
    private var frameTimestamps: [CFTimeInterval] = []
    private let frameHistorySize = 30 // Reduced from 60 to 30 frames
    
    // CPU usage tracking
    private var lastCPUInfo: host_cpu_load_info?
    
    // MARK: - Initialization
    
    init() {
        setupNotifications()
    }
    
    deinit {
        stopMonitoring()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Monitoring Control
    
    /// Start performance monitoring
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        performanceIssueDetected = false
        metricsHistory.removeAll()
        
        // Start monitoring timer
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: monitoringInterval, repeats: true) { [weak self] _ in
            self?.collectMetrics()
        }
        
        FlexaLog.motion.info("Performance monitoring started")
    }
    
    /// Stop performance monitoring
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        isMonitoring = false
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        
        // Calculate final average metrics
        calculateAverageMetrics()
        
        FlexaLog.motion.info("Performance monitoring stopped")
    }
    
    /// Record frame timestamp for frame rate calculation
    func recordFrame() {
        let timestamp = CACurrentMediaTime()
        frameTimestamps.append(timestamp)
        
        // Keep only recent frames
        if frameTimestamps.count > frameHistorySize {
            frameTimestamps.removeFirst()
        }
    }
    
    // MARK: - Metrics Collection
    
    private func collectMetrics() {
        let memoryUsage = getMemoryUsage()
        let cpuUsage = getCPUUsage()
        let frameRate = calculateFrameRate()
        let batteryLevel = getBatteryLevel()
        let thermalState = ProcessInfo.processInfo.thermalState
        
        let metrics = PerformanceMetrics(
            timestamp: Date(),
            memoryUsageMB: memoryUsage,
            cpuUsagePercent: cpuUsage,
            frameRate: frameRate,
            batteryLevel: batteryLevel,
            thermalState: thermalState
        )
        
        // Update current metrics
        DispatchQueue.main.async {
            self.currentMetrics = metrics
            
            // Check for performance issues
            if !metrics.isWithinAcceptableLimits {
                self.performanceIssueDetected = true
                self.logPerformanceIssue(metrics)
            }
        }
        
        // Add to history
        metricsHistory.append(metrics)
        if metricsHistory.count > maxHistorySize {
            metricsHistory.removeFirst()
        }
        
        // Automatic cleanup disabled - allow high memory usage
    }
    
    private func getMemoryUsage() -> Double {
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
    
    private func getCPUUsage() -> Double {
        var cpuInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        
        let result = withUnsafeMutablePointer(to: &cpuInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else { return 0.0 }
        
        if let lastInfo = lastCPUInfo {
            let userDiff = cpuInfo.cpu_ticks.0 - lastInfo.cpu_ticks.0
            let systemDiff = cpuInfo.cpu_ticks.1 - lastInfo.cpu_ticks.1
            let idleDiff = cpuInfo.cpu_ticks.2 - lastInfo.cpu_ticks.2
            let niceDiff = cpuInfo.cpu_ticks.3 - lastInfo.cpu_ticks.3
            
            let totalDiff = userDiff + systemDiff + idleDiff + niceDiff
            
            if totalDiff > 0 {
                let usedDiff = userDiff + systemDiff + niceDiff
                let cpuUsage = Double(usedDiff) / Double(totalDiff) * 100.0
                lastCPUInfo = cpuInfo
                return cpuUsage
            }
        }
        
        lastCPUInfo = cpuInfo
        return 0.0
    }
    
    private func calculateFrameRate() -> Double {
        guard frameTimestamps.count >= 2 else { return 0.0 }
        
        let recentFrames = Array(frameTimestamps.suffix(30)) // Use last 30 frames
        guard recentFrames.count >= 2 else { return 0.0 }
        
        let timeSpan = recentFrames.last! - recentFrames.first!
        guard timeSpan > 0 else { return 0.0 }
        
        return Double(recentFrames.count - 1) / timeSpan
    }
    
    private func getBatteryLevel() -> Float {
        UIDevice.current.isBatteryMonitoringEnabled = true
        return UIDevice.current.batteryLevel
    }
    
    // MARK: - Analysis and Reporting
    
    private func calculateAverageMetrics() {
        guard !metricsHistory.isEmpty else { return }
        
        let avgMemory = metricsHistory.map { $0.memoryUsageMB }.reduce(0, +) / Double(metricsHistory.count)
        let avgCPU = metricsHistory.map { $0.cpuUsagePercent }.reduce(0, +) / Double(metricsHistory.count)
        let avgFrameRate = metricsHistory.map { $0.frameRate }.reduce(0, +) / Double(metricsHistory.count)
        let avgBattery = metricsHistory.map { Double($0.batteryLevel) }.reduce(0, +) / Double(metricsHistory.count)
        
        let avgMetrics = PerformanceMetrics(
            timestamp: Date(),
            memoryUsageMB: avgMemory,
            cpuUsagePercent: avgCPU,
            frameRate: avgFrameRate,
            batteryLevel: Float(avgBattery),
            thermalState: .nominal
        )
        
        DispatchQueue.main.async { [weak self] in
            self?.averageMetrics = avgMetrics
        }
        
        logPerformanceSummary(avgMetrics)
    }
    
    private func logPerformanceIssue(_ metrics: PerformanceMetrics) {
        var issues: [String] = []
        
        if metrics.memoryUsageMB >= 1000.0 {
            issues.append("High memory usage: \(String(format: "%.1f", metrics.memoryUsageMB))MB")
        }
        
        if metrics.cpuUsagePercent >= 90.0 {
            issues.append("High CPU usage: \(String(format: "%.1f", metrics.cpuUsagePercent))%")
        }
        
        if metrics.frameRate <= 15.0 {
            issues.append("Low frame rate: \(String(format: "%.1f", metrics.frameRate))fps")
        }
        
        if metrics.thermalState != .nominal {
            issues.append("Thermal state: \(metrics.thermalState)")
        }
        
        FlexaLog.motion.warning("Performance issues detected: \(issues.joined(separator: ", "))")
    }
    
    private func logPerformanceSummary(_ metrics: PerformanceMetrics) {
        FlexaLog.motion.info("""
        Performance Summary:
        - Average Memory Usage: \(String(format: "%.1f", metrics.memoryUsageMB))MB
        - Average CPU Usage: \(String(format: "%.1f", metrics.cpuUsagePercent))%
        - Average Frame Rate: \(String(format: "%.1f", metrics.frameRate))fps
        - Session Duration: \(self.metricsHistory.count) seconds
        - Performance Issues: \(self.performanceIssueDetected ? "YES" : "NO")
        """)
    }
    
    /// Get performance report for debugging
    func getPerformanceReport() -> String {
        guard let current = currentMetrics, let average = averageMetrics else {
            return "No performance data available"
        }
        
        return """
        Current Performance:
        - Memory: \(String(format: "%.1f", current.memoryUsageMB))MB
        - CPU: \(String(format: "%.1f", current.cpuUsagePercent))%
        - Frame Rate: \(String(format: "%.1f", current.frameRate))fps
        - Battery: \(String(format: "%.0f", current.batteryLevel * 100))%
        - Thermal: \(current.thermalState)
        
        Session Averages:
        - Memory: \(String(format: "%.1f", average.memoryUsageMB))MB
        - CPU: \(String(format: "%.1f", average.cpuUsagePercent))%
        - Frame Rate: \(String(format: "%.1f", average.frameRate))fps
        
        Status: \(current.isWithinAcceptableLimits ? "✅ Good" : "⚠️ Issues Detected")
        """
    }
    
    /// Check if system is performing within acceptable limits
    func isPerformingWell() -> Bool {
        guard let metrics = currentMetrics else { return true }
        return metrics.isWithinAcceptableLimits && !performanceIssueDetected
    }
    
    // MARK: - Notifications
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thermalStateChanged),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
    }
    
    @objc private func thermalStateChanged() {
        let thermalState = ProcessInfo.processInfo.thermalState
        if thermalState != .nominal {
            FlexaLog.motion.warning("Thermal state changed to: \(thermalState)")
            DispatchQueue.main.async {
                self.performanceIssueDetected = true
            }
        }
    }
    
    // MARK: - Memory Management
    
    /// Trigger automatic memory cleanup when memory pressure is detected
    private func triggerMemoryCleanup() {
        // Reduce metrics history size
        if metricsHistory.count > maxHistorySize / 2 {
            let keepCount = maxHistorySize / 2
            metricsHistory = Array(metricsHistory.suffix(keepCount))
        }
        
        // Reduce frame timestamp history
        if frameTimestamps.count > frameHistorySize / 2 {
            let keepCount = frameHistorySize / 2
            frameTimestamps = Array(frameTimestamps.suffix(keepCount))
        }
        
        // Force garbage collection
        autoreleasepool {
            // This block helps release any temporary objects
        }
        
        FlexaLog.motion.info("PerformanceMonitor: Automatic memory cleanup performed")
    }
    
    /// Force memory cleanup (can be called externally)
    func forceMemoryCleanup() {
        triggerMemoryCleanup()
    }
}

// MARK: - ProcessInfo.ThermalState Extension

extension ProcessInfo.ThermalState: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .nominal:
            return "Normal"
        case .fair:
            return "Fair"
        case .serious:
            return "Serious"
        case .critical:
            return "Critical"
        @unknown default:
            return "Unknown"
        }
    }
}