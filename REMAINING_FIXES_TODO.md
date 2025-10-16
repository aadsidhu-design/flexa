# Remaining Fixes - TODO List

## ✅ COMPLETED
1. **Camera obstruction warnings removed** - All camera games (Balloon Pop, Wall Climbers, Constellation)
2. **Constellation circle** - Already working, uses `CoordinateMapper.mapVisionPointToScreen`
3. **Coordinate mapping** - Already correct, using proper screen mapping
4. **Smoothness goal for handheld games** - Fixed in previous commit

## 🔧 IN PROGRESS

### 1. Sessions Goal Circle Update for Custom Exercises
**Status**: NEEDS VERIFICATION
**Location**: `GoalsAndStreaksService.calculateProgress()`
**Issue**: Need to ensure custom exercises update the sessions goal
**Check**: Line 195-230 in GoalsAndStreaksService.swift

The code already counts ALL sessions:
```swift
let todaySessions = comprehensiveSessions.filter { calendar.isDate($0.timestamp, inSameDayAs: today) }
todayProgress.gamesPlayed = todaySessions.count
```

This should work for custom exercises too since they create `ComprehensiveSessionData`.

**Action**: Test custom exercise and verify sessions goal updates

### 2. Download Data Functionality
**Status**: NEEDS IMPLEMENTATION
**Files to check**:
- Settings view with download button
- Data export functionality

**Requirements**:
- Export all session data to JSON/CSV
- Include user goals, streaks, sessions
- Preserve session numbers and user ID

### 3. Delete Data Functionality  
**Status**: NEEDS VERIFICATION
**Location**: `BackendService.clearAllUserData()` and `LocalDataManager.clearLocalData()`
**Requirements**:
- Delete all sessions
- Delete goals and streaks
- **PRESERVE**: Session number, user ID
- **DELETE**: Custom exercises created by user

**Action**: Check if custom exercises are being deleted

### 4. Custom Exercise Prompt Gating
**Status**: NEEDS IMPLEMENTATION
**Location**: Custom exercise creation flow
**Requirements**:
- Block profanity/swearing
- Block requests for sensitive information
- Block exploitation attempts
- Only allow exercise-related prompts

**Implementation**: Add prompt validation before sending to AI

### 5. Keyboard Dismissal for Custom Exercise
**Status**: NEEDS IMPLEMENTATION
**Location**: Custom exercise prompt text field
**Requirements**:
- Tap anywhere outside text field → keyboard dismisses
- Use `.onTapGesture` on background
- Or use `UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)`

### 6. UI/UX Improvements
**Status**: ONGOING
**Areas**:
- Custom exercise creation flow
- Settings screen
- Data management UI
- Goal editing UI

## 📋 PRIORITY ORDER

1. **HIGH**: Custom exercise prompt gating (security)
2. **HIGH**: Keyboard dismissal (UX)
3. **MEDIUM**: Delete data verification (preserve session number/user ID)
4. **MEDIUM**: Download data implementation
5. **LOW**: UI polish

## 🔍 FILES TO CHECK

1. `FlexaSwiftUI/Games/MakeYourOwnGameView.swift` - Custom exercise creation
2. `FlexaSwiftUI/Services/BackendService.swift` - Data deletion
3. `FlexaSwiftUI/Services/LocalDataManager.swift` - Local data management
4. Settings view (need to find file)
5. Custom exercise storage (need to find where they're saved)

## ⚠️ EDGE FILTER WARNINGS

The logs show:
```
🚫 [ZERO-FILTER] Edge position detected: (0.862747, 0.985356)
🚫 [ZERO-FILTER] Filtered invalid camera pose - likely initialization artifact
```

This is NORMAL - it's filtering out edge cases where BlazePose detects landmarks at screen edges (likely false positives). This is working as intended and prevents jittery tracking.

## 📝 NOTES

- Constellation game circle IS working - it's the cyan circle that follows the wrist
- Coordinate mapping is correct - using `CoordinateMapper.mapVisionPointToScreen`
- Camera obstruction warnings are now removed - games won't pause
- SPARC/smoothness goal should update for all games now
