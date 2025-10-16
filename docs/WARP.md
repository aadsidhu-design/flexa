# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Overview

FlexaSwiftUI is an iOS physical therapy and exercise application that uses dual tracking systems (camera-based pose detection and IMU motion sensors) for shoulder ROM exercises. The app provides gamified rehabilitation exercises with real-time feedback and motion analysis.

## Architecture

### Core Services Architecture

The application uses a service-oriented architecture with three main motion tracking systems:

1. **SimpleMotionService** - Central service that coordinates between camera and IMU tracking
2. **VisionPoseProvider** - Apple Vision-based pose detection for camera exercises  
3. **Universal3DROMEngine** - ARKit-based 3D ROM tracking for handheld exercises

### Dual Tracking System

The app implements two distinct tracking modes:

**Camera Games** (Balloon Pop, Wall Climbers, Constellation):
- Uses front-facing camera with Apple Vision body pose detection
- Tracks shoulder elevation, elbow flexion, and wrist movements
- Renders real-time skeleton overlay for user feedback
- Requires NSCameraUsageDescription permission

**Handheld Games** (Fruit Slicer, Fan the Flame, Witch Brew):
- Uses device motion sensors (CMMotionManager) and ARKit
- Tracks pendulum motion, circular movements, and 3D orientation
- Requires NSMotionUsageDescription permission
- Implements sophisticated motion smoothing and filtering

### Data Flow

1. **Motion Input** → Service Layer → Game Logic → UI Feedback
2. **Session Data** → SPARC Analysis → Firebase Storage → Progress Tracking
3. **Real-time Updates** → EMA Smoothing → ROM Calculations → Rep Detection

### Key Components

- **Navigation**: Tab-based with NavigationManager for game flow coordination
- **Games**: Protocol-based architecture with UnifiedGameProtocol for consistency
- **Storage**: Local JSON + Firebase Firestore with offline support
- **Analytics**: SPARC (movement smoothness) calculations and AI analysis via Gemini
- **Calibration**: ROM calibration wizard for personalized tracking

## Common Development Commands

### Building and Running

```bash
# Build project (uses Xcode build system)
xcodebuild -project FlexaSwiftUI.xcodeproj -scheme FlexaSwiftUI -destination 'platform=iOS Simulator,name=iPhone 15' build

# Build for device testing (motion sensors require physical device)
xcodebuild -project FlexaSwiftUI.xcodeproj -scheme FlexaSwiftUI -destination 'generic/platform=iOS' build

# Clean build
xcodebuild clean -project FlexaSwiftUI.xcodeproj -scheme FlexaSwiftUI
```

### Testing

```bash
# Run unit tests
xcodebuild test -project FlexaSwiftUI.xcodeproj -scheme FlexaSwiftUITests -destination 'platform=iOS Simulator,name=iPhone 15'

# Run UI tests
xcodebuild test -project FlexaSwiftUI.xcodeproj -scheme FlexaSwiftUIUITests -destination 'platform=iOS Simulator,name=iPhone 15'
```

### Asset Generation

```bash
# Generate app icons from source image
./generate_icons.sh [source_image_path]

# Generate app icons using Python script
python3 generate_app_icons.py
```

### Integration and Setup

```bash
# Run integration helper script
./integrate_rebuild.sh

# This script:
# - Creates backups of existing files
# - Checks dependencies (Firebase)
# - Validates Info.plist permissions
# - Generates integration mapping and test checklists
```

### Debugging and Analysis

```bash
# View build logs
tail -f xcodebuild.log

# Check Firebase configuration
# Validate GoogleService-Info.plist is present and configured

# Performance profiling (use Xcode Instruments)
# - Time Profiler for CPU usage analysis
# - Allocations for memory leak detection
# - Energy Log for battery impact assessment
```

## Development Workflow

### Motion Sensor Development

Always test motion-dependent features on physical devices. The simulator cannot provide realistic motion data for:
- IMU tracking (handheld games)
- Camera pose detection requires physical camera
- ARKit world tracking needs real environment

### Game Development Pattern

1. Implement UnifiedGameProtocol in new game views
2. Use StandardGameWrapper for consistent game lifecycle
3. Configure motion tracking mode in SimpleMotionService
4. Add navigation routes in NavigationManager
5. Test with test_checklist.md validation steps

### Performance Optimization

The codebase has identified performance bottlenecks documented in PERFORMANCE_OPTIMIZATION_GUIDE.md:

- **Critical**: Timer management leaks across 11+ game files
- **Critical**: Unbounded array growth in motion services
- **High**: Multiple CMMotionManager instances
- **High**: AVCaptureSession resource management issues

Priority fixes:
1. Replace Timer usage with Combine publishers
2. Implement circular buffers for motion data arrays
3. Consolidate to single shared CMMotionManager
4. Add proper camera session lifecycle management

### Firebase Integration

The app uses Firebase for:
- Anonymous authentication
- Session data storage in Firestore
- Analytics and performance monitoring

Configuration requires:
- GoogleService-Info.plist in project bundle
- Firebase SDK dependencies in project.pbxproj
- Secure API key management via KeychainManager

### Motion Tracking Calibration

The app implements a sophisticated calibration system:

- **ARKit + IMU Fusion**: Primary tracking mode using world tracking + device motion
- **Orientation Mapping**: Persisted calibration at 0°/90°/180° positions
- **Segment Length Estimation**: Upper arm and forearm measurements for accurate ROM
- **Grip Offset Compensation**: Accounts for phone-to-forearm alignment variations

Calibration data persists across app launches and room changes via UserDefaults.

## Key File Locations

### Core Services
- `FlexaSwiftUI/Services/SimpleMotionService.swift` - Main motion coordination
- `FlexaSwiftUI/Services/VisionPoseProvider.swift` - Apple Vision integration
- `FlexaSwiftUI/Services/Universal3DROMEngine.swift` - ARKit ROM tracking
- `FlexaSwiftUI/Services/SPARCCalculationService.swift` - Movement smoothness analysis

### Game Infrastructure
- `FlexaSwiftUI/Games/UnifiedGameProtocol.swift` - Game standardization protocol
- `FlexaSwiftUI/Games/StandardGameWrapper.swift` - Common game wrapper
- `FlexaSwiftUI/Navigation/NavigationManager.swift` - Game flow coordination

### Configuration
- `FlexaSwiftUI/Config/SecureConfig.swift` - API key management
- `FlexaSwiftUI/Security/KeychainManager.swift` - Secure storage
- `Config/Info.plist` - App permissions and configuration

### Main App
- `FlexaSwiftUI/FlexaSwiftUIApp.swift` - App entry point with service injection
- `FlexaSwiftUI/ContentView.swift` - Main tab navigation interface

## Testing Approach

Use the provided test checklist (test_checklist.md) for validation:

- **Handheld Games**: Test ARKit tracking, pendulum motion, circular movements
- **Camera Games**: Validate pose detection, skeleton overlay, rep counting
- **Navigation Flow**: Verify Results → Survey → Home routing
- **Data Persistence**: Check local JSON storage and Firebase sync
- **Performance**: Monitor 60fps gameplay and memory usage

Always test performance optimization fixes with Xcode Instruments, particularly:
- Memory usage during extended gameplay sessions
- CPU usage with multiple simultaneous motion updates  
- Battery impact during intensive ARKit + camera operations

## Security Notes

The app implements secure credential management:
- API keys stored in Keychain, not plaintext
- Firebase configuration validated on startup
- Anonymous authentication for user sessions
- Local data encryption for sensitive health information

Never commit API keys, Firebase config files, or authentication tokens to version control.
