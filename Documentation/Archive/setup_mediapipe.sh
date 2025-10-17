#!/bin/bash

# FlexaSwiftUI - MediaPipe BlazePose Setup Script
# This script automates the download and Xcode integration setup

set -e  # Exit on error

PROJECT_DIR="/Users/aadi/Desktop/FlexaSwiftUI"
MODEL_NAME="pose_landmarker_full.task"
MODEL_URL="https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_full/float16/latest/pose_landmarker_full.task"

echo "🔥 MediaPipe BlazePose Full Model Setup"
echo "========================================"
echo ""

# Navigate to project directory
cd "$PROJECT_DIR"

# Download model if it doesn't exist
if [ -f "$MODEL_NAME" ]; then
    echo "✅ Model file already exists: $MODEL_NAME"
else
    echo "📥 Downloading BlazePose Full model (~10 MB)..."
    curl -L "$MODEL_URL" -o "$MODEL_NAME"
    
    if [ -f "$MODEL_NAME" ]; then
        FILE_SIZE=$(du -h "$MODEL_NAME" | cut -f1)
        echo "✅ Downloaded successfully: $MODEL_NAME ($FILE_SIZE)"
    else
        echo "❌ Download failed!"
        exit 1
    fi
fi

echo ""
echo "📦 Next Steps:"
echo "=============="
echo ""
echo "1. Add MediaPipe Package to Xcode:"
echo "   • Open FlexaSwiftUI.xcodeproj"
echo "   • File → Add Package Dependencies..."
echo "   • URL: https://github.com/google-ai-edge/mediapipe"
echo "   • Version: Up to Next Major from 0.10.26"
echo "   • Product: MediaPipeTasksVision"
echo "   • Click Add Package"
echo ""
echo "2. Add Model File to Xcode:"
echo "   • In Xcode Project Navigator"
echo "   • Right-click → Add Files to 'FlexaSwiftUI'"
echo "   • Select: $MODEL_NAME"
echo "   • ✅ Check: Copy items if needed"
echo "   • ✅ Check: Add to targets: FlexaSwiftUI"
echo "   • Click Add"
echo ""
echo "3. Verify in Xcode:"
echo "   • Check Project Navigator shows: $MODEL_NAME"
echo "   • Target → Build Phases → Copy Bundle Resources"
echo "   • Confirm $MODEL_NAME is listed"
echo ""
echo "4. Build and Test:"
echo "   • Product → Clean Build Folder (⇧⌘K)"
echo "   • Product → Build (⌘B)"
echo "   • Run on physical device"
echo "   • Test camera games"
echo ""
echo "🚀 Ready to migrate to MediaPipe BlazePose Full!"
echo ""

# Open Xcode
read -p "Open Xcode now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    open FlexaSwiftUI.xcodeproj
fi
