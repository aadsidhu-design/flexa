# Comprehensive Fixes Plan

## Issues to Fix:

### 1. **Pendulum Circle Game (FollowCircle) - CRITICAL**
- [x] Movement is INVERTED (clockwise becomes counter-clockwise)
- [x] Rep detection overcounting (14 reps for 1-2 circles)
- [x] Smoothness not calculated/graphed
- [x] Grace period needed (5 seconds)
- [ ] Fix coordinate mapping

### 2. **Balloon Pop (Elbow Extension) - CRITICAL**
- [x] TWO pins instead of ONE
- [x] Pin movement inverted (up/down -> left/right)
- [ ] Pin should be CLIPPED to wrist position (not moving independently)
- [ ] Coordinates mapping incorrectly

### 3. **Arm Raises (Constellation) - CRITICAL**
- [x] Remove timer display
- [x] Circle at top left needs to disappear until wrist detected
- [ ] Circle should STICK to wrist instantly
- [ ] Dynamic line only when hovering over target dot
- [ ] Coordinates not mapping correctly for vertical phone

### 4. **Wall Climbers - NEEDS REVIEW**
- [x] Remove timer
- [ ] Verify coordinate mapping
- [ ] Ensure vertical phone orientation works

### 5. **Fan the Flame - REP DETECTION**
- [x] Small swings not registering
- [ ] Need better detection for partial swings
- [ ] Smoothness calculation

### 6. **Fruit Slicer - REFERENCE**
- [x] Smoothness working correctly (use as reference)
- [x] SPARC calculation working

### 7. **All Camera Games**
- [ ] Remove circles at top left/right corners
- [ ] Ensure pose detection coordinates map correctly for VERTICAL phone
- [ ] Add coordinate logging for debugging
- [ ] Ensure smoothness is calculated and graphed properly
- [ ] Make sure goals update on "skip survey"

### 8. **Data Export**
- [x] Service exists
- [x] Download confirmation dialog
- [ ] Test share sheet functionality
- [ ] Ensure all data is included

### 9. **UI/UX Improvements**
- [ ] Remove grey scroll indicators globally
- [ ] Improve all game instructions (clarity)
- [ ] Ensure dynamic screen size handling

### 10. **Circle Rep Detection**
- [ ] Use IMU data instead of ARKit for better accuracy
- [ ] Fix circular movement detection algorithm
- [ ] Proper angle tracking and circle completion detection

## Priority Order:
1. Fix coordinate mapping for camera games (vertical orientation)
2. Fix circle movement inversion
3. Fix rep detection for circles
4. Fix balloon pop pin clipping and movement
5. Improve rep detection accuracy for all games
6. Add smoothness calculation for all games
7. Update instructions
8. Remove scroll indicators
9. Test data export
