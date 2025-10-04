# Comprehensive Game Fixes - Implementation Plan

## Issues to Fix

### 1. **Pendulum Circle Game (FollowCircleGameView)**
- ✅ Movement is INVERTED (clockwise → counter-clockwise)
- ✅ Rep detection overcounting (14 reps for 1-2 circles)
- ✅ No smoothness being calculated/graphed  
- ✅ Should use IMU/ARKit for circular movement (not just tilt)
- ✅ Coordinate mapping issues
- ✅ Grace period should be 5 seconds at start

### 2. **Elbow Extension/Balloon Pop (BalloonPopGameView)**
- ✅ TWO pins showing instead of ONE
- ✅ Movement is horizontal instead of vertical (inverted)
- ✅ Pin should STICK to wrist exactly
- ✅ Coordinate mapping is wrong

### 3. **Arm Raises/Constellation (SimplifiedConstellationGameView)**
- ✅ Timer should be REMOVED (no time limit)
- ✅ Hand circle should stick to wrist exactly
- ✅ Dynamic line from dot to hand ONLY when hovering over current target
- ✅ Remove extra circles at top left/right
- ✅ Coordinate mapping precision

### 4. **Wall Climbers (WallClimbersGameView)**
- ✅ Remove timer (no time limit)
- ✅ Coordinate fixes
- ✅ Better pose detection

### 5. **Fan the Flame (FanOutTheFlameGameView)**
- ✅ Rep detection - swings left & right (vertical phone)
- ✅ Better sensitivity for small movements
- ✅ SPARC/smoothness tracking

### 6. **Fruit Slicer (OptimizedFruitSlicerGameView)**
- ✅ Already good - use as reference for SPARC

### 7. **Scapular Retractions**
- ✅ Rep detection wrong (each swing direction = 1 rep, should be full cycle)

### 8. **Skip Survey Button**
- ✅ Should update goals like normal survey completion
- ✅ Missing functionality

### 9. **Download Data Feature**
- ✅ Prompt user "Download all your data?"
- ✅ Export ALL session data to file
- ✅ Open Files app or show file location

### 10. **ScrollView Indicators**
- ✅ Remove grey scroll indicators throughout app

### 11. **Smoothness (SPARC) for ALL games**
- ✅ Ensure all games calculate smoothness
- ✅ Graph smoothness properly on results
- ✅ Fix curve issues (straight line up then down)

### 12. **Instructions**
- ✅ Improve all 6 game instructions
- ✅ Make them clearer and more specific
- ✅ Phone orientation guidance

## Implementation Order

1. Fix CoordinateMapper for proper vertical phone mapping
2. Fix FollowCircleGameView (inverted movement + rep counting)
3. Fix BalloonPopGameView (single pin, vertical movement)
4. Fix SimplifiedConstellationGameView (remove timer, sticky circle)
5. Fix WallClimbersGameView (remove timer)
6. Fix FanOutTheFlameGameView (rep detection)
7. Fix SPARC calculation for all games
8. Hide scroll indicators globally
9. Implement download data feature
10. Update all instructions
11. Fix skip survey button

## Files to Modify

- `/Games/FollowCircleGameView.swift`
- `/Games/BalloonPopGameView.swift` 
- `/Games/SimplifiedConstellationGameView.swift`
- `/Games/WallClimbersGameView.swift`
- `/Games/FanOutTheFlameGameView.swift`
- `/Games/OptimizedFruitSlicerGameView.swift`
- `/Utilities/CoordinateMapper.swift`
- `/Services/SPARCCalculationService.swift`
- `/Views/GameInstructionsView.swift`
- `/Views/ResultsView.swift`
- `/Views/SettingsView.swift` (download data)
- Global ScrollView indicator hiding

