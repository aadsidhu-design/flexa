# Design Document

## Overview

This design outlines a comprehensive cleanup and optimization of the ROM (Range of Motion) calculation system in FlexaSwiftUI. The current system suffers from conflicting calculation methods, performance bottlenecks, and unnecessary complexity. The reformed system will provide consistent, efficient, and accurate motion tracking using a unified approach.

## Architecture

### Current System Issues

1. **Conflicting ROM Methods**: Both distance-based and arc-length calculations exist simultaneously
2. **IMU Dependency**: Unnecessary IMU fallbacks when ARKit/Vision should be primary
3. **Threading Problems**: ROM calculations blocking main thread and improper async handling
4. **Memory Leaks**: Unbounded arrays and timer leaks during session transitions
5. **Dead Code**: Redundant calculation paths and obsolete IMU-based ROM logic

### Reformed Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    SimpleMotionService                      │
│  ┌─────────────────┐    ┌─────────────────────────────────┐ │
│  │  Game Type      │    │     ROM Calculation Router      │ │
│  │  Detection      │    │                                 │ │
│  └─────────────────┘    └─────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                                    │
                    ┌───────────────┼───────────────┐
                    │               │               │
        ┌───────────▼──────────┐   │   ┌──────────▼──────────┐
        │   Camera Games       │   │   │   Handheld Games    │
        │  (Vision-based)      │   │   │   (ARKit-based)     │
        │                      │   │   │                     │
        │ ┌─────────────────┐  │   │   │ ┌─────────────────┐ │
        │ │ VisionPoseProvider│ │   │   │ │Universal3DROMEngine│ │
        │ │                 │  │   │   │ │                 │ │
        │ │ • Pose Detection│  │   │   │ │ • ARKit 3D      │ │
        │ │ • 2D ROM Calc   │  │   │   │ │ • Path Tracking │ │
        │ │ • Skeleton Lines│  │   │   │ │ • Thread-safe   │ │
        │ └─────────────────┘  │   │   │ └─────────────────┘ │
        └──────────────────────┘   │   └─────────────────────┘
                                   │
                    ┌──────────────▼──────────────┐
                    │      SPARCCalculationService │
                    │                             │
                    │ • Background Processing     │
                    │ • Bounded Data Buffers      │
                    │ • Memory Management         │
                    └─────────────────────────────┘
```

## Components and Interfaces

### 1. SimpleMotionService (Coordinator)

**Responsibilities:**
- Route ROM calculations based on game type
- Manage session lifecycle and cleanup
- Coordinate between ARKit and Vision providers
- Handle threading and main thread updates

**Key Changes:**
- Remove all IMU-based ROM calculation fallbacks
- Implement proper timer invalidation
- Add bounded array management
- Separate camera and handheld game logic paths

### 2. Universal3DROMEngine (ARKit Provider)

**Responsibilities:**
- Pure ARKit 3D position tracking
- Movement path-based ROM calculation
- Thread-safe operation
- Automatic 3D-to-2D projection

**Key Changes:**
- Remove conflicting calculation methods (keep only path tracking)
- Simplify 3D-to-2D projection algorithm
- Implement proper background threading
- Add memory bounds for position history
- Remove IMU fallback code

### 3. VisionPoseProvider (Camera Provider)

**Responsibilities:**
- Computer vision pose detection
- 2D ROM calculation from pose landmarks
- Skeleton line generation
- Camera game support

**Key Changes:**
- Optimize pose processing pipeline
- Implement efficient skeleton generation
- Add proper error handling for missing landmarks
- Remove redundant calculation methods

### 4. SPARCCalculationService (Smoothness Analysis)

**Responsibilities:**
- Movement smoothness calculation
- Background data processing
- Memory-efficient data storage
- Multi-source data integration

**Key Changes:**
- Implement circular buffer patterns
- Add proper threading for FFT calculations
- Remove redundant SPARC calculation methods
- Add memory pressure handling

## Data Models

### ROM Calculation Flow

```swift
// Unified ROM calculation interface
protocol ROMCalculator {
    func calculateROM(from data: MotionData) -> Double
    func reset()
    func cleanup()
}

// Motion data structure
struct MotionData {
    let timestamp: TimeInterval
    let source: MotionSource
    let position: SIMD3<Double>?
    let keypoints: SimplifiedPoseKeypoints?
}

enum MotionSource {
    case arkit
    case vision
}
```

### Memory Management

```swift
// Bounded data structures
class BoundedArray<T> {
    private var items: [T] = []
    private let maxSize: Int
    
    init(maxSize: Int) {
        self.maxSize = maxSize
    }
    
    func append(_ item: T) {
        items.append(item)
        if items.count > maxSize {
            items.removeFirst(items.count - maxSize)
        }
    }
}
```

## Error Handling

### Threading Safety

1. **Background Processing**: All ROM calculations performed on background queues
2. **Main Thread Updates**: UI updates dispatched to main thread with proper error handling
3. **Resource Cleanup**: Automatic cleanup on session end or app backgrounding

### Memory Management

1. **Bounded Arrays**: All data arrays have maximum size limits
2. **Circular Buffers**: Efficient memory usage for continuous data streams
3. **Timer Cleanup**: Proper invalidation of all timers and observers

### Error Recovery

1. **Graceful Degradation**: Fallback to basic ROM when advanced methods fail
2. **Session Recovery**: Automatic session restart on critical errors
3. **Resource Monitoring**: Memory pressure detection and cleanup

## Testing Strategy

### Unit Tests

1. **ROM Calculation Accuracy**: Test path-based ROM tracking against known movement patterns
2. **Threading Safety**: Concurrent access tests for shared data structures
3. **Memory Bounds**: Verify array bounds and memory cleanup
4. **Timer Management**: Test proper timer invalidation

### Integration Tests

1. **ARKit Integration**: Test 3D position tracking and ROM calculation
2. **Vision Integration**: Test pose detection and 2D ROM calculation
3. **Session Lifecycle**: Test proper cleanup during session transitions
4. **Game Type Routing**: Verify correct ROM provider selection

### Performance Tests

1. **Memory Usage**: Monitor memory growth during long sessions
2. **CPU Usage**: Verify background processing doesn't impact UI
3. **Battery Impact**: Test power consumption of optimized system
4. **Frame Rate**: Ensure smooth UI during intensive calculations

## Implementation Plan

### Phase 1: Core Cleanup
- Remove IMU-based ROM calculations
- Consolidate conflicting calculation methods
- Implement proper threading architecture

### Phase 2: Memory Optimization
- Add bounded arrays and circular buffers
- Implement proper timer cleanup
- Add memory pressure handling

### Phase 3: Performance Optimization
- Simplify 3D-to-2D projection
- Optimize Vision processing pipeline
- Add background processing for SPARC

### Phase 4: Testing and Validation
- Comprehensive unit test coverage
- Performance benchmarking
- Memory leak detection
- User acceptance testing

## Migration Strategy

### Backward Compatibility
- Maintain existing public APIs during transition
- Gradual migration of game types to new system
- Fallback mechanisms for edge cases

### Data Migration
- Preserve existing calibration data
- Convert old ROM history to new format
- Maintain session data compatibility

### Rollback Plan
- Feature flags for new ROM system
- Ability to revert to old system if issues arise
- Comprehensive logging for debugging