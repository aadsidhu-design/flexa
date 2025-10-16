# Xcode Integration Steps

## 1. Add New Files to Project
1. Open FlexaSwiftUI.xcworkspace
2. Right-click on FlexaSwiftUI folder
3. Select "Add Files to FlexaSwiftUI..."
4. Add all Rebuild*.swift files

## 2. Update Build Settings
1. Set iOS Deployment Target to 15.0 or higher
2. Enable "Allow Arbitrary Loads" if testing locally

## 3. Configure App Entry Point
1. In FlexaSwiftUI.xcodeproj, select the app target
2. Under "General" tab, set "Main Interface" to empty
3. In Info.plist, update UIApplicationSceneManifest if needed

## 4. Update Existing References
Replace references in existing code:
- SimpleMotionService.shared -> ServiceBridge.shared
- Import the new services where needed

## 5. Test the Integration
1. Build and run on device (not simulator for motion)
2. Test handheld games with phone
3. Test camera games with front camera
4. Verify navigation flow works correctly

