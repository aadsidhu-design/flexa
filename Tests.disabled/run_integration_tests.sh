#!/bin/bash

# Integration Test Runner for IMU Rep Detection, ROM, and SPARC
# This script runs comprehensive tests and generates a detailed report

set -e

echo "=========================================="
echo "FlexaSwiftUI Integration Test Suite"
echo "Testing: IMU Rep Detection, ROM, SPARC"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test configuration
PROJECT_PATH="FlexaSwiftUI.xcodeproj"
SCHEME="FlexaSwiftUI"
DESTINATION="platform=iOS Simulator,name=iPhone 16,OS=18.0"

# Find available simulator if default not found
if ! xcrun simctl list devices | grep -q "iPhone 16.*18.0"; then
    echo "${YELLOW}Default simulator not found, searching for alternatives...${NC}"
    DESTINATION="platform=iOS Simulator,name=iPhone 16"
fi

echo "Running tests with configuration:"
echo "  Project: $PROJECT_PATH"
echo "  Scheme: $SCHEME"
echo "  Destination: $DESTINATION"
echo ""

# Run IMU Rep Detector Tests
echo "${YELLOW}[1/3] Running IMU Rep Detector Integration Tests...${NC}"
xcodebuild test \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -only-testing:FlexaSwiftUITests/IMURepDetectorIntegrationTests \
    2>&1 | tee /tmp/imu_test_output.log | \
    grep -E "Test Suite|Test Case|passed|failed|error" || true

IMU_RESULT=${PIPESTATUS[0]}

echo ""

# Run SPARC Integration Tests
echo "${YELLOW}[2/3] Running SPARC Integration Tests...${NC}"
xcodebuild test \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -only-testing:FlexaSwiftUITests/SPARCIntegrationTests \
    2>&1 | tee /tmp/sparc_test_output.log | \
    grep -E "Test Suite|Test Case|passed|failed|error" || true

SPARC_RESULT=${PIPESTATUS[0]}

echo ""

# Run existing Camera Rep Detector Tests
echo "${YELLOW}[3/3] Running Camera Rep Detector Tests...${NC}"
xcodebuild test \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -only-testing:FlexaSwiftUITests/CameraRepDetectorTests \
    2>&1 | tee /tmp/camera_test_output.log | \
    grep -E "Test Suite|Test Case|passed|failed|error" || true

CAMERA_RESULT=${PIPESTATUS[0]}

echo ""
echo "=========================================="
echo "Test Results Summary"
echo "=========================================="

# Check results
if [ $IMU_RESULT -eq 0 ]; then
    echo -e "${GREEN}✓ IMU Rep Detector Tests: PASSED${NC}"
else
    echo -e "${RED}✗ IMU Rep Detector Tests: FAILED${NC}"
fi

if [ $SPARC_RESULT -eq 0 ]; then
    echo -e "${GREEN}✓ SPARC Integration Tests: PASSED${NC}"
else
    echo -e "${RED}✗ SPARC Integration Tests: FAILED${NC}"
fi

if [ $CAMERA_RESULT -eq 0 ]; then
    echo -e "${GREEN}✓ Camera Rep Detector Tests: PASSED${NC}"
else
    echo -e "${RED}✗ Camera Rep Detector Tests: FAILED${NC}"
fi

echo ""

# Overall result
if [ $IMU_RESULT -eq 0 ] && [ $SPARC_RESULT -eq 0 ] && [ $CAMERA_RESULT -eq 0 ]; then
    echo -e "${GREEN}=========================================="
    echo "ALL TESTS PASSED ✓"
    echo "==========================================${NC}"
    exit 0
else
    echo -e "${RED}=========================================="
    echo "SOME TESTS FAILED ✗"
    echo "==========================================${NC}"
    echo ""
    echo "Check logs for details:"
    echo "  IMU Tests: /tmp/imu_test_output.log"
    echo "  SPARC Tests: /tmp/sparc_test_output.log"
    echo "  Camera Tests: /tmp/camera_test_output.log"
    exit 1
fi
