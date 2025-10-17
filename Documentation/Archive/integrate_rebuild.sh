#!/bin/bash

# FlexaSwiftUI Dual Tracking Integration Script
# This script helps integrate the rebuilt components into the existing project

echo "🚀 Starting FlexaSwiftUI Dual Tracking Integration..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if we're in the right directory
if [ ! -f "FlexaSwiftUI.xcodeproj/project.pbxproj" ]; then
    echo -e "${RED}❌ Error: Please run this script from the FlexaSwiftUI project root directory${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Found FlexaSwiftUI project${NC}"

# Step 1: Backup existing files
echo -e "\n${YELLOW}📦 Creating backup of existing files...${NC}"
mkdir -p Backup/$(date +%Y%m%d_%H%M%S)
cp -r FlexaSwiftUI/Services Backup/$(date +%Y%m%d_%H%M%S)/ 2>/dev/null
cp -r FlexaSwiftUI/Games Backup/$(date +%Y%m%d_%H%M%S)/ 2>/dev/null
echo -e "${GREEN}✅ Backup created${NC}"

# Step 2: Check for required dependencies
echo -e "\n${YELLOW}🔍 Checking dependencies...${NC}"

# Check for Firebase
if grep -q "Firebase" "Podfile" 2>/dev/null; then
    echo -e "${GREEN}✅ Firebase found in Podfile${NC}"
else
    echo -e "${YELLOW}⚠️  Firebase not found in Podfile. Adding...${NC}"
    cat >> Podfile <<EOL

  # Firebase for dual tracking
  pod 'Firebase/Core'
  pod 'Firebase/Auth'
  pod 'Firebase/Firestore'
  pod 'Firebase/Analytics'
EOL
fi

# Step 3: Update Info.plist if needed
echo -e "\n${YELLOW}📝 Checking Info.plist permissions...${NC}"
if grep -q "NSCameraUsageDescription" "FlexaSwiftUI/Info.plist"; then
    echo -e "${GREEN}✅ Camera permission already configured${NC}"
else
    echo -e "${YELLOW}⚠️  Camera permission missing - please add manually${NC}"
fi

if grep -q "NSMotionUsageDescription" "FlexaSwiftUI/Info.plist"; then
    echo -e "${GREEN}✅ Motion permission already configured${NC}"
else
    echo -e "${YELLOW}⚠️  Motion permission missing - please add manually${NC}"
fi

# Step 4: Create file mapping
echo -e "\n${YELLOW}📄 Creating integration mapping...${NC}"
cat > integration_map.txt <<EOL
=== REBUILT COMPONENTS MAPPING ===

SERVICES:
- HandheldMotionService.swift -> Replaces SimpleMotionService for handheld games
- CameraVisionService.swift -> Replaces SimpleMotionService for camera games
- RebuildSPARCService.swift -> New SPARC calculation service
- RebuildDataStorageService.swift -> Enhanced session storage
- ServiceBridge.swift -> Migration helper

GAMES (Handheld):
- RebuildFruitSlicerGame.swift -> Replaces OptimizedFruitSlicerGameView
- RebuildFanTheFlameGame.swift -> Replaces FanOutTheFlameGameView
- RebuildWitchBrewGame.swift -> Replaces OptimizedWitchBrewGameView

GAMES (Camera):
- RebuildBalloonPopGame.swift -> Replaces BalloonPopGameView
- RebuildConstellationGame.swift -> New implementation
- RebuildWallClimbersGame.swift -> Replaces WallClimbersGameView

NAVIGATION:
- RebuildNavigationController.swift -> New instant navigation system
- RebuildResultsView -> Enhanced results with instant routing
- RebuildPostSurveyView -> 1-10 scale survey with proper navigation

APP STRUCTURE:
- RebuildFlexaSwiftUIApp.swift -> New main app entry point
- InstructionsView.swift -> Unified instructions for all games
- FirebaseConfig.swift -> Firebase configuration

EOL

echo -e "${GREEN}✅ Integration map created${NC}"

# Step 5: Run pod install if needed
if [ -f "Podfile" ]; then
    echo -e "\n${YELLOW}🔧 Running pod install...${NC}"
    pod install
    echo -e "${GREEN}✅ Pods installed${NC}"
fi

# Step 6: Generate Xcode integration steps
echo -e "\n${YELLOW}📱 Generating Xcode integration steps...${NC}"
cat > xcode_integration_steps.md <<EOL
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

EOL

echo -e "${GREEN}✅ Xcode integration steps generated${NC}"

# Step 7: Create test checklist
echo -e "\n${YELLOW}✅ Creating test checklist...${NC}"
cat > test_checklist.md <<EOL
# Dual Tracking System Test Checklist

## Handheld Games Testing
- [ ] Fruit Slicer - Pendulum motion tracking works
- [ ] Fruit Slicer - Vertical movement constrained
- [ ] Fan the Flame - Left/right fanning detected
- [ ] Fan the Flame - Flame responds to motion
- [ ] Witch Brew - Circular motion tracking works
- [ ] Witch Brew - Progress increases with circles
- [ ] All handheld games - ARKit 3D tracking active
- [ ] All handheld games - 50Hz sensor sampling

## Camera Games Testing  
- [ ] Balloon Pop - Camera permission requested
- [ ] Balloon Pop - Elbow angle detection works
- [ ] Balloon Pop - Skeleton overlay visible
- [ ] Constellation - Wrist tracking accurate
- [ ] Constellation - Pattern detection works
- [ ] Wall Climbers - Upward motion detection
- [ ] Wall Climbers - Only up counts as reps
- [ ] All camera games - Apple Vision active

## Navigation Testing
- [ ] Results -> Done -> Survey -> Continue -> HOME
- [ ] Results -> Retry -> Survey -> Continue -> INSTRUCTIONS
- [ ] Instant navigation (no gradual transitions)
- [ ] Background cleanup happens properly

## Data Storage Testing
- [ ] Sessions save locally as JSON
- [ ] Sessions upload to Firebase
- [ ] SPARC calculations work for both modes
- [ ] AI analysis requests sent
- [ ] Historical data loads in Progress view

## Performance Testing
- [ ] 60fps gameplay maintained
- [ ] No memory leaks
- [ ] Smooth transitions
- [ ] Services stop properly when games end

EOL

echo -e "${GREEN}✅ Test checklist created${NC}"

# Final summary
echo -e "\n${GREEN}==================================${NC}"
echo -e "${GREEN}✅ Integration preparation complete!${NC}"
echo -e "${GREEN}==================================${NC}"
echo -e "\nNext steps:"
echo -e "1. Review ${YELLOW}integration_map.txt${NC} for component mappings"
echo -e "2. Follow ${YELLOW}xcode_integration_steps.md${NC} in Xcode"
echo -e "3. Use ${YELLOW}test_checklist.md${NC} to verify everything works"
echo -e "\n${YELLOW}Note: Make sure to test on a real device for motion sensors!${NC}"
