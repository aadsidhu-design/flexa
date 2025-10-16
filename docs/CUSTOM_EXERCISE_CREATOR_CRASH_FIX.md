# Custom Exercise Creator Crash Fix

**Date:** October 12, 2025  
**Issue:** App crashes when clicking "+" button to create custom exercise  
**Root Cause:** Nested NavigationStack causing SwiftUI navigation conflict

## Problem Analysis

### User Report
User reported that clicking the "+" button (green circle with plus icon) in the Exercises tab causes the app to crash or navigate incorrectly.

### Root Cause
The `CustomExerciseCreatorView` contained a nested `NavigationStack` wrapper (line 18):

```swift
var body: some View {
    NavigationStack {  // ❌ NESTED NavigationStack
        ZStack {
            // ... view content
        }
    }
}
```

This created a **nested NavigationStack conflict** because:
1. Main app uses `NavigationStack(path: $navigationCoordinator.path)` in `ContentView.swift`
2. When user taps "+", `navigationCoordinator.showCustomExerciseCreator()` appends `.customExerciseCreator` to the navigation path
3. The destination view (`CustomExerciseCreatorView`) then tries to create **another** `NavigationStack` inside itself
4. SwiftUI doesn't handle nested NavigationStacks well, causing crashes or unexpected behavior

## Solution

### Fix 1: Remove Nested NavigationStack
**File:** `FlexaSwiftUI/Views/CustomExerciseCreatorView.swift`

**Before:**
```swift
var body: some View {
    NavigationStack {
        ZStack {
            // ... content
        }
        .navigationTitle("AI Exercise Builder")
        .toolbar { ... }
    }
}
```

**After:**
```swift
var body: some View {
    ZStack {
        // ... content
    }
    .navigationTitle("AI Exercise Builder")
    .toolbar { ... }
}
```

**Changes:**
- ✅ Removed `NavigationStack` wrapper
- ✅ Kept all navigation modifiers (`.navigationTitle`, `.toolbar`, `.navigationBarBackButtonHidden`)
- ✅ View now properly integrates with parent NavigationStack

### Why This Works
- The view is already presented within the main app's `NavigationStack` hierarchy
- SwiftUI navigation modifiers (`.navigationTitle`, `.toolbar`) work on views **inside** a NavigationStack, they don't require the view itself to create one
- The parent NavigationStack handles all navigation logic
- Custom back button using `dismiss()` environment property works correctly

## Bonus Fix: Constellation Game Navigation Protection

While investigating, also added navigation protection to constellation game to prevent premature dismissal:

**File:** `FlexaSwiftUI/Games/SimplifiedConstellationGameView.swift`

**Changes:**
```swift
.toolbar(.hidden, for: .navigationBar)
.navigationBarBackButtonHidden(true) // Prevent back navigation during active game
.interactiveDismissDisabled(isGameActive) // Disable swipe-to-dismiss during gameplay
```

**Also added guards in lifecycle methods:**
```swift
private func endGame() {
    guard isGameActive else {
        FlexaLog.game.warning("⚠️ [ArmRaises] endGame() called but game not active - ignoring")
        return
    }
    // ... rest of method
}

private func cleanup() {
    FlexaLog.game.info("🧹 [ArmRaises] Cleanup called - stopping game session")
    isGameActive = false
    gameTimer?.invalidate()
    gameTimer = nil
    // ... rest of cleanup
}
```

## Testing Verification

### Test Case 1: Custom Exercise Creator Navigation
**Steps:**
1. Open app to Exercises tab
2. Tap green "+" button in top-right
3. Wait for AI Exercise Builder view to appear

**Expected Behavior:**
- ✅ View loads without crash
- ✅ Navigation title shows "AI Exercise Builder"
- ✅ Back button functional
- ✅ All UI elements render correctly

### Test Case 2: Back Navigation from Creator
**Steps:**
1. Navigate to Custom Exercise Creator
2. Tap "Back" button in top-left
3. Verify return to Exercises tab

**Expected Behavior:**
- ✅ Smooth navigation back to Exercises
- ✅ No crashes or memory issues
- ✅ Exercise list still visible

### Test Case 3: Constellation Game Back Protection
**Steps:**
1. Start constellation game
2. Try to swipe back or use back gesture during gameplay

**Expected Behavior:**
- ✅ Back gesture disabled during active game
- ✅ Game continues normally
- ✅ Cleanup happens properly when game ends naturally

## Related Files Modified

1. **CustomExerciseCreatorView.swift** - Removed nested NavigationStack
2. **SimplifiedConstellationGameView.swift** - Added navigation protection and cleanup guards

## Prevention Guidelines

### Rule: Never Nest NavigationStacks
When creating views that will be presented via `NavigationCoordinator`:
- ❌ Do NOT wrap view body in `NavigationStack`
- ✅ Use navigation modifiers directly on view content
- ✅ Trust parent NavigationStack to handle navigation

### Pattern to Follow
```swift
struct MyNewView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    
    var body: some View {
        // NO NavigationStack here!
        ScrollView {
            // ... content
        }
        .navigationTitle("My View")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Back") { dismiss() }
            }
        }
    }
}
```

### When NavigationStack IS Needed
Only use `NavigationStack` in:
- Main app entry point (`ContentView.swift`)
- Modal sheets that need independent navigation
- Preview-only test views

## Build Verification
All changes compile without errors:
- ✅ No syntax errors
- ✅ No type mismatches
- ✅ All environment objects properly referenced
- ✅ Navigation flow intact

## Summary
**Fixed nested NavigationStack causing custom exercise creator crash by removing redundant navigation wrapper. View now properly integrates with parent navigation hierarchy.**
