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
    private let sparcPublishInterval: TimeInterval = 0.25
    private var lastSPARCUpdateTime: Date = .distantPast
    // Smoothing for published SPARC values (0..1) - lower alpha to track changes faster
    private var sparcSmoothingAlpha: Double = 0.15
    private var lastSmoothedSPARC: Double = 50.0
    // Low-pass filter state for accelerometer magnitude (for handheld smoothing)
    private var accelLPFLast: Float = 0.0
    private let accelLPFAlpha: Float = 0.12 // gentle smoothing for accel magnitude
    // Blend weight between spectral SPARC and accel-derived smoothness (0..1)
    private let accelBlendWeight: Double = 0.45
    
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
            acceleration: SIMD3<Float>(0, 0, 0), // Acceleration not directly available from vision
            velocity: estimatedVelocity,
            position: handPosition
        )
        
        movementSamples.append(sample)
        
        // Calculate SPARC more frequently for real-time vision-based smoothness
        if movementSamples.count >= 20 { // Lower threshold for vision data
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
    
    // MARK: - ARKit Position Data Input (for ROM games)
    func addARKitPositionData(timestamp: TimeInterval, position: SIMD3<Float>) {
        // Allow unlimited position data for accurate calculations
        
        let posData = PositionData(timestamp: timestamp, position: position)
        positionBuffer.append(posData)
        
        if positionBuffer.count >= 2 {
            let arcLength = calculateARKitArcLength()
            if arcLengthHistory.count < maxBufferSize {
                arcLengthHistory.append(arcLength)
            }
        }
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
        FlexaLog.motion.info("📊 [SPARC] Reset complete - session start time initialized")
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
        // Allow unlimited movement data for accurate calculations
        
        let sample = MovementSample(
            timestamp: timestamp,
            acceleration: acceleration,
            velocity: velocity,
            position: nil
        )
        
        movementSamples.append(sample)
        
        // Calculate SPARC with proper threshold for accuracy
        if movementSamples.count >= 30 {
            calculateIMUSPARC()
        }
    }
    
    // MARK: - IMU-based SPARC Calculation
    private func calculateIMUSPARC() {
        guard movementSamples.count >= 10 else { return }
        
        // Perform initial processing on processing queue
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Prefer velocity magnitudes for handheld IMU-based SPARC (gives better movement content)
            // Prepare signals: velocity magnitudes preferred, otherwise accel magnitudes
            let velocityMagnitudes = self.movementSamples.compactMap { sample -> Float? in
                guard let v = sample.velocity else { return nil }
                return simd_length(v)
            }

            let accelerationMagnitudes = self.movementSamples.map { sample -> Float in
                return simd_length(sample.acceleration)
            }

            // Compute accel magnitude low-pass filtered series for accel-based smoothness
            var accelLPFSeries: [Float] = []
            var last: Float = self.accelLPFLast
            for a in accelerationMagnitudes {
                last = (self.accelLPFAlpha * a) + ((1.0 - self.accelLPFAlpha) * last)
                accelLPFSeries.append(last)
            }
            // Update state
            if let lastVal = accelLPFSeries.last { self.accelLPFLast = lastVal }

            // Velocity-based signal preferred for spectral SPARC
            let signalToUse: [Float] = velocityMagnitudes.count >= 10 ? velocityMagnitudes : accelerationMagnitudes

            // Perform FFT computation on dedicated background queue
            self.fftQueue.async {
                autoreleasepool {
                    do {
                        // Use configured sampling rate for correct frequency axis
                        let result = try self.computeSPARCWithErrorHandling(signal: signalToUse, samplingRate: self.samplingRate)
                        
                        // Throttle publish to 0.5s cadence
                        let now = Date()
                        if now.timeIntervalSince(self.lastSPARCUpdateTime) >= self.sparcPublishInterval {
                            self.lastSPARCUpdateTime = now
                            DispatchQueue.main.async {
                                // Normalize spectral smoothness to 0..100
                                let spectral = max(0.0, min(100.0, result.smoothness))

                                // Compute simple accel-derived smoothness metric: lower variance -> smoother
                                let accelVar: Float
                                if accelLPFSeries.count > 1 {
                                    let mean = accelLPFSeries.reduce(0, +) / Float(accelLPFSeries.count)
                                    var sumSq: Float = 0
                                    for v in accelLPFSeries { sumSq += (v - mean) * (v - mean) }
                                    accelVar = sumSq / Float(accelLPFSeries.count)
                                } else { accelVar = 0.0 }
                                // Map variance to a 0..100 smoothness (heuristic): lower variance -> higher smoothness
                                let accelSmoothness = Double(max(0.0, min(1.0, 1.0 - Double(accelVar) * 50.0))) * 100.0

                                // Blend spectral and accel-based smoothness
                                let blended = (self.accelBlendWeight * accelSmoothness) + ((1.0 - self.accelBlendWeight) * spectral)

                                // Apply smoothing to the blended value
                                let smoothed = (self.sparcSmoothingAlpha * blended) + ((1.0 - self.sparcSmoothingAlpha) * self.lastSmoothedSPARC)
                                self.lastSmoothedSPARC = smoothed
                                self.currentSPARC = smoothed
                                self.updateAverageSPARC()
                                // Store SPARC data point with REAL timestamp for proper graphing
                                let timeFromStart = now.timeIntervalSince(self.sessionStartTime)
                                let dataPoint = SPARCDataPoint(
                                    timestamp: now,
                                    sparcValue: smoothed,
                                    movementPhase: "steady",
                                    jointAngles: [:]
                                )
                                self.sparcDataPoints.append(dataPoint)
                                self.calculationFailures = 0 // Reset on success
                            }
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
        guard movementSamples.count >= 10 else { return }
        
        // Perform initial processing on processing queue
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            let velocityMagnitudes = self.movementSamples.compactMap { sample -> Float? in
                guard let velocity = sample.velocity else { return nil }
                return simd_length(velocity)
            }
            
            guard velocityMagnitudes.count >= 10 else { return }
            
            let mean = velocityMagnitudes.reduce(0, +) / Float(velocityMagnitudes.count)
            let detrendedSignal = velocityMagnitudes.map { abs($0 - mean) }
            
            // Perform FFT computation on dedicated background queue
            self.fftQueue.async {
                autoreleasepool {
                    do {
                        let result = try self.computeSPARCWithErrorHandling(signal: detrendedSignal, samplingRate: 30.0)
                        
                        // Throttle publish to 0.5s cadence
                        let now = Date()
                        if now.timeIntervalSince(self.lastSPARCUpdateTime) >= self.sparcPublishInterval {
                            self.lastSPARCUpdateTime = now
                            DispatchQueue.main.async {
                                // Normalize to 0-100 and smooth for stable graphs
                                let normalized = max(0.0, min(100.0, result.smoothness))
                                let smoothed = (self.sparcSmoothingAlpha * normalized) + ((1.0 - self.sparcSmoothingAlpha) * self.lastSmoothedSPARC)
                                self.lastSmoothedSPARC = smoothed
                                self.currentSPARC = smoothed
                                self.updateAverageSPARC()

                                // Store SPARC data point with REAL timestamp for proper graphing
                                let dataPoint = SPARCDataPoint(
                                    timestamp: now,
                                    sparcValue: smoothed,
                                    movementPhase: "steady",
                                    jointAngles: [:]
                                )
                                self.sparcDataPoints.append(dataPoint)

                                self.calculationFailures = 0 // Reset on success
                            }
                        }
                    } catch {
                        self.handleSPARCCalculationError(error)
                    }
                }
            }
        }
    }
    
    private func updateAverageSPARC() {
        // Add current SPARC to history with REAL timestamp for proper time-based graphing
        sparcHistory.append(currentSPARC)
        
        // Calculate average from recent SPARC values
        let recentValues = sparcHistory.suffix(50) // Use last 50 SPARC calculations
        if !recentValues.isEmpty {
            averageSPARC = recentValues.reduce(0, +) / Double(recentValues.count)
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
        guard totalPower > 0 && magnitudes.count > 4 else { return 5.0 }
        
        // Enhanced SPARC calculation using spectral arc length
        let N = magnitudes.count / 2 // Use only positive frequencies
        let usableMagnitudes = Array(magnitudes[0..<N])
        
        // Calculate spectral arc length (key SPARC metric)
        var spectralArcLength: Float = 0.0
        var spectralCentroid: Float = 0.0
        var spectralSpread: Float = 0.0
        
        // Calculate spectral centroid
        for (index, magnitude) in usableMagnitudes.enumerated() {
            spectralCentroid += Float(index) * magnitude
        }
        spectralCentroid /= totalPower
        
        // Calculate spectral spread (variance around centroid)
        for (index, magnitude) in usableMagnitudes.enumerated() {
            let deviation = Float(index) - spectralCentroid
            spectralSpread += deviation * deviation * magnitude
        }
        spectralSpread = sqrt(spectralSpread / totalPower)
        
        // Calculate arc length in frequency domain
        for i in 1..<usableMagnitudes.count {
            let freq1 = Float(i-1)
            let freq2 = Float(i)
            let mag1 = usableMagnitudes[i-1] / totalPower
            let mag2 = usableMagnitudes[i] / totalPower
            
            let deltaFreq = freq2 - freq1
            let deltaMag = mag2 - mag1
            
            spectralArcLength += sqrt(deltaFreq * deltaFreq + deltaMag * deltaMag)
        }
        
        // Convert to SPARC score (0-100 scale, higher = smoother)
        // Lower arc length = smoother movement
        let normalizedArcLength = Double(spectralArcLength) / Double(N)
        let sparcScore = max(0.0, min(100.0, 100.0 * (1.0 - normalizedArcLength)))
        
        return sparcScore
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
