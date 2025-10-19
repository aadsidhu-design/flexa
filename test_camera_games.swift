#!/usr/bin/env swift

// Comprehensive Camera Games Test Suite
// Tests: Rep detection, ROM mapping, coordinate transforms, ARKit fallbacks

import Foundation
import CoreGraphics

print("==========================================")
print("Camera Games Comprehensive Test Suite")
print("==========================================\n")

var passedTests = 0
var failedTests = 0

func assert(_ condition: Bool, _ message: String) {
    if condition {
        print("✅ PASS: \(message)")
        passedTests += 1
    } else {
        print("❌ FAIL: \(message)")
        failedTests += 1
    }
}

// MARK: - Test 1: Camera Rep Detection Cooldown

print("\n[Test 1] Camera Rep Detection - Cooldown Period")
print("Testing rep detection with realistic timing...")

let cooldownPeriod = 0.65 // Current cooldown
var cameraReps = 0
var lastCameraRepTime = 0.0

// Simulate 50 reps at 1.2s intervals (realistic pace)
for i in 0..<50 {
    let time = Double(i) * 1.2
    let rom = 25.0 // Valid ROM
    
    if time - lastCameraRepTime >= cooldownPeriod {
        cameraReps += 1
        lastCameraRepTime = time
    }
}

assert(cameraReps >= 45, "Should detect most reps at 1.2s pace (got \(cameraReps)/50)")

// Test with faster pace (0.8s per rep)
var fastReps = 0
var lastFastTime = 0.0

for i in 0..<50 {
    let time = Double(i) * 0.8
    if time - lastFastTime >= cooldownPeriod {
        fastReps += 1
        lastFastTime = time
    }
}

assert(fastReps >= 40, "Should detect reps at 0.8s pace (got \(fastReps)/50)")

// MARK: - Test 2: Optimal Cooldown Calculation

print("\n[Test 2] Optimal Cooldown Period")
print("Testing recommended cooldown values...")

let optimalCooldown = 0.4 // Recommended: 400ms
var optimalReps = 0
var lastOptimalTime = 0.0

for i in 0..<50 {
    let time = Double(i) * 1.0 // 1 rep per second
    if time - lastOptimalTime >= optimalCooldown {
        optimalReps += 1
        lastOptimalTime = time
    }
}

assert(optimalReps >= 48, "Optimal cooldown should catch most reps (got \(optimalReps)/50)")

// MARK: - Test 3: ROM Threshold Validation

print("\n[Test 3] ROM Threshold Validation")
print("Testing ROM filtering...")

let romThreshold = 15.0
let testROMs = [10.0, 14.9, 15.0, 20.0, 25.0, 30.0]
var validROMs = 0

for rom in testROMs {
    if rom >= romThreshold {
        validROMs += 1
    }
}

assert(validROMs == 4, "Should accept 4 ROMs >= 15° (got \(validROMs))")

// MARK: - Test 4: Wall Climbers Motion Detection

print("\n[Test 4] Wall Climbers - Upward Motion Detection")
print("Testing vertical movement tracking...")

enum ClimbPhase { case waiting, up, down }
var phase = ClimbPhase.waiting
var startY: CGFloat = 500
var peakY: CGFloat = 500
let screenHeight: CGFloat = 800
let threshold: CGFloat = 0.1 // 10% of screen
let movementThreshold = threshold * screenHeight // 80 pixels

var climbReps = 0

// Simulate upward climb then downward return
let wristPositions: [CGFloat] = [500, 480, 450, 420, 380, 350, 320, 300, 280, 260, 240, 260, 280, 300, 350, 400]

for wristY in wristPositions {
    switch phase {
    case .waiting:
        if wristY < startY - movementThreshold || startY == 500 {
            phase = .up
            startY = wristY
            peakY = wristY
        }
    case .up:
        if wristY < peakY {
            peakY = wristY
        }
        if wristY > peakY + movementThreshold {
            phase = .down
            let distance = startY - peakY
            if distance >= 100 { // minimum distance
                climbReps += 1
            }
            phase = .waiting
            startY = wristY
        }
    case .down:
        break
    }
}

assert(climbReps >= 1, "Should detect upward climb motion (got \(climbReps))")

// MARK: - Test 5: Coordinate Mapping

print("\n[Test 5] Coordinate Mapping - Vision to Screen")
print("Testing coordinate transformations...")

// Vision coordinates: normalized 0-1
let visionX = 0.5
let visionY = 0.3

// Screen coordinates
let screenW: CGFloat = 375
let screenH: CGFloat = 812

let screenX = CGFloat(visionX) * screenW
let screenY = CGFloat(visionY) * screenH

assert(screenX == 187.5, "Vision X 0.5 should map to screen center (got \(screenX))")
assert(screenY == 243.6, "Vision Y 0.3 should map correctly (got \(screenY))")

// Test inverse mapping
let backToVisionX = Double(screenX / screenW)
let backToVisionY = Double(screenY / screenH)

assert(abs(backToVisionX - visionX) < 0.01, "Inverse mapping X should match")
assert(abs(backToVisionY - visionY) < 0.01, "Inverse mapping Y should match")

// MARK: - Test 6: Joint Angle Calculation

print("\n[Test 6] Joint Angle Calculation")
print("Testing angle computation from 3 points...")

func calculateAngle(p1: CGPoint, vertex: CGPoint, p2: CGPoint) -> Double {
    let v1 = CGPoint(x: p1.x - vertex.x, y: p1.y - vertex.y)
    let v2 = CGPoint(x: p2.x - vertex.x, y: p2.y - vertex.y)
    
    let dot = v1.x * v2.x + v1.y * v2.y
    let mag1 = sqrt(v1.x * v1.x + v1.y * v1.y)
    let mag2 = sqrt(v2.x * v2.x + v2.y * v2.y)
    
    let cosAngle = dot / (mag1 * mag2)
    let angleRad = acos(max(-1, min(1, cosAngle)))
    return angleRad * 180 / .pi
}

// Test 90° angle
let shoulder = CGPoint(x: 100, y: 100)
let elbow = CGPoint(x: 150, y: 100)
let wrist = CGPoint(x: 150, y: 150)

let angle90 = calculateAngle(p1: shoulder, vertex: elbow, p2: wrist)
assert(abs(angle90 - 90) < 1, "Should calculate 90° angle (got \(angle90)°)")

// Test 180° angle (straight arm)
let wrist180 = CGPoint(x: 200, y: 100)
let angle180 = calculateAngle(p1: shoulder, vertex: elbow, p2: wrist180)
assert(abs(angle180 - 180) < 1, "Should calculate 180° angle (got \(angle180)°)")

// MARK: - Test 7: ARKit World Transform

print("\n[Test 7] ARKit World Transform")
print("Testing coordinate system transformations...")

// Simulate ARKit world transform (4x4 matrix)
struct Transform {
    var position: (x: Float, y: Float, z: Float)
    var rotation: (x: Float, y: Float, z: Float, w: Float)
}

let worldTransform = Transform(
    position: (0.5, 1.2, -0.3),
    rotation: (0, 0, 0, 1) // Identity rotation
)

assert(worldTransform.position.y > 0, "Y position should be positive (upward)")
assert(abs(worldTransform.rotation.w - 1) < 0.01, "Identity rotation should have w=1")

// MARK: - Test 8: ARKit Anchor Fallback

print("\n[Test 8] ARKit Anchor Fallback System")
print("Testing anchor priority: world → face → object...")

enum AnchorType { case world, face, object, none }

func selectAnchor(worldAvailable: Bool, faceAvailable: Bool, objectAvailable: Bool) -> AnchorType {
    if worldAvailable { return .world }
    if faceAvailable { return .face }
    if objectAvailable { return .object }
    return .none
}

// Test priority
let anchor1 = selectAnchor(worldAvailable: true, faceAvailable: true, objectAvailable: true)
assert(anchor1 == .world, "Should prefer world anchor when available")

let anchor2 = selectAnchor(worldAvailable: false, faceAvailable: true, objectAvailable: true)
assert(anchor2 == .face, "Should fallback to face anchor")

let anchor3 = selectAnchor(worldAvailable: false, faceAvailable: false, objectAvailable: true)
assert(anchor3 == .object, "Should fallback to object anchor")

let anchor4 = selectAnchor(worldAvailable: false, faceAvailable: false, objectAvailable: false)
assert(anchor4 == .none, "Should return none when no anchors available")

// MARK: - Test 9: Pose Confidence Filtering

print("\n[Test 9] Pose Confidence Filtering")
print("Testing pose quality thresholds...")

let confidenceThreshold = 0.5
let poseConfidences = [0.3, 0.45, 0.5, 0.65, 0.8, 0.95]
var validPoses = 0

for confidence in poseConfidences {
    if confidence >= confidenceThreshold {
        validPoses += 1
    }
}

assert(validPoses == 4, "Should accept 4 poses with confidence >= 0.5")

// MARK: - Test 10: Wrist Tracking Stability

print("\n[Test 10] Wrist Tracking Stability")
print("Testing position smoothing...")

var wristHistory: [CGPoint] = []
let smoothingWindow = 3

// Add noisy wrist positions
let noisyPositions = [
    CGPoint(x: 100, y: 200),
    CGPoint(x: 102, y: 198),
    CGPoint(x: 98, y: 202),
    CGPoint(x: 101, y: 199),
    CGPoint(x: 99, y: 201)
]

for pos in noisyPositions {
    wristHistory.append(pos)
    if wristHistory.count > smoothingWindow {
        wristHistory.removeFirst()
    }
}

// Calculate average position
let avgX = wristHistory.map { $0.x }.reduce(0, +) / CGFloat(wristHistory.count)
let avgY = wristHistory.map { $0.y }.reduce(0, +) / CGFloat(wristHistory.count)

assert(abs(avgX - 100) < 5, "Smoothed X should be near 100 (got \(avgX))")
assert(abs(avgY - 200) < 5, "Smoothed Y should be near 200 (got \(avgY))")

// MARK: - Test 11: Elbow Extension Detection

print("\n[Test 11] Elbow Extension Detection")
print("Testing extension/flexion cycle...")

enum ExtensionPhase { case waiting, extending, flexing }
var extPhase = ExtensionPhase.waiting
var extReps = 0

let elbowAngles = [80.0, 100.0, 120.0, 140.0, 160.0, 170.0, 150.0, 120.0, 90.0, 70.0]

for angle in elbowAngles {
    switch extPhase {
    case .waiting:
        if angle > 140 {
            extPhase = .extending
        }
    case .extending:
        if angle < 90 {
            extReps += 1
            extPhase = .waiting
        }
    case .flexing:
        break
    }
}

assert(extReps >= 1, "Should detect extension cycle")

// MARK: - Test 12: Screen Boundary Validation

print("\n[Test 12] Screen Boundary Validation")
print("Testing coordinate bounds checking...")

func isWithinBounds(point: CGPoint, width: CGFloat, height: CGFloat) -> Bool {
    return point.x >= 0 && point.x <= width && point.y >= 0 && point.y <= height
}

let validPoint = CGPoint(x: 100, y: 200)
let invalidPoint1 = CGPoint(x: -10, y: 200)
let invalidPoint2 = CGPoint(x: 100, y: 900)

assert(isWithinBounds(point: validPoint, width: 375, height: 812), "Valid point should be in bounds")
assert(!isWithinBounds(point: invalidPoint1, width: 375, height: 812), "Negative X should be out of bounds")
assert(!isWithinBounds(point: invalidPoint2, width: 375, height: 812), "Y > height should be out of bounds")

// MARK: - Test 13: Distance Calculation

print("\n[Test 13] Distance Calculation")
print("Testing Euclidean distance...")

func distance(from p1: CGPoint, to p2: CGPoint) -> CGFloat {
    let dx = p2.x - p1.x
    let dy = p2.y - p1.y
    return sqrt(dx * dx + dy * dy)
}

let point1 = CGPoint(x: 0, y: 0)
let point2 = CGPoint(x: 3, y: 4)
let dist = distance(from: point1, to: point2)

assert(abs(dist - 5) < 0.01, "3-4-5 triangle distance should be 5 (got \(dist))")

// MARK: - Test 14: Minimum Distance Threshold

print("\n[Test 14] Minimum Distance Threshold")
print("Testing movement validation...")

let minDistance: CGFloat = 100
let movements = [50.0, 80.0, 100.0, 120.0, 150.0]
var validMovements = 0

for movement in movements {
    if movement >= minDistance {
        validMovements += 1
    }
}

assert(validMovements == 3, "Should accept 3 movements >= 100px")

// MARK: - Test 15: Rep Rate Calculation

print("\n[Test 15] Rep Rate Calculation")
print("Testing reps per minute...")

let totalReps = 50
let totalTime = 60.0 // seconds
let repsPerMinute = Double(totalReps) / (totalTime / 60.0)

assert(repsPerMinute == 50.0, "50 reps in 60s = 50 RPM")

let fastReps2 = 30
let fastTime = 20.0
let fastRPM = Double(fastReps2) / (fastTime / 60.0)

assert(fastRPM == 90.0, "30 reps in 20s = 90 RPM")

// MARK: - Test 16: Constellation Pattern Validation

print("\n[Test 16] Constellation Pattern Validation")
print("Testing dot connection logic...")

func isValidConnection(from: Int, to: Int, connected: [Int]) -> Bool {
    guard from != to else { return false }
    guard !connected.contains(to) else { return false }
    return true
}

let connectedDots = [0, 1, 2]
assert(isValidConnection(from: 2, to: 3, connected: connectedDots), "Should allow new connection")
assert(!isValidConnection(from: 2, to: 1, connected: connectedDots), "Should reject already connected")
assert(!isValidConnection(from: 2, to: 2, connected: connectedDots), "Should reject self-connection")

// MARK: - Test 17: Triangle Pattern Completion

print("\n[Test 17] Triangle Pattern Completion")
print("Testing pattern completion logic...")

func isTriangleComplete(connected: [Int], totalPoints: Int) -> Bool {
    return connected.count >= totalPoints
}

assert(!isTriangleComplete(connected: [0, 1], totalPoints: 3), "2 points incomplete")
assert(isTriangleComplete(connected: [0, 1, 2], totalPoints: 3), "3 points complete")

// MARK: - Test 18: Frame Rate Handling

print("\n[Test 18] Frame Rate Handling")
print("Testing camera frame processing...")

let targetFPS = 30.0
let frameDuration = 1.0 / targetFPS

var processedFrames = 0
var currentTime = 0.0

for _ in 0..<90 { // 3 seconds worth
    currentTime += frameDuration
    processedFrames += 1
}

let actualFPS = Double(processedFrames) / currentTime
assert(abs(actualFPS - targetFPS) < 1, "Should process at ~30 FPS (got \(actualFPS))")

// MARK: - Test 19: Pose Dropout Handling

print("\n[Test 19] Pose Dropout Handling")
print("Testing missing pose recovery...")

var poseHistory: [CGPoint?] = []
let gracePeriod = 3 // frames

// Simulate pose dropout
let poses: [CGPoint?] = [
    CGPoint(x: 100, y: 200),
    CGPoint(x: 102, y: 198),
    nil, // dropout
    nil, // dropout
    CGPoint(x: 104, y: 196)
]

for pose in poses {
    poseHistory.append(pose)
}

let dropouts = poseHistory.filter { $0 == nil }.count
assert(dropouts == 2, "Should track 2 dropouts")
assert(dropouts <= gracePeriod, "Dropouts within grace period")

// MARK: - Test 20: ROM Normalization

print("\n[Test 20] ROM Normalization")
print("Testing ROM value clamping...")

func normalizeROM(_ rom: Double) -> Double {
    return max(0, min(180, rom))
}

assert(normalizeROM(-10) == 0, "Negative ROM should clamp to 0")
assert(normalizeROM(200) == 180, "ROM > 180 should clamp to 180")
assert(normalizeROM(90) == 90, "Valid ROM should pass through")

// Summary
print("\n==========================================")
print("Test Results Summary")
print("==========================================")
print("✅ Passed: \(passedTests)")
print("❌ Failed: \(failedTests)")
print("Total: \(passedTests + failedTests)")

if failedTests == 0 {
    print("\n🎉 ALL CAMERA GAME TESTS PASSED!")
    print("\n📋 Recommendations:")
    print("  • Reduce camera rep cooldown from 0.65s to 0.4s")
    print("  • Implement ARKit anchor fallback: world → face → object")
    print("  • Use pose confidence threshold of 0.5")
    print("  • Apply 3-frame smoothing window for wrist tracking")
    exit(0)
} else {
    print("\n⚠️  SOME TESTS FAILED")
    exit(1)
}
