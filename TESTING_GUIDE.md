# Testing Guide - Camera Games & System Fixes

## Quick Test Plan

### 1. **Follow Circle (Pendulum Circles)** 🔵
**Setup**: Hold phone in hand with screen facing you

**Test Checklist**:
- [ ] Move hand RIGHT → cursor moves RIGHT (not left!)
- [ ] Move hand FORWARD → cursor moves UP (not down!)
- [ ] Move in clockwise circle → cursor follows clockwise (not counter-clockwise!)
- [ ] Complete ONE full circle → should count as 1 rep (not 8-14!)
- [ ] Very small movements near center → should NOT count as reps
- [ ] Check logs: Should see SPARC data points being collected

**Expected Rep Count**: ~1 rep per 3-5 seconds of circular movement

---

### 2. **Arm Raises (Constellation Maker)** ⭐
**Setup**: Prop phone so camera sees upper body

**Test Checklist**:
- [ ] Hand circle ONLY appears when wrist is detected
- [ ] Hand circle DISAPPEARS when wrist not in frame
- [ ] Hand circle sticks precisely to wrist (no lag/offset)
- [ ] Line appears ONLY when hovering over current target dot
- [ ] No line to hand when not near target
- [ ] UI shows "Pattern 1/3" (not score or timer)
- [ ] Coordinates logged in console match on-screen position

**Expected**: Clean, precise hand tracking with no ghost circles

---

### 3. **Balloon Pop (Elbow Extension)** 🎈
**Setup**: Prop phone so camera sees upper body

**Test Checklist**:
- [ ] ONLY ONE pin visible (for active arm)
- [ ] No extra pins or circles
- [ ] Pin moves UP when you raise hand
- [ ] Pin moves DOWN when you lower hand
- [ ] Pin tip is at wrist position (not offset)
- [ ] Balloon pops when pin touches it
- [ ] Balloons appear overhead (one at a time)

**Expected**: Single pin tracking vertically, clean balloon popping

---

### 4. **Wall Climbers** 🧗
**Setup**: Prop phone so camera sees full body

**Test Checklist**:
- [ ] Altitude meter displays clearly
- [ ] Shows "Reps: X" count
- [ ] NO timer displayed
- [ ] Arms up → altitude increases
- [ ] Arms down → ready for next climb
- [ ] Hand circles track both wrists accurately

**Expected**: Clean altitude display, accurate rep counting

---

### 5. **Fan the Flame (Scapular Retractions)** 🔥
**Setup**: Hold phone in hand

**Test Checklist**:
- [ ] Swing LEFT → flame reduces
- [ ] Swing RIGHT → flame reduces
- [ ] Full swing (left→right OR right→left) = 1 rep
- [ ] NOT 2 reps per full cycle!
- [ ] Small swings count if above threshold
- [ ] Very tiny movements don't count

**Expected**: ~1 rep per full pendulum swing

---

### 6. **Game Instructions** 📖
**Test Checklist**:
- [ ] All 6 games have clear, concise instructions
- [ ] Each step has appropriate emoji
- [ ] Instructions explain phone orientation clearly
- [ ] Instructions explain what movement to do
- [ ] Instructions explain goal/objective
- [ ] Instructions give helpful tips

**Expected**: User can understand how to play without confusion

---

### 7. **Download Data** 💾
**Test Checklist**:
- [ ] Go to Settings
- [ ] Tap "Download Data"
- [ ] Confirmation dialog appears
- [ ] After confirm, file export happens
- [ ] iOS share sheet appears
- [ ] Can save to Files app
- [ ] JSON file contains all session data

**Expected**: Complete data export to JSON file

---

### 8. **Skip Survey** ⏭️
**Test Checklist**:
- [ ] Complete any exercise
- [ ] Post-survey appears
- [ ] Tap "Skip Survey" button
- [ ] Session completes without survey
- [ ] Goals still update correctly
- [ ] Session appears in history

**Expected**: Skipping survey works, session still saves

---

## Debug Console Checks

### Coordinate Logging (Camera Games)
Look for these logs:
```
📍 [Game-COORDS] RAW Vision: x=XXX.XX, y=YYY.YY
📍 [Game-COORDS] MAPPED Screen: x=XXX.X, y=YYY.Y
📍 [Game-COORDS] Final position: x=XXX.X, y=YYY.Y
```

### Rep Detection Logging
Look for these logs:
```
✅ [FollowCircle] Circle completed! Rep #X, Angle traveled: XXX.X°
🍃 [Fan] LEFT/RIGHT swing detected - Rep!
```

### SPARC Tracking
Look for these logs:
```
📊 [FollowCircle] SPARC collected: XX data points, final score: XX.XX
```

---

## Common Issues & Solutions

### Issue: Coordinates seem inverted
**Solution**: Check that CoordinateMapper is rotating and mirroring correctly
- Vision coords should be rotated 90° clockwise
- X should be mirrored for front camera

### Issue: Too many reps counted
**Solution**: Check rep detection thresholds
- Circle game: Minimum 320° travel required
- Fan game: Must alternate left/right swings

### Issue: Hand circle not showing
**Solution**: Check pose detection
- Ensure wrist landmark is detected
- Check camera has clear view
- Verify lighting conditions

### Issue: Movement feels laggy
**Solution**: Check smoothing alpha values
- Higher alpha = less smoothing, more responsive
- Current values: 0.7-0.8 for good balance

---

## Performance Checks

### Frame Rate
- Should maintain ~60 FPS during games
- Check console for "Performance issues detected" warnings
- Memory should stay under 250MB

### SPARC Calculation
- Should collect data points every frame
- Should calculate smoothness score at session end
- Score should be between -10 and 0 (higher = smoother)

---

## Build Verification

```bash
# Build succeeded with only minor warnings
** BUILD SUCCEEDED **

# No errors, only harmless warnings about AppIntents
```

---

## Files to Review

If issues occur, check these files:
1. `CoordinateMapper.swift` - Coordinate transformation
2. `FollowCircleGameView.swift` - Circular rep detection
3. `SimplifiedConstellationGameView.swift` - Hand tracking
4. `BalloonPopGameView.swift` - Pin positioning
5. `UnifiedRepDetectionService.swift` - Rep detection logic

---

## Success Criteria

✅ All camera games map coordinates correctly for vertical phone
✅ Rep detection is accurate (not overcounting)
✅ UI is clean (no extra circles, timers where not needed)
✅ Instructions are clear and actionable
✅ Download data exports complete session history
✅ Skip survey works without breaking session flow

---

## Next Steps After Testing

1. Test on physical device with real users
2. Gather feedback on rep detection sensitivity
3. Monitor crash reports for coordinate edge cases
4. Consider adaptive difficulty based on user performance
5. Add visual feedback for rep requirements being met

---

## Emergency Rollback

If critical issues found:
```bash
git log --oneline | head -5  # Find commit before fixes
git revert <commit-hash>     # Revert changes
xcodebuild clean build       # Rebuild
```

All changes are in version control and can be easily reverted if needed.
