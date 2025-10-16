# Technology Stack

## Platform & Build System
- **Platform**: iOS (minimum deployment target: iOS 16.0)
- **Build System**: Xcode project with Swift Package Manager dependencies
- **Language**: Swift 5.0
- **UI Framework**: SwiftUI with dark mode preference
- **Architecture**: MVVM with ObservableObject services and environment injection

## Core Frameworks & Libraries
- **ARKit**: 3D motion tracking, world tracking, and body tracking
- **Vision**: Pose estimation and computer vision analysis
- **CoreMotion**: IMU sensor data (accelerometer, gyroscope)
- **AVFoundation**: Camera capture and video processing
- **Firebase**: Authentication (anonymous), document database, and analytics
 Firebase (self-hosted or cloud) used for runtime uploads and document storage
 └── Firebase SDK / REST API - Backend document database and auth
 **BackendService (Firebase)**: Cloud data synchronization via Appwrite with offline queueing

## Services Architecture
- **SimpleMotionService**: Central motion tracking coordinator (singleton)
- **Universal3DROMEngine**: 3D range of motion calculations
- **VisionPoseProvider**: Computer vision pose detection
- **SPARCCalculationService**: Movement smoothness analysis
-- **AppwriteService**: Cloud data synchronization (Appwrite is the runtime backend)
- **CalibrationDataManager**: User calibration persistence


## Build Requirements
- **Target Device**: iPhone 16 with iOS 26.0
- **Error Handling**: All compilation errors must be resolved completely
- **Testing**: Ensure all builds pass without warnings or errors

## Security & Configuration
- **KeychainManager**: Secure API key storage
- **SecureConfig**: Environment-based configuration management

## Logging System
-- **FlexaLog**: Structured logging with categorized loggers (gemini, backend, motion, vision, security, ui, notifications, game, lifecycle)
- Uses Apple's unified logging system (os.Logger)