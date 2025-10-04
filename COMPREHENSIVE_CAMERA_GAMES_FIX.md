# Comprehensive Camera Games Fix - Sprint Plan

## Critical Issues Identified

### 1. **Coordinate Mapping Inverted (Y-Axis)**
- **Problem**: When user moves hand UP, cursor/pin goes DOWN
- **Root Cause**: In CoordinateMapper, the Y-axis is not inverted correctly
- **Fix**: Invert Y-coordinate mapping so hand UP = cursor/pin UP

### 2. **Services Continue After Game Ends**
- **Problem**: Camera and pose tracking services keep running on analyzing/results screen
- **Fix**: Ensure cleanup() properly stops all services immediately when game ends

### 3. **Constellation Game (Arm Raises) Broken Mechanics**
- **Problem**: 
  - User can't start from any dot
  - Dots move when selected (should stay in place)
  - Line doesn't follow hand until hitting next dot
  - Rep counting inaccurate
- **Fix**: 
  - Allow starting from ANY dot
  - Lock selected dots in position
  - Show dynamic line from selected dot to hand until next connection
  - Count each point-to-point connection as a rep

### 4. **Balloon Pop Double Pin Issue**
- **Problem**: Two pins showing instead of one
- **Fix**: Remove duplicate pin rendering, ensure only active arm pin shows

### 5. **Timer on Arm Raises & Wall Climbers**
- **Problem**: These games have timers when they shouldn't
- **Fix**: Remove all timer display and time-based ending

### 6. **Scroll Indicators Visible**
- **Problem**: Gray scroll bars showing on all scroll views
- **Fix**: Ensure all ScrollViews have `showsIndicators: false`

### 7. **Smoothness Not Calculated for Camera Games**
- **Problem**: SPARC/smoothness data not collected or graphed properly
- **Fix**: Ensure all camera games collect movement data and calculate SPARC correctly

### 8. **Rep Detection for Circular Motion**
- **Problem**: 14 reps detected when user did 1-2 circles
- **Fix**: Improve circular motion detection algorithm, proper angle tracking

### 9. **Pendulum Circle Game - Movement Inverted**
- **Problem**: User moves clockwise, cursor goes counter-clockwise
- **Fix**: Fix ARKit coordinate transformation

### 10. **Data Export Missing Confirmation**
- **Problem**: No confirmation dialog before exporting data
- **Fix**: Add alert dialog with Files app navigation

### 11. **Game Instructions Need Improvement**
- **Problem**: Instructions unclear for all 6 games
- **Fix**: Rewrite instructions to be clearer and more specific

### 12. **Skip Survey Button Doesn't Update Goals**
- **Problem**: When skipping post-survey, goals don't update
- **Fix**: Ensure skipSurvey triggers same goal updates as completing survey

## Implementation Order

1. Fix CoordinateMapper (Y-axis inversion)
2. Fix all camera game coordinate mappings
3. Fix constellation game mechanics
4. Remove timers from arm raises & wall climbers
5. Improve circular motion detection
6. Fix pendulum circle ARKit mapping
7. Ensure service cleanup on game end
8. Hide all scroll indicators
9. Fix smoothness calculation for camera games
10. Add data export confirmation
11. Update game instructions
12. Fix skip survey goal updates

## Files to Modify

- [x] CoordinateMapper.swift
- [ ] SimplifiedConstellationGameView.swift
- [ ] BalloonPopGameView.swift  
- [ ] WallClimbersGameView.swift
- [ ] FollowCircleGameView.swift
- [ ] FanOutTheFlameGameView.swift
- [ ] OptimizedFruitSlicerGameView.swift
- [ ] All ScrollView files
- [ ] DataExportService.swift
- [ ] SettingsView.swift
- [ ] GameInstructionsView.swift
- [ ] ResultsView.swift (skip survey)
- [ ] SPARCService.swift (camera game smoothness)
