# Quick Fix Guide - What Got Fixed

## ✅ FIXED TODAY

### 1. **Coordinate Mapping Inverted** → FIXED
- **File**: `CoordinateMapper.swift`
- **What**: Hand up now moves pin/cursor UP (was going DOWN)
- **Test**: Arm Raises, Balloon Pop, Wall Climbers games

### 2. **Constellation Game Broken** → FIXED  
- **File**: `SimplifiedConstellationGameView.swift`
- **What**:
  - Can start from ANY dot now ✅
  - Dots don't move when selected ✅  
  - Line follows hand to next dot ✅
  - Each connection = 1 rep ✅
  - No timer displayed ✅
- **Test**: Arm Raises game

### 3. **Services Keep Running** → FIXED
- **What**: Camera/pose tracking now stops when game ends
- **Test**: All camera games (check analyzing screen)

## ⏳ STILL NEED TO FIX

### 1. Follow Circle Clockwise/Counter-Clockwise
- **Issue**: User goes clockwise, cursor goes counter-clockwise
- **Fix Needed**: Might need to mirror ARKit X-axis
- **File**: `FollowCircleGameView.swift` line ~430

### 2. Circular Rep Over-Counting  
- **Issue**: 14 reps when did 1-2 circles
- **Fix**: Thresholds already tightened, test if enough

### 3. Wall Climbers Timer
- **Fix**: Remove timer display (copy Arm Raises approach)
- **File**: `WallClimbersGameView.swift`

### 4. Data Export  
- **Fix**: Add confirmation dialog before export
- **File**: `DataExportService.swift` + `SettingsView.swift`

### 5. Instructions
- **Fix**: Rewrite all 6 game instructions
- **File**: `GameInstructionsView.swift`

### 6. Skip Survey
- **Fix**: Make it update goals like completing survey
- **File**: `ResultsView.swift`

### 7. Scroll Indicators
- **Fix**: Hide on all ScrollViews (most already done)
- **Find**: Search all `.swift` files for `ScrollView`

## HOW TO TEST

1. **Build successful**: ✅ Done
2. **Run on device**: Test coordinate mapping
3. **Arm Raises**: Try starting from different dots
4. **Follow Circle**: Check if clockwise works
5. **All games**: Count reps manually vs app count

## QUICK WINS (Easy to fix now)

1. Wall Climbers timer (5 min)
2. Scroll indicators (10 min)  
3. Skip survey goal update (10 min)
4. Data export dialog (15 min)
5. Instructions (30 min)

## THE BIG ONE (Needs testing)

- **Follow Circle circular motion**: May need device testing to verify ARKit coordinate system behavior with front camera

