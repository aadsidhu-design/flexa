import Foundation

/// Simple memory testing utility to verify memory optimizations
final class MemoryTest {
    
    /// Test memory usage before and after SPARC calculations
    static func testSPARCMemoryUsage() {
        let memoryManager = MemoryManager.shared
        let sparcService = SPARCCalculationService()
        
        let initialMemory = memoryManager.getCurrentMemoryUsage()
        FlexaLog.motion.info("🧪 Memory Test - Initial: \(String(format: "%.1f", initialMemory))MB")
        
        // Simulate intensive SPARC calculations
        for i in 0..<100 {
            let timestamp = Double(i) * 0.1
            let acceleration = SIMD3<Float>(
                Float.random(in: -1...1),
                Float.random(in: -1...1),
                Float.random(in: -1...1)
            )
            let velocity = SIMD3<Float>(
                Float.random(in: -0.5...0.5),
                Float.random(in: -0.5...0.5),
                Float.random(in: -0.5...0.5)
            )
            
            sparcService.addMovement(timestamp: timestamp, acceleration: acceleration, velocity: velocity)
        }
        
        let peakMemory = memoryManager.getCurrentMemoryUsage()
        FlexaLog.motion.info("🧪 Memory Test - Peak: \(String(format: "%.1f", peakMemory))MB")
        
        // Force cleanup
        sparcService.forceMemoryCleanup()
        
        // Wait a moment for cleanup to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let finalMemory = memoryManager.getCurrentMemoryUsage()
            FlexaLog.motion.info("🧪 Memory Test - Final: \(String(format: "%.1f", finalMemory))MB")
            
            let memoryIncrease = peakMemory - initialMemory
            let memoryRecovered = peakMemory - finalMemory
            
            FlexaLog.motion.info("🧪 Memory Test Results:")
            FlexaLog.motion.info("  - Memory increase: \(String(format: "%.1f", memoryIncrease))MB")
            FlexaLog.motion.info("  - Memory recovered: \(String(format: "%.1f", memoryRecovered))MB")
            FlexaLog.motion.info("  - Recovery rate: \(String(format: "%.1f", (memoryRecovered / memoryIncrease) * 100))%")
            
            if memoryIncrease < 50.0 {
                FlexaLog.motion.info("✅ Memory test PASSED - Low memory usage")
            } else if memoryRecovered > memoryIncrease * 0.7 {
                FlexaLog.motion.info("✅ Memory test PASSED - Good recovery rate")
            } else {
                FlexaLog.motion.warning("⚠️ Memory test FAILED - High memory usage or poor recovery")
            }
        }
    }
    
    /// Test memory pressure detection and cleanup
    static func testMemoryPressureHandling() {
        let memoryManager = MemoryManager.shared
        
        FlexaLog.motion.info("🧪 Testing memory pressure detection...")
        
        if memoryManager.isUnderMemoryPressure() {
            FlexaLog.motion.info("✅ Memory pressure correctly detected")
            memoryManager.performEmergencyCleanup()
        } else {
            FlexaLog.motion.info("ℹ️ No memory pressure detected - system is healthy")
        }
    }
}