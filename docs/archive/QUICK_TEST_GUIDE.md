# Quick Testing Guide - Handheld ROM Improvements

## ⚡ Fast Setup

1. **Build to device**: `Cmd+R` with physical iPhone selected
2. **Complete calibration**: Home → Settings → Calibrate Arm Length
3. **Ensure good lighting**: ARKit needs visual features to track

## 🎯 Test Each Game (5 min each)

### Fruit Slicer
**What to do**: Hold phone and swing arm forward/backward like a pendulum

**Expected behavior**:
- ✅ Each direction change = 1 rep (faster detection than before)
- ✅ ROM matches your actual swing angle (±5°)
- ✅ Small swings (20-30°) now count as reps
- ✅ SPARC shows 70-85% for smooth swings, 30-50% for jerky

**Check**:
```
Reps: Should increment on every forward→back or back→forward swing
ROM: Should show realistic angles (30-90° typical for therapeutic swings)
SPARC: Should vary based on smoothness (not stuck at 50%)
```

### Follow Circle
**What to do**: Move phone in circular pattern (like stirring a pot)

**Expected behavior**:
- ✅ Each complete circle = 1 rep
- ✅ ROM reflects circle size
- ✅ Partial circles (>320°) still count
- ✅ Both horizontal and vertical circles work

**Check**:
```
Reps: Complete circles should register
ROM: Larger circles = higher ROM
Pattern: Should detect "circle" in logs
```

### Fan the Flame
**What to do**: Swing phone side-to-side (frontal plane)

**Expected behavior**:
- ✅ Each direction change = 1 rep
- ✅ Smaller swings now register (was too strict before)
- ✅ ROM accurate for lateral movements
- ✅ Debounce prevents double-counting

**Check**:
```
Reps: Each left→right or right→left = 1 rep
ROM: Should match swing angle (typically 20-45°)
```

## 🔬 SPARC Specific Tests

### Test 1: Smooth Movement
**Do**: Move phone very smoothly at constant speed in a straight line
**Expected SPARC**: **75-90%** ✨

### Test 2: Jerky Movement  
**Do**: Move phone with abrupt stops and starts
**Expected SPARC**: **30-50%** ⚠️

### Test 3: Rapid Changes
**Do**: Quick acceleration then sudden deceleration
**Expected SPARC**: **35-55%** ⚠️

## 📊 ROM Accuracy Verification

### Small Movements (20-40°)
- Try a small swing, estimate angle visually
- Check if ROM matches ±3-5°

### Medium Movements (40-90°)
- Standard therapeutic range
- Should be very accurate (±4-5°)

### Large Movements (90-150°)
- Full arm extension
- Check against mirror/video ±5-8°

## 🐛 If Something's Wrong

### Reps not counting
1. Check calibration is complete
2. Try larger movements (>10cm displacement)
3. Verify ARKit tracking (should say "normal" in console)
4. Increase movement speed slightly

### ROM seems off
1. **Too high**: Recalibrate arm length (might be set too short)
2. **Too low**: Check phone grip - keep consistent distance from wrist
3. **Wildly inaccurate**: ARKit may have lost tracking - restart game

### SPARC stuck at 50%
1. **Must use physical device** - simulator doesn't work
2. Check motion permissions granted
3. Try more dramatic smooth vs jerky differences

## 📱 Console Logs to Watch

Enable verbose logging in Xcode console:
```
[Universal3D] Rep ROM: X.X° (pattern: arc/circle/line)
[Universal3D] Plane=XY/XZ/YZ Chord=X.XXXm Arc=X.XXXm Angle=XX.X°
[UnifiedRep] Rep #X [Method] ROM=XX.X°
[SPARC] Data point added: t=X.XXs value=XX.X total=XXX
```

## ✅ Success Criteria

After 5 minutes of testing each game:

- [ ] **Reps detect reliably** (95%+ of movements counted)
- [ ] **ROM values realistic** (match visual estimation ±5°)
- [ ] **SPARC varies dynamically** (not stuck at one value)
- [ ] **Pattern detection works** (logs show correct line/arc/circle)
- [ ] **No crashes or memory issues**

## 🎉 Expected Improvements vs. Old System

| Metric | Before | After |
|--------|--------|-------|
| Rep detection rate | 60-70% | 95%+ |
| ROM accuracy | ±15-20° | ±3-5° |
| SPARC dynamic range | 45-55% | 20-95% |
| Tilt bias impact | High | Eliminated |

## 🚨 Known Limitations

1. **ARKit needs features**: Blank walls may cause tracking loss
2. **Lighting dependent**: Works best in well-lit rooms
3. **Calibration critical**: Inaccurate arm length = inaccurate ROM
4. **Simulator won't work**: Must use physical device

## 💡 Pro Tips

- **Calibration**: Do it standing, arm fully extended, measure accurately
- **Testing ROM**: Film yourself and compare video to reported angle
- **SPARC testing**: Exaggerate smooth vs. jerky movements for clear differences
- **Pattern detection**: Check console logs to verify correct detection

---

**Total testing time**: ~20 minutes for thorough verification
**Priority**: Test Fruit Slicer first (most common game)

Good luck! 🚀
