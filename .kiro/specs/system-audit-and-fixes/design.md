# Design Document

## Overview

This design outlines a comprehensive audit and fix strategy for critical systems in FlexaSwiftUI including AI scoring, SPARC smoothness calculations, custom exercise robustness, circle ROM accuracy, metrics integrity, and Appwrite data upload reliability. The goal is to ensure production-level quality across all systems.

## Architecture

### System Audit Approach

```
┌─────────────────────────────────────────────────────────────┐
│                    System Audit Framework                   │
│  ┌─────────────────┐    ┌─────────────────────────────────┐ │
│  │  Data Validation│    │     Integrity Verification      │ │
│  │     Pipeline    │    │         Pipeline               │ │
│  └─────────────────┘    └─────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        │                           │                           │
┌───────▼──────────┐    ┌──────────▼──────────┐    ┌─────────▼─────────┐
│   AI Scoring     │    │   SPARC Smoothness  │    │  Custom Exercise  │
│   Audit System   │    │   Audit System      │    │   Audit System    │
│                  │    │                     │    │                   │
│ • Score Accuracy │    │ • Calculation Fix   │    │ • Rep Detection   │
│ • Algorithm Val. │    │ • Graph Rendering   │    │ • Config Robust.  │
│ • Fallback Logic │    │ • Data Collection   │    │ • Edge Case Hand. │
└──────────────────┘    └─────────────────────┘    └───────────────────┘
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        │                           │                           │
┌───────▼──────────┐    ┌──────────▼──────────┐    ┌─────────▼─────────┐
│   Circle ROM     │    │   Metrics Collection│    │  Firebase Upload  │
│   Audit System   │    │   Audit System      │    │   Audit System    │
│                  │    │                     │    │                   │
│ • 360° Tracking  │    │ • Calculation Val.  │    │ • Data Integrity  │
│ • Circular Logic │    │ • Storage Integrity │    │ • Upload Verify   │
│ • Calibration    │    │ • Real-time Updates │    │ • Error Recovery  │
└──────────────────┘    └─────────────────────┘    └───────────────────┘
```

## Components and Interfaces

### 1. AI Scoring Audit System

**Current Issues to Investigate:**
- Placeholder or hardcoded scores instead of real calculations
- Incorrect algorithm implementation
- Missing validation of score ranges
- Lack of correlation with actual exercise quality

**Audit Strategy:**
- Trace AI scoring pipeline from motion data to final score
- Validate mathematical correctness of scoring algorithms
- Implement score validation and bounds checking
- Add logging for score calculation steps

**Key Components:**
```swift
protocol AIScoreValidator {
    func validateScore(_ score: Double, for exercise: ExerciseType) -> Bool
    func auditScoreCalculation(motionData: [MotionDataPoint]) -> ScoreAuditResult
}

struct ScoreAuditResult {
    let isValid: Bool
    let calculatedScore: Double
    let issues: [ScoreIssue]
    let recommendations: [String]
}
```

### 2. SPARC Smoothness Audit System

**Current Issues to Investigate:**
- Incorrect FFT implementation in SPARCCalculationService
- Missing or corrupted data points in smoothness graphs
- Improper time series data handling
- Threading issues affecting calculation accuracy

**Audit Strategy:**
- Verify FFT algorithm implementation against SPARC specification
- Audit data collection pipeline for smoothness calculations
- Fix graph rendering to display accurate smoothness trends
- Implement proper error handling for missing data points

**Key Components:**
```swift
protocol SPARCValidator {
    func validateSPARCCalculation(velocityData: [Double]) -> SPARCAuditResult
    func auditGraphData(smoothnessHistory: [SPARCDataPoint]) -> GraphAuditResult
}

struct SPARCAuditResult {
    let isValid: Bool
    let calculatedSPARC: Double
    let fftResults: [Double]
    let issues: [SPARCIssue]
}
```

### 3. Custom Exercise Audit System

**Current Issues to Investigate:**
- Incomplete rep counting for custom movement patterns
- Missing validation for custom exercise configurations
- Edge cases causing crashes or incorrect behavior
- Inconsistent behavior between custom and built-in exercises

**Audit Strategy:**
- Test custom exercise creation with various movement patterns
- Validate rep counting accuracy across different exercise types
- Implement robust error handling for edge cases
- Ensure feature parity with built-in exercises

**Key Components:**
```swift
protocol CustomExerciseValidator {
    func validateExerciseConfig(_ config: CustomExerciseConfig) -> ValidationResult
    func auditRepCounting(motionData: [MotionDataPoint], config: CustomExerciseConfig) -> RepCountAuditResult
}

struct CustomExerciseConfig {
    let movementPattern: MovementPattern
    let repDetectionThreshold: Double
    let romRequirements: ROMRequirements
    let validationRules: [ValidationRule]
}
```

### 4. Circle ROM Audit System

**Current Issues to Investigate:**
- Incorrect calculation of circular range of motion
- Missing handling of 360-degree movements
- Improper projection of 3D circular motion to 2D
- Calibration issues for circular exercises

**Audit Strategy:**
- Verify circular ROM calculation algorithms
- Test with known circular movement patterns
- Implement proper 360-degree range handling
- Fix calibration for circular exercises

**Key Components:**
```swift
protocol CircleROMValidator {
    func validateCircularROM(positions: [SIMD3<Double>]) -> CircleROMAuditResult
    func auditCircularCalibration(calibrationData: CalibrationData) -> CalibrationAuditResult
}

struct CircleROMAuditResult {
    let isValid: Bool
    let calculatedRange: Double
    let circularityScore: Double
    let issues: [CircleROMIssue]
}
```

### 5. Metrics Collection Audit System

**Current Issues to Investigate:**
- Missing or incorrect metric calculations
- Data loss during collection and storage
- Inconsistent metric updates during exercise sessions
- Improper aggregation of session data

**Audit Strategy:**
- Trace metric collection pipeline from sensors to storage
- Validate all mathematical calculations used in metrics
- Implement data integrity checks throughout the pipeline
- Add comprehensive logging for metric collection

**Key Components:**
```swift
protocol MetricsValidator {
    func validateMetricCalculation(_ metric: ExerciseMetric, rawData: [MotionDataPoint]) -> MetricAuditResult
    func auditDataIntegrity(sessionData: ExerciseSessionData) -> DataIntegrityResult
}

struct MetricAuditResult {
    let isValid: Bool
    let recalculatedValue: Double
    let dataQuality: DataQualityScore
    let issues: [MetricIssue]
}
```

### 6. Firebase Upload Audit System

**Current Issues to Investigate:**
- Fake or placeholder data being uploaded instead of real metrics
- Missing data fields in uploaded session documents
- Upload failures not being handled properly
- Data corruption during serialization/upload process

**Audit Strategy:**
- Audit all data before upload to ensure authenticity
- Implement comprehensive upload verification
- Add retry mechanisms with proper error handling
- Validate data integrity after successful uploads

**Key Components:**
```swift
protocol UploadValidator {
    func validateUploadData(_ data: ExerciseSessionData) -> UploadValidationResult
    func auditUploadIntegrity(localData: ExerciseSessionData, uploadedData: [String: Any]) -> UploadAuditResult
}

struct UploadValidationResult {
    let isValid: Bool
    let hasRealData: Bool
    let missingFields: [String]
    let dataQualityIssues: [DataQualityIssue]
}
```

## Data Models

### Audit Framework Models

```swift
// Comprehensive audit result
struct SystemAuditResult {
    let aiScoringAudit: AIScoreAuditResult
    let sparcAudit: SPARCAuditResult
    let customExerciseAudit: CustomExerciseAuditResult
    let circleROMAudit: CircleROMAuditResult
    let metricsAudit: MetricsAuditResult
    let uploadAudit: UploadAuditResult
    let overallHealthScore: Double
}

// Issue tracking
enum SystemIssue {
    case aiScoringInaccuracy(details: String)
    case sparcCalculationError(details: String)
    case customExerciseFailure(details: String)
    case circleROMError(details: String)
    case metricsCorruption(details: String)
    case uploadDataLoss(details: String)
}

// Data quality assessment
struct DataQualityScore {
    let accuracy: Double        // 0.0 - 1.0
    let completeness: Double    // 0.0 - 1.0
    let consistency: Double     // 0.0 - 1.0
    let timeliness: Double      // 0.0 - 1.0
    let overall: Double         // Weighted average
}
```

## Error Handling

### Audit Error Recovery

1. **Graceful Degradation**: When audit systems detect issues, provide fallback mechanisms
2. **Issue Isolation**: Prevent issues in one system from affecting others
3. **Automatic Correction**: Implement self-healing mechanisms where possible
4. **Comprehensive Logging**: Log all audit findings for debugging and improvement

### Data Validation Pipeline

1. **Input Validation**: Validate all sensor data before processing
2. **Calculation Verification**: Cross-check calculations with known good algorithms
3. **Output Validation**: Ensure all results are within expected ranges
4. **Storage Integrity**: Verify data integrity before and after storage operations

## Testing Strategy

### Audit Testing Approach

1. **Known Good Data**: Test with pre-recorded sessions with known correct results
2. **Edge Case Testing**: Test with extreme values and unusual movement patterns
3. **Regression Testing**: Ensure fixes don't break existing functionality
4. **Performance Testing**: Verify audit systems don't impact app performance

### Validation Testing

1. **Cross-Platform Validation**: Test on different iOS devices and versions
2. **Long Session Testing**: Test with extended exercise sessions
3. **Network Failure Testing**: Test upload reliability under poor network conditions
4. **Memory Pressure Testing**: Test system behavior under low memory conditions

## Implementation Plan

### Phase 1: Audit Infrastructure
- Implement audit framework and validation interfaces
- Add comprehensive logging throughout all systems
- Create test data sets with known correct results

### Phase 2: System-Specific Audits
- Audit and fix AI scoring system
- Fix SPARC calculation and graphing issues
- Enhance custom exercise robustness
- Correct circle ROM calculations

### Phase 3: Data Integrity
- Audit metrics collection and calculation pipeline
- Fix Firebase upload data integrity issues
- Implement upload verification and retry mechanisms

### Phase 4: Production Hardening
- Add comprehensive error handling and recovery
- Implement monitoring and alerting for system health
- Performance optimization and memory management

## Migration Strategy

### Backward Compatibility
- Maintain existing APIs during audit and fix process
- Gradual rollout of fixes with feature flags
- Preserve existing user data and session history

### Data Migration
- Validate and potentially recalculate historical data
- Implement data repair mechanisms for corrupted records
- Ensure seamless transition to improved systems

### Rollback Plan
- Feature flags for all system improvements
- Ability to revert to previous implementations if issues arise
- Comprehensive monitoring to detect regressions quickly