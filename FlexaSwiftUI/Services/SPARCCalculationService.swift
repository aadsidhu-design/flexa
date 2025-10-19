import Foundation
import Accelerate
import CoreMotion
import simd

// MARK: - SPARC Calculation Service
class SPARCCalculationService: ObservableObject, @unchecked Sendable {
    
    // MARK: - Movement Data Structure
    struct MovementSample {
        let timestamp: TimeInterval
        let acceleration: SIMD3<Float>
        let velocity: SIMD3<Float>?
        let position: CGPoint?
    }
    
    struct PositionData {
        let timestamp: TimeInterval
        let position: SIMD3<Float>
    }
    
    struct SPARCResult {
        let smoothness: Double
        let arcLength: Double
        let frequency: Double
        let confidence: Double
    }
    
    // MARK: - Properties
    @Published var currentSPARC: Double = 0.0
    @Published var averageSPARC: Double = 0.0
    @Published var isConnected = false
    @Published var connectionError: String?
    
    // Error handling and resource monitoring
    private var errorHandler: ROMErrorHandler?
    private var processingQueue = DispatchQueue(label: "com.flexa.sparc.processing", qos: .userInitiated)
    private var fftQueue = DispatchQueue(label: "com.flexa.sparc.fft", qos: .background)
    private var calculationFailures: Int = 0
    private let maxCalculationFailures = 5
    
    // Circular buffers - restored to larger sizes for better accuracy
    private let movementSamples = BoundedArray<MovementSample>(maxSize: 1000) // Restored
    private let cameraMovementSamples = BoundedArray<MovementSample>(maxSize: 600)
    private let positionBuffer = BoundedArray<PositionData>(maxSize: 500) // Restored
    private let arcLengthHistory = BoundedArray<Double>(maxSize: 500) // Restored
    private let sparcHistory = BoundedArray<Double>(maxSize: 200) // Increased for better averaging
    
    // REAL TIME-BASED SPARC DATA for proper graphing
    private let sparcDataPoints = BoundedArray<SPARCDataPoint>(maxSize: 200) // Real timestamps
    private var sessionStartTime: Date = Date() // Track session start for relative timestamps
    
    // Memory management constants - relaxed for better performance
    private let maxSamples = 1000
    private let maxBufferSize = 500
    private let memoryPressureThreshold: Double = 1000.0 // Removed memory restrictions - allow high usage
    private let samplingRate: Double = 100.0 // Restored full sampling rate
    private let transmissionInterval: TimeInterval = 1.0 // Restored original interval
    private var lastTransmissionTime = Date()
    private var lastMemoryCheck = Date()
    private let memoryCheckInterval: TimeInterval = 2.0 // Check every 2 seconds (more frequent)
    
    // SPARC publish throttle: enforce a more responsive cadence
    private let sparcPublishInterval: TimeInterval = 0.05
    private var lastSPARCUpdateTime: Date = .distantPast
    // Smoothing for published SPARC values (0..1) - lower alpha to track changes faster
    private var sparcSmoothingAlpha: Double = 0.5
    private var lastSmoothedSPARC: Double = 50.0
    // Low-pass filter state for accelerometer magnitude (for handheld smoothing)
    private var accelLPFLast: Float = 0.0
    private let accelLPFAlpha: Float = 0.12 // gentle smoothing for accel magnitude
    // Smoothness weighting for spectral vs. consistency metrics
    private let spectralWeight: Double = 0.65
    private let consistencyReference: Double = 0.85
    private let cameraSamplingRate: Double = 30.0
    private var lastCameraPosition: SIMD3<Float>?
    private var lastCameraVelocity: SIMD3<Float>?
    private var lastCameraTimestamp: TimeInterval?
    
    init() {
        reset()
        setupMemoryNotifications()
    }
    
    deinit {
        // Remove notification observers
        NotificationCenter.default.removeObserver(self)
        
        // Clear all data arrays and reset state with proper deallocation
        movementSamples.removeAllAndDeallocate()
        positionBuffer.removeAllAndDeallocate()
        arcLengthHistory.removeAllAndDeallocate()
        sparcHistory.removeAllAndDeallocate()
        FlexaLog.motion.info("SPARCCalculationService deinitializing and cleaning up resources")
    }
    
    /// Set error handler for recovery support
    func setErrorHandler(_ handler: ROMErrorHandler) {
        self.errorHandler = handler
    }
    
    // MARK: - Vision Data Input (for camera games)
    func addVisionMovement(timestamp: TimeInterval, position: CGPoint, velocity: SIMD3<Float>? = nil) {
        addVisionData(timestamp: timestamp, handPosition: position, velocity: velocity ?? SIMD3<Float>(0, 0, 0))
    }
    
    func addVisionData(timestamp: TimeInterval, handPosition: CGPoint, velocity: SIMD3<Float>) {
        // Calculate velocity from position changes for more accurate SPARC
        let estimatedVelocity = estimateVelocityFromPosition(handPosition, timestamp: timestamp)
        
        let sample = MovementSample(
            timestamp: timestamp,
            acceleration: SIMD3<Float>(0, 0, 0),
            velocity: estimatedVelocity,
            position: handPosition
        )
        
        cameraMovementSamples.append(sample)
        movementSamples.append(sample)

        if cameraMovementSamples.count >= 15 {
            calculateVisionSPARC()
        }
    }
    
    // MARK: - IMU Data Input
    func addIMUData(timestamp: TimeInterval, acceleration: [Double], velocity: [Double]?) {
        // Bounds checking for input arrays
        guard acceleration.count >= 3 else {
            FlexaLog.motion.error("Invalid acceleration data: insufficient components")
            return
        }
        
        // Apply high-pass filter to remove gravity and low-frequency noise
        let accel = SIMD3<Float>(Float(acceleration[0]), Float(acceleration[1]), Float(acceleration[2]))
        let filteredAccel = applyHighPassFilter(accel)
        
        // Estimate velocity from acceleration if not provided
        let vel = velocity != nil && velocity!.count >= 3 ? 
            SIMD3<Float>(Float(velocity![0]), Float(velocity![1]), Float(velocity![2])) : 
            estimateVelocityFromAccel(filteredAccel, timestamp: timestamp)
        
        let sample = MovementSample(
            timestamp: timestamp,
            acceleration: filteredAccel,
            velocity: vel,
            position: nil
        )
        
        movementSamples.append(sample)
        
        // Calculate SPARC more frequently for real-time smoothness tracking
        if movementSamples.count >= 30 { // Reduced threshold for more responsive calculations
            calculateIMUSPARC()
        }
    }
    
    // MARK: - ARKit Position Data Input (for handheld games)
    func addARKitPositionData(timestamp: TimeInterval, position: SIMD3<Float>) {
        // Store position data for trajectory-based SPARC calculation
        // Sanitize position and timestamp before storing
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite, timestamp.isFinite else {
            FlexaLog.motion.warning("⚠️ [SPARC] Ignoring invalid ARKit position or timestamp")
            return
        }
        let posData = PositionData(timestamp: timestamp, position: position)
        positionBuffer.append(posData)
        
        // Calculate arc length for ROM tracking
        if positionBuffer.count >= 2 {
            let arcLength = calculateARKitArcLength()
            if arcLengthHistory.count < maxBufferSize {
                arcLengthHistory.append(arcLength)
            }
        }
        
        calculateARKitSPARC()
    }
    
    func reset() {
        movementSamples.removeAllAndDeallocate()
        positionBuffer.removeAllAndDeallocate()
        arcLengthHistory.removeAllAndDeallocate()
        sparcHistory.removeAllAndDeallocate()
        sparcDataPoints.removeAllAndDeallocate() // Clear real time-based data
        currentSPARC = 0.0
        averageSPARC = 0.0
        calculationFailures = 0
        lastMemoryCheck = Date()
        lastSPARCUpdateTime = .distantPast
        sessionStartTime = Date() // Reset session start time for accurate graphing
        FlexaLog.motion.info(" [SPARC] Reset complete - session start time initialized")
    }
    
    func getCurrentSPARC() -> Double {
        return currentSPARC
    }
    
    func getAverageSPARC() -> Double {
        return averageSPARC
    }
    
    // Get real time-based SPARC data for proper graphing
    func getSPARCDataPoints() -> [SPARCDataPoint] {
        return sparcDataPoints.allElements
    }
    
    /// Get the session start time for accurate relative timestamp calculations in charts
    func getSessionStartTime() -> Date {
        return sessionStartTime
    }
    
    // MARK: - General Movement Data Input
    func addMovement(timestamp: TimeInterval, acceleration: SIMD3<Float>, velocity: SIMD3<Float>) {
        let sample = MovementSample(
            timestamp: timestamp,
            acceleration: acceleration,
            velocity: velocity,
            position: nil
        )
        movementSamples.append(sample)

        if movementSamples.count >= 30 {
            calculateIMUSPARC()
        }
    }

    // MARK: - IMU-based SPARC Calculation
    private func calculateIMUSPARC() {
        processingQueue.async { [weak self] in
            guard let self else { return }

            let samples = self.movementSamples.allElements
            guard samples.count >= 10 else { return }

            let velocityMagnitudes = samples.compactMap { sample -> Float? in
                guard let v = sample.velocity else { return nil }
                return simd_length(v)
            }

            let accelerationMagnitudes = samples.map { sample -> Float in
                simd_length(sample.acceleration)
            }

            guard !velocityMagnitudes.isEmpty || accelerationMagnitudes.count >= 10 else { return }

            let signal = velocityMagnitudes.isEmpty ? accelerationMagnitudes : velocityMagnitudes

            self.fftQueue.async {
                autoreleasepool {
                    do {
                        let result = try self.computeSPARCWithErrorHandling(signal: signal, samplingRate: self.samplingRate)
                        let now = Date()
                        if now.timeIntervalSince(self.lastSPARCUpdateTime) >= self.sparcPublishInterval {
                            let spectral = max(0.0, min(100.0, result.smoothness))
                            let consistency = self.calculateConsistencyScore(from: velocityMagnitudes.isEmpty ? accelerationMagnitudes : velocityMagnitudes, reference: self.consistencyReference)
                            let blended = self.blendSmoothnessComponents(spectral: spectral, consistency: consistency)
                            let smoothed = self.applyPublishingSmoothing(value: blended)
                            self.publishSPARC(value: smoothed, timestamp: now, dataSource: .imu, confidence: result.confidence)
                        }
                    } catch {
                        self.handleSPARCCalculationError(error)
                    }
                }
            }
        }
    }

    // MARK: - Vision-based SPARC Calculation
    private func calculateVisionSPARC() {
        processingQueue.async { [weak self] in
            guard let self else { return }

            let samples = self.cameraMovementSamples.allElements
            guard samples.count >= 10 else { return }

            let velocityMagnitudes = samples.compactMap { sample -> Float? in
                guard let velocity = sample.velocity else { return nil }
                return simd_length(velocity)
            }

            guard velocityMagnitudes.count >= 10 else { return }

            let mean = velocityMagnitudes.reduce(0, +) / Float(velocityMagnitudes.count)
            let detrendedSignal = velocityMagnitudes.map { abs($0 - mean) }

            self.fftQueue.async {
                autoreleasepool {
                    do {
                        let result = try self.computeSPARCWithErrorHandling(signal: detrendedSignal, samplingRate: self.cameraSamplingRate)
                        let now = Date()
                        if now.timeIntervalSince(self.lastSPARCUpdateTime) >= self.sparcPublishInterval {
                            let spectral = max(0.0, min(100.0, result.smoothness))
                            let consistency = self.calculateConsistencyScore(from: velocityMagnitudes, reference: self.consistencyReference)
                            let blended = self.blendSmoothnessComponents(spectral: spectral, consistency: consistency)
                            let smoothed = self.applyPublishingSmoothing(value: blended)
                            self.publishSPARC(value: smoothed, timestamp: now, dataSource: .vision, confidence: result.confidence)
                        }
                    } catch {
                        self.handleSPARCCalculationError(error)
                    }
                }
            }
        }
    }

    // MARK: - ARKit-based SPARC Calculation (for handheld games)
    private func calculateARKitSPARC() {
        processingQueue.async { [weak self] in
            guard let self else { return }

            let positions = self.positionBuffer.allElements
            guard positions.count >= 10 else { return }

            // Calculate velocity from position changes for smoothness analysis
            var velocityMagnitudes: [Float] = []
            for i in 1..<positions.count {
                let prev = positions[i-1]
                let curr = positions[i]
                let dt = Float(curr.timestamp - prev.timestamp)
                guard dt > 0 else { continue }
                
                let displacement = curr.position - prev.position
                let velocity = simd_length(displacement) / dt
                velocityMagnitudes.append(velocity)
            }

            guard velocityMagnitudes.count >= 10 else { return }

            // Detrend the signal to focus on movement quality
            let mean = velocityMagnitudes.reduce(0, +) / Float(velocityMagnitudes.count)
            let detrendedSignal = velocityMagnitudes.map { abs($0 - mean) }

            self.fftQueue.async {
                autoreleasepool {
                    do {
                        // Use 60Hz sampling rate for ARKit (typical ARKit update rate)
                        let result = try self.computeSPARCWithErrorHandling(signal: detrendedSignal, samplingRate: 60.0)
                        let now = Date()
                        if now.timeIntervalSince(self.lastSPARCUpdateTime) >= self.sparcPublishInterval {
                            let spectral = max(0.0, min(100.0, result.smoothness))
                            let consistency = self.calculateConsistencyScore(from: velocityMagnitudes, reference: self.consistencyReference)
                            let blended = self.blendSmoothnessComponents(spectral: spectral, consistency: consistency)
                            let smoothed = self.applyPublishingSmoothing(value: blended)
                            self.publishSPARC(value: smoothed, timestamp: now, dataSource: .arkit, confidence: result.confidence)
                        }
                    } catch {
                        self.handleSPARCCalculationError(error)
                    }
                }
            }
        }
    }

    // MARK: - Camera Movement Input
    func addCameraMovement(position: SIMD3<Float>, timestamp: TimeInterval) {
        let velocity = estimateCameraVelocity(position: position, timestamp: timestamp)
        let sample = MovementSample(
            timestamp: timestamp,
            acceleration: SIMD3<Float>(0, 0, 0),
            velocity: velocity,
            position: CGPoint(x: CGFloat(position.x), y: CGFloat(position.y))
        )
        cameraMovementSamples.append(sample)
        movementSamples.append(sample)

        if cameraMovementSamples.count >= 15 {
            calculateVisionSPARC()
        }
    }

    // MARK: - SPARC Computation Core
    private func computeSPARC(signal: [Float], samplingRate: Double) -> SPARCResult {
        guard signal.count > 1 else {
            return SPARCResult(smoothness: 5.0, arcLength: 0.0, frequency: 0.0, confidence: 0.0)
        }
        
        // Use full signal for accurate SPARC calculation
        let paddedSignal = signal
        
        // Ensure signal length is power of 2 for optimal FFT performance
        let n = nextPowerOfTwo(paddedSignal.count)
        var processedSignal = paddedSignal
        
        // Pad with zeros if necessary
        if processedSignal.count < n {
            processedSignal.append(contentsOf: Array(repeating: 0.0, count: n - processedSignal.count))
        }
        
        var realInput = processedSignal
        var imaginaryInput = Array(repeating: Float(0.0), count: n)
        
        return realInput.withUnsafeMutableBufferPointer { realPtr in
            return imaginaryInput.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
        
                let log2n = vDSP_Length(log2(Float(n)))
                guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
                    return SPARCResult(smoothness: 50.0, arcLength: 0.0, frequency: 0.0, confidence: 0.0)
                }
                
                // Perform FFT
                vDSP_fft_zip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
                
                // Calculate magnitudes
                var magnitudes = Array(repeating: Float(0.0), count: n)
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(n))
                
                // Calculate frequency domain metrics
                let nyquistFreq = samplingRate / 2.0
                let freqResolution = nyquistFreq / Double(n / 2)
                
                var totalPower: Float = 0.0
                vDSP_sve(magnitudes, 1, &totalPower, vDSP_Length(n))
                
                // Improved smoothness calculation based on spectral centroid
                let smoothness = calculateSpectralSmoothness(magnitudes: magnitudes, totalPower: totalPower)
                let dominantFreqIndex = magnitudes.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
                let dominantFreq = Double(dominantFreqIndex) * freqResolution
                
                // Calculate confidence based on signal quality
                let confidence = calculateSignalConfidence(magnitudes: magnitudes, totalPower: totalPower)
                
                vDSP_destroy_fftsetup(fftSetup)
                
                return SPARCResult(
                    smoothness: smoothness,
                    arcLength: calculateVisionArcLength(),
                    frequency: dominantFreq,
                    confidence: confidence
                )
            }
        }
    }
    
    // MARK: - Helper Methods for SPARC Calculation
    
    private func nextPowerOfTwo(_ n: Int) -> Int {
        guard n > 1 else { return 2 }
        return 1 << (Int(log2(Double(n - 1))) + 1)
    }
    
    private func calculateSpectralSmoothness(magnitudes: [Float], totalPower: Float) -> Double {
        guard totalPower > 0 && magnitudes.count > 4 else { return 50.0 }

        let halfCount = magnitudes.count / 2
        let usableMagnitudes = Array(magnitudes[..<halfCount])
        var spectralArcLength: Float = 0.0

        for i in 1..<usableMagnitudes.count {
            let freq1 = Float(i - 1)
            let freq2 = Float(i)
            let mag1 = usableMagnitudes[i - 1] / totalPower
            let mag2 = usableMagnitudes[i] / totalPower

            let deltaFreq = freq2 - freq1
            let deltaMag = mag2 - mag1

            spectralArcLength += sqrt(deltaFreq * deltaFreq + deltaMag * deltaMag)
        }

        let normalizedArcLength = Double(spectralArcLength) / Double(max(1, usableMagnitudes.count))
        return max(0.0, min(100.0, 100.0 * (1.0 - normalizedArcLength)))
    }

    private func calculateConsistencyScore(from magnitudes: [Float], reference: Double) -> Double {
        guard magnitudes.count >= 5 else { return 100.0 }
        let mean = Double(magnitudes.reduce(0, +)) / Double(magnitudes.count)
        guard mean > 0 else { return 100.0 }
        let variance = magnitudes.reduce(0.0) { partial, value in
            let delta = Double(value) - mean
            return partial + delta * delta
        } / Double(magnitudes.count)
        let coefficient = sqrt(variance) / mean
        let normalized = max(0.0, 1.0 - min(coefficient / reference, 1.0))
        return normalized * 100.0
    }

    private func blendSmoothnessComponents(spectral: Double, consistency: Double) -> Double {
        let clampedConsistency = max(0.0, min(100.0, consistency))
        return spectralWeight * spectral + (1.0 - spectralWeight) * clampedConsistency
    }

    private func applyPublishingSmoothing(value: Double) -> Double {
        let smoothed = (sparcSmoothingAlpha * value) + ((1.0 - sparcSmoothingAlpha) * lastSmoothedSPARC)
        lastSmoothedSPARC = smoothed
        return smoothed
    }

    private func publishSPARC(value: Double, timestamp: Date, dataSource: SPARCDataSource, confidence: Double) {
        // Sanitize value
        var sanitized = value
        if sanitized.isNaN || sanitized.isInfinite {
            FlexaLog.motion.warning("⚠️ [SPARC] Computed SPARC was invalid (NaN/Inf). Falling back to 50.0")
            sanitized = 50.0
        }
        let clamped = max(0.0, min(100.0, sanitized))
        if clamped != sanitized {
            FlexaLog.motion.warning("⚠️ [SPARC] SPARC value \(sanitized) clamped to \(clamped)")
        }
        currentSPARC = clamped
        lastSPARCUpdateTime = timestamp
        calculationFailures = 0

        recordSPARCValue(value)

        let normalizedConfidence = max(0.0, min(confidence, 1.0))
        let dataPoint = SPARCDataPoint(
            timestamp: timestamp,
            sparcValue: value,
            movementPhase: "steady",
            jointAngles: [:],
            confidence: normalizedConfidence,
            dataSource: dataSource
        )
        sparcDataPoints.append(dataPoint)

        // Extra safety: if SPARC spikes unexpectedly, log recent arc lengths to aid diagnosis
        if clamped > 95.0 || clamped < 5.0 {
                FlexaLog.motion.debug("🔎 [SPARC] Unusual SPARC value: \(clamped). Recent arcLengths count=\(self.arcLengthHistory.count)")
        }
    }

    private func recordSPARCValue(_ value: Double) {
        sparcHistory.append(value)
        let recent = sparcHistory.suffix(50)
        if !recent.isEmpty {
            averageSPARC = recent.reduce(0, +) / Double(recent.count)
        }
    }

    private func estimateCameraVelocity(position: SIMD3<Float>, timestamp: TimeInterval) -> SIMD3<Float> {
        defer {
            lastCameraPosition = position
            lastCameraTimestamp = timestamp
        }

        guard let previousPosition = lastCameraPosition, let previousTimestamp = lastCameraTimestamp else {
            lastCameraVelocity = SIMD3<Float>(repeating: 0)
            return SIMD3<Float>(repeating: 0)
        }

        let dt = Float(timestamp - previousTimestamp)
        guard dt > 0 else { return lastCameraVelocity ?? SIMD3<Float>(repeating: 0) }

        let velocity = (position - previousPosition) / dt
        lastCameraVelocity = velocity
        return velocity
    }
    
    private func calculateSignalConfidence(magnitudes: [Float], totalPower: Float) -> Double {
        guard totalPower > 0 && !magnitudes.isEmpty else { return 0.0 }
        
        // Calculate signal-to-noise ratio as confidence metric
        let maxMagnitude = magnitudes.max() ?? 0.0
        let averageMagnitude = totalPower / Float(magnitudes.count)
        
        guard averageMagnitude > 0 else { return 0.0 }
        
        let snr = maxMagnitude / averageMagnitude
        return min(1.0, Double(snr) / 10.0) // Normalize to 0-1 range
    }
    
    func endSession() -> SPARCResult {
        guard !movementSamples.isEmpty else {
            return SPARCResult(smoothness: 50.0, arcLength: 0.0, frequency: 0.0, confidence: 0.0)
        }
        
        // For end session, we need synchronous calculation
        let velocityMagnitudes = movementSamples.compactMap { sample -> Float? in
            guard let velocity = sample.velocity else { return nil }
            return simd_length(velocity)
        }
        
        guard !velocityMagnitudes.isEmpty else {
            return SPARCResult(smoothness: 50.0, arcLength: 0.0, frequency: 0.0, confidence: 0.0)
        }
        
        let mean = velocityMagnitudes.reduce(0, +) / Float(velocityMagnitudes.count)
        let detrendedSignal = velocityMagnitudes.map { abs($0 - mean) }
        
        // Use error handling version for final calculation
        do {
            let result = try computeSPARCWithErrorHandling(signal: detrendedSignal, samplingRate: samplingRate)
            
            // Perform final cleanup after session ends
            performMemoryCleanup()
            
            return result
        } catch {
            FlexaLog.motion.error("Failed to compute final SPARC: \(error.localizedDescription)")
            return SPARCResult(smoothness: 50.0, arcLength: 0.0, frequency: 0.0, confidence: 0.0)
        }
    }
    
    func getSessionSummary() -> (averageSPARC: Double, peakSPARC: Double, sampleCount: Int) {
        return (averageSPARC, currentSPARC, movementSamples.count)
    }
    

    
    // MARK: - Arc Length Calculations
    private func calculateARKitArcLength() -> Double {
        guard positionBuffer.count >= 2 else { return 0.0 }
        
        let positions = positionBuffer.allElements
        var totalLength = 0.0
        for i in 1..<positions.count {
            let prev = positions[i-1].position
            let curr = positions[i].position
            let distance = simd_length(curr - prev)
            totalLength += Double(distance)
        }
        
        return totalLength
    }
    
    private func calculateVisionArcLength() -> Double {
        guard movementSamples.count >= 2 else { return 0.0 }
        
        let samples = movementSamples.allElements
        var totalLength = 0.0
        for i in 1..<samples.count {
            let prev = samples[i-1]
            let curr = samples[i]
            let dt = curr.timestamp - prev.timestamp
            
            if let velocity = curr.velocity {
                let displacement = simd_length(velocity) * Float(dt)
                totalLength += Double(displacement)
            }
        }
        
        return totalLength
    }
    
    // MARK: - Error Handling
    
    private func computeSPARCWithErrorHandling(signal: [Float], samplingRate: Double) throws -> SPARCResult {
        guard signal.count > 1 else {
            throw NSError(domain: "SPARCCalculationService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Insufficient signal data"])
        }
        
        // Memory check removed - allow SPARC calculations to proceed
        
        return computeSPARC(signal: signal, samplingRate: samplingRate)
    }

    // Public convenience helper so other modules can call the canonical SPARC implementation
    // without needing to instantiate the full service and wiring. This method delegates
    // to the internal computeSPARCWithErrorHandling implementation and returns the raw result.
    static func computeSPARCStandalone(signal: [Float], samplingRate: Double) throws -> SPARCResult {
        let service = SPARCCalculationService()
        // Use the instance method to leverage existing validation/error handling
        return try service.computeSPARCWithErrorHandling(signal: signal, samplingRate: samplingRate)
    }
    
    private func handleSPARCCalculationError(_ error: Error) {
        calculationFailures += 1
        
        FlexaLog.motion.error("SPARC calculation failed: \(error.localizedDescription)")
        
        if calculationFailures >= maxCalculationFailures {
            errorHandler?.handleError(.resourceExhaustion)
        }
        
        // Provide fallback SPARC value
        DispatchQueue.main.async {
            self.currentSPARC = 50.0 // Default moderate smoothness (0-100 scale)
        }
    }
    
    // MARK: - Memory Management and Cleanup
    
    // Memory pressure checking removed - allow unlimited memory usage for accurate calculations
    
    private func performMemoryCleanup() {
        // Much more aggressive cleanup - keep only 1/4 of data
        if movementSamples.count > maxSamples / 4 {
            let keepCount = maxSamples / 4
            let allSamples = movementSamples.allElements
            movementSamples.removeAllAndDeallocate()
            
            // Keep only the most recent samples
            let recentSamples = Array(allSamples.suffix(keepCount))
            for sample in recentSamples {
                movementSamples.append(sample)
            }
        }
        
        if positionBuffer.count > maxBufferSize / 4 {
            let keepCount = maxBufferSize / 4
            let allPositions = positionBuffer.allElements
            positionBuffer.removeAllAndDeallocate()
            
            // Keep only the most recent positions
            let recentPositions = Array(allPositions.suffix(keepCount))
            for position in recentPositions {
                positionBuffer.append(position)
            }
        }
        
        // Clean up history arrays more aggressively
        if arcLengthHistory.count > maxBufferSize / 4 {
            let keepCount = maxBufferSize / 4
            let allLengths = arcLengthHistory.allElements
            arcLengthHistory.removeAllAndDeallocate()
            
            let recentLengths = Array(allLengths.suffix(keepCount))
            for length in recentLengths {
                arcLengthHistory.append(length)
            }
        }
        
        if sparcHistory.count > 25 {
            let keepCount = 10
            let allSparc = sparcHistory.allElements
            sparcHistory.removeAllAndDeallocate()
            
            let recentSparc = Array(allSparc.suffix(keepCount))
            for sparc in recentSparc {
                sparcHistory.append(sparc)
            }
        }
        
        // Force garbage collection
        autoreleasepool {
            // This block helps release temporary objects
        }
        
        FlexaLog.motion.info("Aggressive memory cleanup completed - buffers significantly reduced")
    }
    
    func forceMemoryCleanup() {
        performMemoryCleanup()
    }
    
    // MARK: - Memory Notifications
    
    private func setupMemoryNotifications() {
        // Listen for memory pressure notifications
        NotificationCenter.default.addObserver(
            forName: .memoryPressureDetected,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.performMemoryCleanup()
        }
        
        NotificationCenter.default.addObserver(
            forName: .memoryWarningDetected,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.performMemoryCleanup()
        }
    }
    
    // MARK: - Signal Processing Helper Methods
    
    private var lastAcceleration: SIMD3<Float>?
    private var lastVelocity: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    private var lastPosition: CGPoint?
    private var lastTimestamp: TimeInterval = 0
    private let highPassAlpha: Float = 0.8 // High-pass filter coefficient
    
    /// Apply high-pass filter to remove gravity and low-frequency components
    private func applyHighPassFilter(_ acceleration: SIMD3<Float>) -> SIMD3<Float> {
        defer { lastAcceleration = acceleration }
        
        guard let lastAccel = lastAcceleration else {
            return acceleration
        }
        
        // High-pass filter: output = alpha * (output + input - lastInput)
        let filteredAccel = highPassAlpha * (lastVelocity + acceleration - lastAccel)
        lastVelocity = filteredAccel
        
        return filteredAccel
    }
    
    /// Estimate velocity from filtered acceleration using numerical integration
    private func estimateVelocityFromAccel(_ acceleration: SIMD3<Float>, timestamp: TimeInterval) -> SIMD3<Float> {
        let dt = Float(timestamp - lastTimestamp)
        lastTimestamp = timestamp
        
        guard dt > 0 && dt < 1.0 else { // Sanity check for reasonable time delta
            return lastVelocity
        }
        
        // Numerical integration: v = v0 + a*dt
        lastVelocity = lastVelocity + acceleration * dt
        
        // Apply velocity damping to prevent drift
        lastVelocity *= 0.98
        
        return lastVelocity
    }
    
    /// Estimate velocity from position changes for vision-based SPARC
    private func estimateVelocityFromPosition(_ position: CGPoint, timestamp: TimeInterval) -> SIMD3<Float> {
        defer { 
            lastPosition = position
            lastTimestamp = timestamp
        }
        
        guard let lastPos = lastPosition else {
            return SIMD3<Float>(0, 0, 0)
        }
        
        let dt = Float(timestamp - lastTimestamp)
        guard dt > 0 && dt < 1.0 else {
            return SIMD3<Float>(0, 0, 0)
        }
        
        // Calculate velocity from position change
        let deltaX = Float(position.x - lastPos.x) / dt
        let deltaY = Float(position.y - lastPos.y) / dt
        
        return SIMD3<Float>(deltaX, deltaY, 0)
    }
    
    // MARK: - Connection Status
    func checkConnectionStatus() {
        DispatchQueue.main.async {
            self.isConnected = true
            self.connectionError = nil
        }
    }
}
