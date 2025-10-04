# Requirements Document

## Introduction

This feature involves a comprehensive cleanup and optimization of the ROM (Range of Motion) calculation system in the FlexaSwiftUI app. The current system has conflicting calculation methods, performance issues, and unnecessary complexity that needs to be resolved to ensure accurate, efficient motion tracking.

## Requirements

### Requirement 1: ROM Calculation Method Standardization

**User Story:** As a physical therapy patient, I want consistent and accurate ROM measurements so that my progress tracking is reliable and meaningful.

#### Acceptance Criteria

1. WHEN the app calculates ROM THEN it SHALL use only ARKit OR Vision-based methods, not IMU
2. WHEN multiple ROM calculation methods exist THEN the system SHALL remove all IMU-based ROM calculations
3. WHEN ROM is calculated THEN it SHALL use either distance-based OR path-based tracking, not both
4. WHEN ARKit is available THEN the system SHALL prefer ARKit 3D positioning over Vision 2D tracking
5. IF ARKit is unavailable THEN the system SHALL fall back to Vision-based ROM calculation

### Requirement 2: Threading and Performance Optimization

**User Story:** As a user performing exercises, I want the app to respond smoothly without lag or crashes so that my exercise experience is seamless.

#### Acceptance Criteria

1. WHEN ROM calculations are performed THEN they SHALL be executed on appropriate background threads
2. WHEN UI updates occur THEN they SHALL be dispatched to the main thread properly
3. WHEN timers are used THEN they SHALL be properly invalidated to prevent memory leaks
4. WHEN the app processes motion data THEN it SHALL not block the main thread
5. WHEN arrays are used for data storage THEN they SHALL have proper bounds checking to prevent crashes

### Requirement 3: Dead Code Removal

**User Story:** As a developer maintaining the codebase, I want clean, maintainable code so that future development is efficient and bug-free.

#### Acceptance Criteria

1. WHEN the codebase is analyzed THEN all unused ROM calculation methods SHALL be removed
2. WHEN services are reviewed THEN all redundant calculation logic SHALL be eliminated
3. WHEN motion tracking code is examined THEN all obsolete IMU fallback code SHALL be removed
4. WHEN the Universal3DROMEngine is updated THEN conflicting calculation approaches SHALL be consolidated
5. WHEN SimpleMotionService is cleaned THEN duplicate ROM tracking logic SHALL be removed

### Requirement 4: 3D to 2D Projection Simplification

**User Story:** As a user with various device orientations, I want accurate motion tracking regardless of how I hold my device so that exercise measurements remain consistent.

#### Acceptance Criteria

1. WHEN 3D positions are projected to 2D THEN the projection algorithm SHALL be simplified for better performance
2. WHEN movement plane detection occurs THEN it SHALL use efficient variance-based calculation
3. WHEN coordinate transformations happen THEN they SHALL minimize computational overhead
4. WHEN projection calculations run THEN they SHALL not perform redundant mathematical operations
5. WHEN the system detects dominant movement planes THEN it SHALL cache results to avoid recalculation

### Requirement 5: Memory Management and Array Bounds

**User Story:** As a user performing long exercise sessions, I want the app to remain stable and not crash due to memory issues so that my session data is preserved.

#### Acceptance Criteria

1. WHEN motion data arrays grow THEN they SHALL have maximum size limits to prevent unbounded growth
2. WHEN historical data is stored THEN old entries SHALL be automatically removed when limits are reached
3. WHEN array access occurs THEN bounds checking SHALL prevent index out of range errors
4. WHEN memory usage increases THEN the system SHALL implement proper cleanup mechanisms
5. WHEN data buffers are full THEN the system SHALL use circular buffer patterns or similar efficient storage

### Requirement 6: Timer and Resource Leak Prevention

**User Story:** As a user who starts and stops exercise sessions multiple times, I want the app to properly clean up resources so that performance doesn't degrade over time.

#### Acceptance Criteria

1. WHEN exercise sessions end THEN all active timers SHALL be properly invalidated
2. WHEN ARKit sessions stop THEN the ARSession SHALL be properly paused and cleaned up
3. WHEN motion tracking stops THEN CoreMotion updates SHALL be properly stopped
4. WHEN camera sessions end THEN AVCaptureSession SHALL be properly stopped and released
5. WHEN services are deinitialized THEN all observers and delegates SHALL be properly removed

### Requirement 7: Calculation Method Consistency

**User Story:** As a healthcare provider reviewing patient data, I want consistent ROM calculation methods so that progress comparisons are meaningful across sessions.

#### Acceptance Criteria

1. WHEN ROM is calculated for handheld games THEN it SHALL use only ARKit 3D positioning
2. WHEN ROM is calculated for camera games THEN it SHALL use only Vision pose detection
3. WHEN the system switches between calculation methods THEN it SHALL maintain consistent units and scales
4. WHEN ROM values are reported THEN they SHALL use the same mathematical approach within each exercise type
5. WHEN calibration data is applied THEN it SHALL be used consistently across all ROM calculations