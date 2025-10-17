# MediaPipe BlazePose Migration Guide

## Overview

FlexaSwiftUI has been migrated from Apple Vision Framework to Google MediaPipe BlazePose for pose detection. This change provides:

- **Better tracking reliability**: BlazePose maintains tracking even when the device tilts or the user moves
- **Lower confidence thresholds**: Configured to track poses at 30% confidence (vs Vision's higher defaults)
- **More robust front camera performance**: Optimized for challenging lighting and angles
- **33-point skeleton**: More detailed joint tracking than Vision's limited keypoints

## Setup Instructions

### Step 1: Add MediaPipe via Swift Package Manager

1. Open `FlexaSwiftUI.xcodeproj` in Xcode
2. Go to **File → Add Package Dependencies...**
3. Enter the repository URL:
   ```
   https://github.com/google-ai-edge/mediapipe
   ```
4. Select **Version**: `Up to Next Major` starting from `0.10.26`
5. Click **Add Package**
6. In the "Choose Package Products" dialog, select:
   - ✅ **MediaPipeTasksVision**
7. Click **Add Package**

### Step 2: Download BlazePose Model

MediaPipe requires a `.task` model file to be bundled with the app.

#### Option A: Lite Model (Recommended for FlexaSwiftUI)
- **Name**: `pose_landmarker_lite.task`
- **Size**: ~7 MB
- **Performance**: Optimized for real-time mobile use
- **Download URL**: [MediaPipe Pose Landmarker Models](https://developers.google.com/mediapipe/solutions/vision/pose_landmarker/index#models)

#### Option B: Full Model (Higher Accuracy)
- **Name**: `pose_landmarker_full.task`
- **Size**: ~10 MB
- **Performance**: Better accuracy, slightly slower
- **Use when**: Testing shows lite model isn't accurate enough

#### Installation Steps:

1. Download the model file from the MediaPipe documentation
2. In Xcode, drag the `.task` file into your project navigator
3. In the file dialog:
   - ✅ **Copy items if needed**
   - ✅ **Add to targets: FlexaSwiftUI**
   - Click **Finish**
4. Verify the model is in the project by checking:
   - Project Navigator shows `pose_landmarker_lite.task` (or `pose_landmarker_full.task`)
   - Target → Build Phases → Copy Bundle Resources includes the file

### Step 3: Update Model Name (if using Full model)

If you downloaded the **Full** model instead of **Lite**, update the model name in `MediaPipePoseProvider.swift`:

```swift
// Line ~21
private let modelName = "pose_landmarker_full"  // Change from "pose_landmarker_lite"
```

### Step 4: Build and Test

1. Clean the build folder: **Product → Clean Build Folder** (⇧⌘K)
2. Build the project: **Product → Build** (⌘B)
3. Run on a **physical device** (simulator has limited camera support)
4. Test camera-based exercises:
   - Balloon Pop
   - Wall Climbers
   - Make Your Own (camera mode)

## Configuration Tuning

### Confidence Thresholds

The current configuration is optimized for **maximum tracking reliability**:

```swift
// In MediaPipePoseProvider.swift (lines ~27-29)
private let minDetectionConfidence: Float = 0.3  // 30%
private let minPresenceConfidence: Float = 0.3   // 30%
private let minTrackingConfidence: Float = 0.3   // 30%
```

**If you experience false positives** (tracking non-human objects), increase these values:
```swift
private let minDetectionConfidence: Float = 0.5  // 50%
private let minPresenceConfidence: Float = 0.5   // 50%
private let minTrackingConfidence: Float = 0.5   // 50%
```

**If tracking is still lost during tilting**, decrease further (not recommended below 0.2):
```swift
private let minDetectionConfidence: Float = 0.2  // 20%
private let minPresenceConfidence: Float = 0.2   // 20%
private let minTrackingConfidence: Float = 0.2   // 20%
```

### Frame Rate

Default: 30 FPS (line ~26):
```swift
private let minimumFrameInterval: TimeInterval = 1.0 / 30.0
```

**For smoother tracking** (higher battery usage):
```swift
private let minimumFrameInterval: TimeInterval = 1.0 / 60.0  // 60 FPS
```

**For battery saving** (lower smoothness):
```swift
private let minimumFrameInterval: TimeInterval = 1.0 / 15.0  // 15 FPS
```

### Image Preprocessing

Currently disabled but available in `createHighQualityMPImage` (lines ~127-133):

```swift
// Uncomment to enhance low-light performance
let adjustedImage = ciImage.applyingFilter("CIColorControls", parameters: [
    "inputBrightness": 0.1,
    "inputContrast": 1.1
])
```

Enable this if front camera struggles in dim lighting conditions.

## Verification Checklist

After migration, verify these behaviors:

### Camera Games
- [ ] **Balloon Pop**: Arm elevation tracked smoothly even with phone tilt
- [ ] **Wall Climbers**: Shoulder tracking maintains lock during sideways movement
- [ ] **Make Your Own (camera)**: Custom exercises detect reps reliably

### Tracking Quality
- [ ] Pose skeleton appears in LiveCameraView overlay
- [ ] ROM values update in real-time during movement
- [ ] Rep counter increments correctly
- [ ] No crashes or "model not found" errors in console

### Performance
- [ ] Frame rate stays at ~30 FPS (check Xcode Instruments)
- [ ] No excessive memory usage (should stay under 200 MB)
- [ ] Battery drain is reasonable during gameplay

### Console Logs
Look for these success indicators:
```
🔥 [MEDIAPIPE] MediaPipe BlazePose initialized successfully with lowered confidence thresholds
🔥 [MEDIAPIPE] Starting pose tracking with BlazePose
🔥 [MEDIAPIPE] Processing frame #30
```

**Red flags** (should NOT appear):
```
🔥 [MEDIAPIPE] MediaPipe model file not found: pose_landmarker_lite.task
🔥 [MEDIAPIPE] Max consecutive failures reached (10)
```

## Troubleshooting

### Model File Not Found

**Error**: `MediaPipe model file not found: pose_landmarker_lite.task`

**Solution**:
1. Verify the file is in the project navigator
2. Check Build Phases → Copy Bundle Resources includes the `.task` file
3. Clean build folder and rebuild
4. Ensure file name matches exactly (case-sensitive)

### No Pose Detection

**Symptoms**: Camera shows but no skeleton overlay appears

**Solutions**:
1. Run on a **physical device** (simulator has limited camera support)
2. Ensure sufficient lighting in the room
3. Check camera permissions: Settings → FlexaSwiftUI → Camera
4. Lower confidence thresholds temporarily to 0.2
5. Check console for MediaPipe errors

### Poor Tracking Performance

**Symptoms**: Skeleton jumps around or disappears frequently

**Solutions**:
1. Switch to `pose_landmarker_full.task` for better accuracy
2. Increase frame rate to 60 FPS
3. Enable image preprocessing for low-light environments
4. Ensure phone is held steady (not shaking)

### Crashes on Launch

**Error**: Swift package resolution or linker errors

**Solutions**:
1. Delete DerivedData: `rm -rf ~/Library/Developer/Xcode/DerivedData`
2. Re-add MediaPipe package via SPM
3. Clean build folder and rebuild
4. Ensure deployment target is iOS 16.0+

## Comparison: Vision vs MediaPipe

| Feature | Apple Vision | MediaPipe BlazePose |
|---------|--------------|---------------------|
| **Keypoints** | Limited (17 joints) | Comprehensive (33 joints) |
| **Tilt Resilience** | Loses tracking | Maintains tracking |
| **Front Camera** | Struggles with angles | Robust multi-angle |
| **Confidence Threshold** | Fixed/high | Configurable/low |
| **Lighting** | Requires good lighting | Works in varied lighting |
| **Setup** | Built-in (no dependencies) | Requires model download |
| **Model Size** | N/A | 7-10 MB |
| **Performance** | Native iOS | Optimized TensorFlow Lite |

## Migration Rollback (if needed)

If you need to revert to Apple Vision:

1. Open `SimpleMotionService.swift` (line ~293)
2. Change:
   ```swift
   private var poseProvider = MediaPipePoseProvider()
   ```
   to:
   ```swift
   private var poseProvider = VisionPoseProvider()
   ```
3. Remove MediaPipe package dependency
4. Delete `pose_landmarker_*.task` files
5. Rebuild

Both providers implement the same interface, so no other code changes are needed.

## Support Resources

- **MediaPipe Documentation**: https://developers.google.com/mediapipe/solutions/vision/pose_landmarker
- **Model Downloads**: https://developers.google.com/mediapipe/solutions/vision/pose_landmarker/index#models
- **GitHub Examples**: https://github.com/google-ai-edge/mediapipe-samples/tree/main/examples/pose_landmarker/ios
- **FlexaSwiftUI Issues**: Check `.github/copilot-instructions.md` for architecture notes

## Next Steps

1. **Test thoroughly** on multiple devices (iPhone 12+, various iOS versions)
2. **Gather user feedback** on tracking quality
3. **Monitor console logs** for MediaPipe errors
4. **Adjust confidence thresholds** based on real-world usage
5. **Consider A/B testing** Vision vs MediaPipe if needed
