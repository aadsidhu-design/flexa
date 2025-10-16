# Swift Package Manager Configuration for MediaPipe

## Automated Setup Script

Run this script to automatically add MediaPipe to your Xcode project:

```bash
#!/bin/bash

# Navigate to project directory
cd /Users/aadi/Desktop/FlexaSwiftUI

echo "📦 Adding MediaPipe to FlexaSwiftUI via Swift Package Manager..."

# Open Xcode and wait for it to launch
open FlexaSwiftUI.xcodeproj

echo "
✅ Xcode project opened!

📝 Manual Steps to Complete:
1. In Xcode, go to: File → Add Package Dependencies...
2. Paste this URL: https://github.com/google-ai-edge/mediapipe
3. Select version: 'Up to Next Major' from 0.10.26
4. Click 'Add Package'
5. Select product: MediaPipeTasksVision
6. Click 'Add Package' to finish

Alternative: Use CocoaPods
------------------------
If SPM fails, you can use CocoaPods instead:

1. Create/update Podfile:
   cd /Users/aadi/Desktop/FlexaSwiftUI
   pod init  # if Podfile doesn't exist
   
2. Add this line to Podfile:
   pod 'MediaPipeTasksVision'
   
3. Run:
   pod install
   
4. Open FlexaSwiftUI.xcworkspace (not .xcodeproj)
"

# Download model file
echo "
📥 Downloading BlazePose model...
"

MODEL_URL="https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/latest/pose_landmarker_lite.task"
MODEL_PATH="/Users/aadi/Desktop/FlexaSwiftUI/pose_landmarker_lite.task"

if command -v curl &> /dev/null; then
    curl -L "$MODEL_URL" -o "$MODEL_PATH"
    if [ -f "$MODEL_PATH" ]; then
        echo "✅ Model downloaded to: $MODEL_PATH"
        echo "
📝 Next Step: Drag pose_landmarker_lite.task into Xcode
   - Right-click project navigator → Add Files to 'FlexaSwiftUI'
   - Select: pose_landmarker_lite.task
   - Check: Copy items if needed
   - Check: Add to targets: FlexaSwiftUI
"
    else
        echo "❌ Download failed. Please download manually from:"
        echo "   $MODEL_URL"
    fi
else
    echo "❌ curl not found. Please download model manually from:"
    echo "   $MODEL_URL"
fi
```

## Manual Package.swift Configuration

If you prefer to configure Package.swift manually (for custom builds), create this file:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FlexaSwiftUI",
    platforms: [
        .iOS(.v16)
    ],
    dependencies: [
        // MediaPipe Tasks Vision for pose detection
        .package(url: "https://github.com/google-ai-edge/mediapipe", from: "0.10.26")
    ],
    targets: [
        .target(
            name: "FlexaSwiftUI",
            dependencies: [
                .product(name: "MediaPipeTasksVision", package: "mediapipe")
            ]
        )
    ]
)
```

## CocoaPods Alternative (If SPM Fails)

Some developers report issues with MediaPipe's SPM integration. If you encounter problems, use CocoaPods:

### Podfile

Create or update `Podfile` in the project root:

```ruby
platform :ios, '16.0'

target 'FlexaSwiftUI' do
  use_frameworks!

  # MediaPipe Tasks Vision
  pod 'MediaPipeTasksVision', '~> 0.10.26'

  # Existing pods (if any)
  # ...
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
    end
  end
end
```

### Installation Commands

```bash
# Install CocoaPods if not already installed
sudo gem install cocoapods

# Navigate to project directory
cd /Users/aadi/Desktop/FlexaSwiftUI

# Install dependencies
pod install

# Open workspace (not project!)
open FlexaSwiftUI.xcworkspace
```

## Verifying Installation

After adding MediaPipe via SPM or CocoaPods, verify it's working:

### 1. Check Import

Create a test Swift file:

```swift
import MediaPipeTasksVision

func testMediaPipeImport() {
    print("MediaPipeTasksVision imported successfully!")
}
```

If Xcode doesn't show errors, the package is installed correctly.

### 2. Check Build

1. Clean build folder: **Product → Clean Build Folder** (⇧⌘K)
2. Build: **Product → Build** (⌘B)
3. Look for success message in build log

### 3. Check Model Loading

After adding the `.task` file to your project, test loading:

```swift
if let modelPath = Bundle.main.path(forResource: "pose_landmarker_lite", ofType: "task") {
    print("✅ Model found at: \(modelPath)")
} else {
    print("❌ Model NOT found - check Bundle Resources")
}
```

Run this in `AppDelegate` or `FlexaSwiftUIApp.init()` to verify on app launch.

## Common SPM Issues

### Issue 1: Package Resolution Fails

**Error**: `Cannot find package 'mediapipe'`

**Solutions**:
1. Check internet connection
2. Clear SPM cache:
   ```bash
   rm -rf ~/Library/Caches/org.swift.swiftpm
   ```
3. Reset package caches in Xcode:
   - **File → Packages → Reset Package Caches**
4. Try adding with specific version:
   ```
   https://github.com/google-ai-edge/mediapipe.git @ 0.10.26
   ```

### Issue 2: Build Errors After Adding Package

**Error**: `Undefined symbol: _OBJC_CLASS_$_MPPPoseLandmarker`

**Solutions**:
1. Ensure **MediaPipeTasksVision** is in **Target → General → Frameworks, Libraries, and Embedded Content**
2. Set **Embed & Sign** (not "Do Not Embed")
3. Clean derived data:
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData
   ```
4. Rebuild

### Issue 3: Binary Size Increase

MediaPipe adds ~10-15 MB to your app binary. If this is a concern:

1. Use `pose_landmarker_lite.task` (7 MB) instead of Full (10 MB)
2. Enable **App Thinning** in Xcode:
   - Target → Build Settings → Enable Bitcode: **Yes**
3. Use **On-Demand Resources** to load model conditionally

## Migration from Vision to MediaPipe Checklist

- [ ] Add MediaPipe package via SPM or CocoaPods
- [ ] Download and add `pose_landmarker_lite.task` to project
- [ ] Verify model file is in Bundle Resources
- [ ] Update `SimpleMotionService.swift` to use `MediaPipePoseProvider`
- [ ] Build and test on physical device
- [ ] Monitor console for initialization logs
- [ ] Test camera games (Balloon Pop, Wall Climbers)
- [ ] Verify ROM tracking and rep counting still work
- [ ] Check memory usage (should be stable)
- [ ] Test in various lighting conditions

## Rollback Plan

If MediaPipe doesn't work for your setup:

1. Remove package from Xcode:
   - **File → Packages → Resolve Package Versions**
   - Select mediapipe → Remove
2. Delete model file from project
3. Revert `SimpleMotionService.swift`:
   ```swift
   private var poseProvider = VisionPoseProvider()
   ```
4. Clean and rebuild

## Support

If you encounter issues:

1. Check MediaPipe GitHub Issues: https://github.com/google-ai-edge/mediapipe/issues
2. Review iOS setup guide: https://developers.google.com/mediapipe/solutions/setup_ios
3. Post in MediaPipe Slack: https://mediapipe.page.link/joinslack
