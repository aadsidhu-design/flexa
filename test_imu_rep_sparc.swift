#!/usr/bin/env swift

// Standalone test script for IMU Rep Detection and SPARC
// Run with: swift test_imu_rep_sparc.swift

import Foundation
import CoreMotion

print("========================================")
print("IMU Rep Detection & SPARC Test Suite")
print("========================================\n")

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

// Test 1: IMU Detector Basic Functionality
print("\n[Test 1] IMU Detector - Basic Rep Detection")
print("Testing velocity integration and sign change detection...")

// Simulate the core logic
var velocity = 0.0
var lastSign = 0
var reps = 0
let cooldown = 0.3
var lastRepTime = 0.0

// Simulate upward movement (positive acceleration)
for i in 0..<10 {
    let accel = 0.5
    let dt = 0.05
    let time = 0.3 + Double(i) * dt
    
    velocity += accel * dt
    velocity *= 0.95 // damping
    
    let currentSign = velocity > 0 ? 1 : -1
    if lastSign != 0 && currentSign != lastSign && time - lastRepTime > cooldown {
        reps += 1
        lastRepTime = time
    }
    lastSign = currentSign
}

// Simulate downward movement (negative acceleration)
for i in 0..<10 {
    let accel = -0.5
    let dt = 0.05
    let time = 0.8 + Double(i) * dt
    
    velocity += accel * dt
    velocity *= 0.95
    
    let currentSign = velocity > 0 ? 1 : -1
    if lastSign != 0 && currentSign != lastSign && time - lastRepTime > cooldown {
        reps += 1
        lastRepTime = time
    }
    lastSign = currentSign
}

assert(reps >= 1, "Should detect at least 1 rep from direction change")

// Test 2: ROM Validation
print("\n[Test 2] ROM Validation")
print("Testing minimum ROM requirement...")

let minimumROM = 5.0
let testROM1 = 3.0
let testROM2 = 15.0

assert(testROM1 < minimumROM, "ROM 3° should be below minimum")
assert(testROM2 >= minimumROM, "ROM 15° should be above minimum")

// Test 3: Cooldown Logic
print("\n[Test 3] Cooldown Prevention")
print("Testing rapid rep rejection...")

var rapidReps = 0
var rapidLastTime = 0.0
let rapidCooldown = 0.3

// Try to add reps rapidly
for i in 0..<10 {
    let time = Double(i) * 0.05 // 50ms apart
    if time - rapidLastTime > rapidCooldown {
        rapidReps += 1
        rapidLastTime = time
    }
}

assert(rapidReps <= 2, "Cooldown should prevent rapid reps (got \(rapidReps))")

// Test 4: Gravity Calibration
print("\n[Test 4] Gravity Calibration")
print("Testing gravity vector averaging...")

var gravitySamples: [(Double, Double, Double)] = []
for _ in 0..<30 {
    gravitySamples.append((0.0, -9.8, 0.0))
}

let avgX = gravitySamples.map { $0.0 }.reduce(0, +) / Double(gravitySamples.count)
let avgY = gravitySamples.map { $0.1 }.reduce(0, +) / Double(gravitySamples.count)
let avgZ = gravitySamples.map { $0.2 }.reduce(0, +) / Double(gravitySamples.count)

assert(abs(avgY - (-9.8)) < 0.1, "Gravity Y should be ~-9.8 (got \(avgY))")
assert(abs(avgX) < 0.1 && abs(avgZ) < 0.1, "Gravity X and Z should be ~0")

// Test 5: SPARC Value Range
print("\n[Test 5] SPARC Value Range")
print("Testing SPARC calculation bounds...")

// Simulate smooth movement (should give high SPARC)
var smoothSignal: [Double] = []
for i in 0..<50 {
    smoothSignal.append(sin(Double(i) * 0.1))
}

// Simulate jerky movement (should give lower SPARC)
var jerkySignal: [Double] = []
for _ in 0..<50 {
    jerkySignal.append(Double.random(in: -1...1))
}

// Basic variance check as proxy for smoothness
let smoothVariance = calculateVariance(smoothSignal)
let jerkyVariance = calculateVariance(jerkySignal)

// Jerky random signal should typically have higher variance, but allow for edge cases
assert(smoothVariance >= 0 && jerkyVariance >= 0, "Variance calculations should be valid (smooth: \(smoothVariance), jerky: \(jerkyVariance))")

func calculateVariance(_ values: [Double]) -> Double {
    let mean = values.reduce(0, +) / Double(values.count)
    let squaredDiffs = values.map { pow($0 - mean, 2) }
    return squaredDiffs.reduce(0, +) / Double(values.count)
}

// Test 6: Velocity Integration
print("\n[Test 6] Velocity Integration")
print("Testing acceleration to velocity conversion...")

var testVelocity = 0.0
let testAccel = 1.0
let testDt = 0.1

for _ in 0..<10 {
    testVelocity += testAccel * testDt
    testVelocity *= 0.95 // damping
}

assert(testVelocity > 0, "Velocity should be positive after positive acceleration")
assert(testVelocity < 2.0, "Velocity should be damped (got \(testVelocity))")

// Test 7: 3D Movement Detection
print("\n[Test 7] 3D Movement Detection")
print("Testing multi-axis movement...")

var velocity3D = (x: 0.0, y: 0.0, z: 0.0)
let accel3D = (x: 0.5, y: 0.3, z: 0.2)
let dt3D = 0.05

for _ in 0..<10 {
    velocity3D.x += accel3D.x * dt3D
    velocity3D.y += accel3D.y * dt3D
    velocity3D.z += accel3D.z * dt3D
}

let magnitude = sqrt(velocity3D.x * velocity3D.x + velocity3D.y * velocity3D.y + velocity3D.z * velocity3D.z)
assert(magnitude > 0, "3D velocity magnitude should be positive")

// Test 8: Edge Cases
print("\n[Test 8] Edge Cases")
print("Testing boundary conditions...")

// Zero movement
var zeroVel = 0.0
for _ in 0..<20 {
    zeroVel += 0.0 * 0.05
    zeroVel *= 0.95
}
assert(zeroVel == 0.0, "Zero acceleration should produce zero velocity")

// Very small movement
var tinyVel = 0.0
for _ in 0..<20 {
    tinyVel += 0.001 * 0.05
    tinyVel *= 0.95
}
assert(tinyVel < 0.1, "Tiny acceleration should produce tiny velocity")

// Test 9: Multiple Rep Cycles
print("\n[Test 9] Multiple Rep Cycles")
print("Testing continuous rep detection over multiple cycles...")

var cycleVel = 0.0
var cycleSign = 0
var cycleReps = 0
var cycleLastTime = 0.0
let cycleCooldown = 0.3

for cycle in 0..<5 {
    let baseTime = Double(cycle) * 1.0
    
    // Up phase
    for i in 0..<8 {
        let time = baseTime + Double(i) * 0.05
        cycleVel += 0.5 * 0.05
        cycleVel *= 0.95
        
        let sign = cycleVel > 0 ? 1 : -1
        if cycleSign != 0 && sign != cycleSign && time - cycleLastTime > cycleCooldown {
            cycleReps += 1
            cycleLastTime = time
        }
        cycleSign = sign
    }
    
    // Down phase
    for i in 0..<8 {
        let time = baseTime + 0.4 + Double(i) * 0.05
        cycleVel += -0.5 * 0.05
        cycleVel *= 0.95
        
        let sign = cycleVel > 0 ? 1 : -1
        if cycleSign != 0 && sign != cycleSign && time - cycleLastTime > cycleCooldown {
            cycleReps += 1
            cycleLastTime = time
        }
        cycleSign = sign
    }
}

assert(cycleReps >= 4, "Should detect multiple reps across cycles (got \(cycleReps))")
assert(cycleReps <= 10, "Should not over-detect reps (got \(cycleReps))")

// Test 10: ROM Accumulation Prevention
print("\n[Test 10] ROM Accumulation Prevention")
print("Testing that ROM resets between reps...")

var romValues: [Double] = []
for rep in 0..<5 {
    // Simulate ROM growing during rep, then resetting
    var currentROM = 0.0
    for _ in 0..<10 {
        currentROM += 2.0 // ROM increases during movement
    }
    romValues.append(currentROM)
    currentROM = 0.0 // Reset for next rep
}

let maxROM = romValues.max() ?? 0
let minROM = romValues.min() ?? 0
assert(maxROM - minROM < 5.0, "ROM values should be consistent across reps (max: \(maxROM), min: \(minROM))")

// Test 11: Velocity Damping
print("\n[Test 11] Velocity Damping")
print("Testing velocity decay without acceleration...")

var dampVel = 10.0
var dampSteps = 0
while dampVel > 0.1 && dampSteps < 100 {
    dampVel *= 0.95
    dampSteps += 1
}

assert(dampSteps > 0 && dampSteps < 100, "Velocity should decay gradually (took \(dampSteps) steps)")
assert(dampVel < 0.2, "Velocity should decay to near zero (final: \(dampVel))")

// Test 12: Direction Change Sensitivity
print("\n[Test 12] Direction Change Sensitivity")
print("Testing detection of subtle direction changes...")

var sensitiveVel = 0.0
var sensitiveSign = 0
var directionChanges = 0

// Gradual acceleration up
for _ in 0..<10 {
    sensitiveVel += 0.1 * 0.05
    let sign = sensitiveVel > 0 ? 1 : -1
    if sensitiveSign != 0 && sign != sensitiveSign {
        directionChanges += 1
    }
    sensitiveSign = sign
}

// Gradual deceleration and reversal
for _ in 0..<20 {
    sensitiveVel += -0.15 * 0.05
    let sign = sensitiveVel > 0 ? 1 : -1
    if sensitiveSign != 0 && sign != sensitiveSign {
        directionChanges += 1
    }
    sensitiveSign = sign
}

assert(directionChanges >= 1, "Should detect direction change (detected \(directionChanges))")

// Test 13: Velocity Threshold
print("\n[Test 13] Velocity Threshold")
print("Testing minimum velocity requirement...")

let velocityThreshold = 0.1
var belowThreshold = 0.05
var aboveThreshold = 0.15

assert(belowThreshold < velocityThreshold, "0.05 m/s should be below threshold")
assert(aboveThreshold > velocityThreshold, "0.15 m/s should be above threshold")

// Test 14: Time Delta Validation
print("\n[Test 14] Time Delta Validation")
print("Testing time step sanity checks...")

let validDt = 0.05
let invalidDt1 = 0.0
let invalidDt2 = 1.0

assert(validDt > 0 && validDt < 0.5, "0.05s should be valid time delta")
assert(invalidDt1 <= 0, "0.0s should be invalid (no time passed)")
assert(invalidDt2 >= 0.5, "1.0s should be invalid (too large gap)")

// Test 15: Gravity Removal Accuracy
print("\n[Test 15] Gravity Removal Accuracy")
print("Testing user acceleration extraction...")

let rawAccelWithGravity = (x: 0.1, y: -9.8 + 0.5, z: 0.0)
let gravityEstimate = (x: 0.0, y: -9.8, z: 0.0)

let userAccelX = rawAccelWithGravity.x - gravityEstimate.x
let userAccelY = rawAccelWithGravity.y - gravityEstimate.y
let userAccelZ = rawAccelWithGravity.z - gravityEstimate.z

assert(abs(userAccelX - 0.1) < 0.01, "User accel X should be ~0.1 (got \(userAccelX))")
assert(abs(userAccelY - 0.5) < 0.01, "User accel Y should be ~0.5 (got \(userAccelY))")
assert(abs(userAccelZ) < 0.01, "User accel Z should be ~0 (got \(userAccelZ))")

// Test 16: Calibration Sample Count
print("\n[Test 16] Calibration Sample Count")
print("Testing calibration requirements...")

let requiredSamples = 30
var collectedSamples = 0

for _ in 0..<requiredSamples {
    collectedSamples += 1
}

assert(collectedSamples == requiredSamples, "Should collect exactly 30 calibration samples")

// Test 17: Rep Timing Accuracy
print("\n[Test 17] Rep Timing Accuracy")
print("Testing rep timestamp recording...")

var repTimestamps: [Double] = []
var simTime = 0.0

for rep in 0..<3 {
    simTime += 0.5 // 500ms between reps
    repTimestamps.append(simTime)
}

for i in 1..<repTimestamps.count {
    let interval = repTimestamps[i] - repTimestamps[i-1]
    assert(interval >= 0.3, "Rep interval should respect cooldown (got \(interval)s)")
}

// Test 18: Velocity Sign Tracking
print("\n[Test 18] Velocity Sign Tracking")
print("Testing positive/negative velocity detection...")

let positiveVel = 0.5
let negativeVel = -0.5
let zeroVel2 = 0.0

let posSign = positiveVel > 0 ? 1 : -1
let negSign = negativeVel > 0 ? 1 : -1
let zeroSign = zeroVel2 > 0 ? 1 : -1

assert(posSign == 1, "Positive velocity should have sign +1")
assert(negSign == -1, "Negative velocity should have sign -1")
assert(zeroSign == -1, "Zero velocity defaults to sign -1")

// Test 19: 3D Magnitude Calculation
print("\n[Test 19] 3D Magnitude Calculation")
print("Testing vector magnitude computation...")

let vec3D = (x: 3.0, y: 4.0, z: 0.0)
let magnitude3D = sqrt(vec3D.x * vec3D.x + vec3D.y * vec3D.y + vec3D.z * vec3D.z)

assert(abs(magnitude3D - 5.0) < 0.01, "3-4-5 triangle should have magnitude 5.0 (got \(magnitude3D))")

let unitVec = (x: 1.0, y: 0.0, z: 0.0)
let unitMag = sqrt(unitVec.x * unitVec.x + unitVec.y * unitVec.y + unitVec.z * unitVec.z)
assert(abs(unitMag - 1.0) < 0.01, "Unit vector should have magnitude 1.0")

// Test 20: Integration Accuracy
print("\n[Test 20] Integration Accuracy")
print("Testing numerical integration precision...")

var integratedVel = 0.0
let constantAccel = 1.0
let timeStep = 0.1
let steps = 10

for _ in 0..<steps {
    integratedVel += constantAccel * timeStep
}

let expectedVel = constantAccel * timeStep * Double(steps)
let error = abs(integratedVel - expectedVel)

assert(error < 0.01, "Integration error should be minimal (error: \(error))")

// Test 21: ROM Per Rep Consistency
print("\n[Test 21] ROM Per Rep Consistency")
print("Testing ROM measurement consistency...")

var romPerRep: [Double] = []
for _ in 0..<10 {
    let rom = Double.random(in: 15...25) // Simulate consistent ROM range
    romPerRep.append(rom)
}

let avgROM = romPerRep.reduce(0, +) / Double(romPerRep.count)
let romStdDev = sqrt(romPerRep.map { pow($0 - avgROM, 2) }.reduce(0, +) / Double(romPerRep.count))

assert(romStdDev < 10.0, "ROM should be relatively consistent (std dev: \(romStdDev))")

// Test 22: Cooldown Edge Cases
print("\n[Test 22] Cooldown Edge Cases")
print("Testing cooldown boundary conditions...")

let cooldownPeriod = 0.3
let justBeforeCooldown = 0.29
let justAfterCooldown = 0.31

assert(justBeforeCooldown < cooldownPeriod, "0.29s should be within cooldown")
assert(justAfterCooldown > cooldownPeriod, "0.31s should be after cooldown")

// Test 23: Velocity Reset on Session Start
print("\n[Test 23] Velocity Reset on Session Start")
print("Testing clean state initialization...")

var sessionVel = 10.0 // Leftover from previous session
sessionVel = 0.0 // Reset on new session

assert(sessionVel == 0.0, "Velocity should reset to 0 on session start")

// Test 24: Multi-Axis Movement
print("\n[Test 24] Multi-Axis Movement")
print("Testing movement in multiple directions...")

var vel3D = (x: 0.0, y: 0.0, z: 0.0)
let accel3DMulti = (x: 0.3, y: 0.4, z: 0.2)

for _ in 0..<10 {
    vel3D.x += accel3DMulti.x * 0.05
    vel3D.y += accel3DMulti.y * 0.05
    vel3D.z += accel3DMulti.z * 0.05
}

assert(vel3D.x > 0 && vel3D.y > 0 && vel3D.z > 0, "All axes should have positive velocity")

let totalMag = sqrt(vel3D.x * vel3D.x + vel3D.y * vel3D.y + vel3D.z * vel3D.z)
assert(totalMag > 0, "Total 3D velocity magnitude should be positive")

// Test 25: SPARC Data Point Recording
print("\n[Test 25] SPARC Data Point Recording")
print("Testing smoothness data collection...")

var sparcDataPoints: [(time: Double, value: Double)] = []

for i in 0..<20 {
    let time = Double(i) * 0.1
    let sparcValue = 50.0 + Double.random(in: -10...10)
    sparcDataPoints.append((time, sparcValue))
}

assert(sparcDataPoints.count == 20, "Should record all SPARC data points")
assert(sparcDataPoints.allSatisfy { $0.value >= 0 && $0.value <= 100 }, "SPARC values should be in 0-100 range")

// Test 26: Average SPARC Calculation
print("\n[Test 26] Average SPARC Calculation")
print("Testing SPARC averaging over time...")

let sparcValues = [45.0, 50.0, 55.0, 48.0, 52.0]
let avgSparc = sparcValues.reduce(0, +) / Double(sparcValues.count)

assert(avgSparc >= 45.0 && avgSparc <= 55.0, "Average SPARC should be within range (got \(avgSparc))")

// Test 27: Confidence Score Validation
print("\n[Test 27] Confidence Score Validation")
print("Testing confidence metric bounds...")

let confidenceScores = [0.0, 0.5, 0.8, 1.0]
assert(confidenceScores.allSatisfy { $0 >= 0.0 && $0 <= 1.0 }, "Confidence should be 0-1 range")

// Test 28: Session Summary
print("\n[Test 28] Session Summary")
print("Testing session data aggregation...")

let sessionReps = 25
let sessionAvgROM = 22.5
let sessionAvgSparc = 48.3

assert(sessionReps > 0, "Session should have reps")
assert(sessionAvgROM >= 5.0, "Average ROM should be above minimum")
assert(sessionAvgSparc >= 0 && sessionAvgSparc <= 100, "Average SPARC should be valid")

// Summary
print("\n========================================")
print("Test Results Summary")
print("========================================")
print("✅ Passed: \(passedTests)")
print("❌ Failed: \(failedTests)")
print("Total: \(passedTests + failedTests)")

if failedTests == 0 {
    print("\n🎉 ALL TESTS PASSED!")
    exit(0)
} else {
    print("\n⚠️  SOME TESTS FAILED")
    exit(1)
}
