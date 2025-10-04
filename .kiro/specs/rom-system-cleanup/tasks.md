# Implementation Plan

- [x] 1. Remove IMU-based ROM calculations from SimpleMotionService
  - Remove all IMU fallback ROM calculation methods
  - Clean up romTrackingMode enum to remove IMU options
  - Remove setROMTrackingMode IMU handling code
  - _Requirements: 1.1, 1.2, 3.1, 3.3_

- [x] 2. Consolidate ROM calculation methods in Universal3DROMEngine
  - Remove conflicting distance-based and arc-length ROM calculations
  - Keep only path-based 3D position tracking for ROM
  - Remove calculateDistanceBasedROM method
  - Remove arc-length tracking variables and logic
  - _Requirements: 1.3, 1.4, 3.2, 7.1_

- [x] 3. Implement proper threading architecture
  - Move ROM calculations to background threads in Universal3DROMEngine
  - Add proper DispatchQueue.main.async for UI updates
  - Implement thread-safe access to shared ROM data
  - Add proper synchronization for currentROM and maxROM properties
  - _Requirements: 2.1, 2.2, 2.4_

- [x] 4. Add bounded arrays and memory management
  - Replace unbounded arrays with BoundedArray class
  - Implement circular buffer for romHistory, positionHistory, movementHistory
  - Add maxSize limits to prevent memory growth
  - Implement automatic cleanup when arrays reach capacity
  - _Requirements: 5.1, 5.2, 5.3, 5.4_

- [x] 5. Fix timer and resource leaks
  - Add proper timer invalidation in SimpleMotionService.stopSession()
  - Implement proper ARSession cleanup in Universal3DROMEngine.stop()
  - Add CoreMotion updates cleanup in stopSession()
  - Remove observers and delegates properly in deinit methods
  - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5_

- [x] 6. Simplify 3D-to-2D projection in Universal3DROMEngine
  - Optimize detectDominantMovementPlane() method
  - Cache movement plane detection results to avoid recalculation
  - Simplify projectToMovementPlane() algorithm
  - Remove redundant mathematical operations in projection
  - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_

- [x] 7. Remove dead code from motion services
  - Remove unused ROM calculation methods from SimpleMotionService
  - Clean up obsolete IMU fallback code in Universal3DROMEngine
  - Remove redundant SPARC calculation methods from SPARCCalculationService
  - Delete unused motion tracking variables and properties
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_

- [x] 8. Optimize SPARCCalculationService threading and memory
  - Implement background processing for FFT calculations in computeSPARC()
  - Add circular buffer pattern for movementSamples and positionBuffer
  - Implement proper bounds checking for all data arrays
  - Add memory pressure handling and cleanup mechanisms
  - _Requirements: 2.3, 5.1, 5.2, 5.5_

- [x] 9. Standardize ROM calculation consistency
  - Ensure handheld games use only ARKit 3D positioning
  - Ensure camera games use only Vision pose detection
  - Remove mixed calculation approaches within game types
  - Implement consistent units and scales across all ROM calculations
  - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5_

- [x] 10. Add comprehensive error handling and recovery
  - Implement graceful degradation when ARKit/Vision fails
  - Add session recovery mechanisms for critical errors
  - Implement proper error logging for debugging
  - Add resource monitoring and automatic cleanup
  - _Requirements: 2.1, 2.2, 5.4, 6.5_

- [x] 11. Performance optimization and validation
  - Benchmark memory usage during long exercise sessions
  - Verify CPU usage stays within acceptable limits
  - Test UI responsiveness during intensive ROM calculations
  - Validate battery impact of optimized system
  - _Requirements: 2.4, 4.3, 5.1, 5.4_