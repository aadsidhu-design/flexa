# Camera Games Comprehensive Fix Plan

## Issues Identified

### 1. **Follow Circle Game (Pendulum Circles)**
- ❌ Movement is INVERSED - user moves clockwise but cursor goes counter-clockwise
- ❌ Rep detection is OVERCOMPENSATING (user does 1-2 circles, counts 8-9 reps)
- ❌ Smoothness (SPARC) not being calculated or graphed
- ❌ ROM for circular movement not properly calculated
- ❌ 5-second grace period needed at start

### 2. **Balloon Pop Game (Elbow Extension)**
- ❌ TWO pins showing instead of ONE
- ❌ Pin movement is HORIZONTAL (left/right) instead of VERTICAL (up/down)
- ❌ Pin should be "clipped" to wrist position - direct 1:1 mapping
- ❌ Smoothness (SPARC) for camera games needs improvement

### 3. **Constellation/Arm Raises Game**
- ❌ Timer should be REMOVED (no time limit)
- ❌ Circle at top left needs to be hidden until wrist detected
- ❌ Line should only show when hovering over current target dot
- ❌ Hand tracking circle not sticking properly to wrist

### 4. **Wall Climbers Game**
- ❌ Timer should be REMOVED (no time limit)
- ❌ Game ends when reaching 1000m altitude

### 5. **Fan the Flame Game**
- ❌ Rep detection needs improvement for short swings
- ❌ SPARC/smoothness calculation and graphing needs fixing

### 6. **Fruit Slicer Game**
- ✅ SPARC working correctly (use as reference for other games)

### 7. **All Camera Games**
- ❌ Coordinate mapping may not be correctly handling vertical phone orientation
- ❌ Preview should be dynamic for different phone sizes
- ❌ Two circles appearing at top (debug artifacts)

### 8. **General Issues**
- ❌ Skip survey button should update goals
- ❌ Download data feature not implemented
- ❌ Instructions need improvement for all 6 games

## Fix Strategy

### Phase 1: Fix Coordinate Mapping (CRITICAL)
1. Fix Follow Circle movement inversion
2. Fix Balloon Pop pin positioning (vertical, not horizontal)
3. Ensure all games use consistent coordinate mapping

### Phase 2: Fix Rep Detection
1. Tighten circular rep detection in Follow Circle
2. Improve swing detection in Fan the Flame
3. Ensure consistent rep thresholds

### Phase 3: Fix SPARC/Smoothness
1. Implement SPARC for all handheld games
2. Implement SPARC for all camera games
3. Ensure graphing hooks up correctly

### Phase 4: UI/UX Fixes
1. Remove timers where needed
2. Hide debug circles
3. Improve instructions
4. Add skip survey functionality
5. Add data download feature

### Phase 5: Testing & Validation
1. Test on actual device with vertical orientation
2. Validate coordinate mapping
3. Validate rep counting
4. Validate SPARC calculations
