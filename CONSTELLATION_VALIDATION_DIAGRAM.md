# Constellation Validation Logic Diagram

## Overview
This document visualizes the smart validation rules for each constellation pattern in the Arm Raises game.

---

## 🔺 TRIANGLE PATTERN

### Rules:
- ✅ Start from ANY vertex (0, 1, or 2)
- ✅ Connect to ANY unvisited vertex
- ✅ Must return to START to complete
- ❌ Cannot revisit already-connected vertices

### Valid Examples:

```
Example 1: Start at 0
    0* ← START
   / \
  1---2

Path: 0 → 1 → 2 → 0 ✅
```

```
Example 2: Start at 1
    0
   / \
  1*--2 ← START at 1

Path: 1 → 0 → 2 → 1 ✅
Path: 1 → 2 → 0 → 1 ✅
```

### Invalid Example:

```
    0* ← START
   / 
  1   2

Path: 0 → 1 → 2 (STOP) ❌
Reason: Did not return to start (0)
```

---

## ⬜ SQUARE PATTERN

### Rules:
- ✅ Start from ANY corner (0, 1, 2, or 3)
- ✅ Must follow EDGES ONLY
- ❌ NO DIAGONAL connections allowed
- ✅ Must return to START to complete

### Layout:
```
  0-------1
  |       |
  |       |
  3-------2
```

### Valid Edges:
```
✅ 0 ↔ 1  (top edge)
✅ 1 ↔ 2  (right edge)
✅ 2 ↔ 3  (bottom edge)
✅ 3 ↔ 0  (left edge)
```

### Invalid Diagonals:
```
❌ 0 ↔ 2  (diagonal)
❌ 1 ↔ 3  (diagonal)
```

### Valid Example:

```
  0*------1
  |       |
  |       |
  3-------2

Path: 0 → 1 → 2 → 3 → 0 ✅
```

### Invalid Example:

```
  0*------1
   \     /
    \   /
     \ /
  3---2

Path: 0 → 2 ❌
Reason: DIAGONAL not allowed! Shows "Incorrect" → RESET
```

---

## ⭕ CIRCLE PATTERN (8 points)

### Rules:
- ✅ Start from ANY dot (0-7)
- ✅ Can ONLY connect to immediate LEFT or RIGHT neighbor (±1)
- ❌ Cannot skip dots
- ❌ Cannot jump across the circle
- ✅ Must complete full circle

### Layout:
```
        0
    7       1
  6           2
    5       3
        4
```

### Neighbor Map:
```
Point 0: ✅ 7 (left)  ✅ 1 (right)
Point 1: ✅ 0 (left)  ✅ 2 (right)
Point 2: ✅ 1 (left)  ✅ 3 (right)
Point 3: ✅ 2 (left)  ✅ 4 (right)
Point 4: ✅ 3 (left)  ✅ 5 (right)
Point 5: ✅ 4 (left)  ✅ 6 (right)
Point 6: ✅ 5 (left)  ✅ 7 (right)
Point 7: ✅ 6 (left)  ✅ 0 (right) [wraps around]
```

### Valid Example:

```
        0* ← START
    7       1
  6           2
    5       3
        4

Path: 0 → 1 → 2 → 3 → 4 → 5 → 6 → 7 → 0 ✅
(Clockwise around circle)
```

### Invalid Example:

```
        0* ← START
    7   ↓   1
  6     ↓     2
    5   ↓   3
        4

Path: 0 → 4 ❌
Reason: Skipped 1, 2, 3! Shows "Incorrect" → RESET
```

---

## 🔄 ERROR HANDLING FLOW

```
User attempts connection
        ↓
   Validate connection
        ↓
    ┌───┴───┐
    ↓       ↓
  Valid   Invalid
    ↓       ↓
Accept  Show "Incorrect"
  dot       ↓
   ↓    Play error haptic
Turn        ↓
green   Wait 0.5s
   ↓        ↓
Draw    RESET pattern
line        ↓
   ↓    Clear all dots
Continue    ↓
          Start over
```

---

## 💡 COMPLETION LOGIC

### Pattern Completion Steps:

```
1. User connects to a dot
   ↓
2. Check: Is this the START dot?
   ↓
3. If YES: Are ALL other dots connected?
   ↓
4. If YES: PATTERN COMPLETE! 🎉
   ↓
5. Play success haptic
   ↓
6. Award points (+100)
   ↓
7. Generate next pattern
```

### Visual Example (Triangle):

```
Step 1: Connect first dot
    0* [GREEN]
   / 
  1   2 [WHITE]

Step 2: Connect second dot
    0* [GREEN]
   / \
  1   2 [GREEN]
  [GREEN]

Step 3: Return to start
    0* [GREEN] ← Back here!
   /█\ [COMPLETE]
  1███2 [GREEN]

✅ Pattern complete!
```

---

## 🎯 VALIDATION FUNCTION LOGIC

```swift
func isValidConnection(from: Int, to: Int) -> Bool {
    switch currentPatternName {
    case "Triangle":
        // Any unvisited point is valid
        return !connectedPoints.contains(to)
        
    case "Square":
        // Only edges allowed, no diagonals
        let validPairs: Set<Set<Int>> = [
            [0, 1], [1, 2], [2, 3], [3, 0]
        ]
        return validPairs.contains([from, to])
        
    case "Circle":
        // Only immediate neighbors (±1 modulo 8)
        let numPoints = 8
        let leftNeighbor = (from - 1 + numPoints) % numPoints
        let rightNeighbor = (from + 1) % numPoints
        return to == leftNeighbor || to == rightNeighbor
    }
}
```

---

## 🧠 STATE TRACKING

### State Variables:

```
connectedPoints: [Int]
  - Array of dot indices that have been connected
  - Example: [0, 1, 2] means dots 0, 1, 2 are green

patternStartIndex: Int?
  - Remembers which dot user started at
  - Used for closure detection
  - Example: If started at dot 1, this = 1

activeLineStartIndex: Int?
  - Last connected dot
  - Used for drawing live line to hand

activeLineEndIndex: Int?
  - Next target dot
  - Used when moving between dots
```

### State Flow Example:

```
INITIAL STATE:
connectedPoints = []
patternStartIndex = nil
activeLineStartIndex = nil

USER TOUCHES DOT 1:
connectedPoints = [1]
patternStartIndex = 1
activeLineStartIndex = 1

USER TOUCHES DOT 2:
connectedPoints = [1, 2]
patternStartIndex = 1 (unchanged)
activeLineStartIndex = 2

USER TOUCHES DOT 0:
connectedPoints = [1, 2, 0]
patternStartIndex = 1 (unchanged)
activeLineStartIndex = 0

USER RETURNS TO DOT 1:
Check: to == patternStartIndex? YES!
Check: all dots connected? YES!
→ COMPLETE! 🎉
```

---

## 📊 DECISION TREE

```
Connection Attempt
    ↓
Is connectedPoints empty?
    ↓ YES
    ↓ NO
    ↓
Set start point
Accept any dot
    ↓
    ↓ NO (already started)
    ↓
Is target already connected?
    ↓ YES
    ↓ NO
    ↓
Is target the start point?
  AND all others connected?
    ↓ YES → COMPLETE! 🎉
    ↓ NO
    ↓
    ↓ NO (target is unvisited)
    ↓
Validate shape rules
    ↓
    ├─ Valid? → Accept + turn green
    └─ Invalid? → Show error + reset
```

---

## 🎨 VISUAL FEEDBACK

### Dot Colors:
```
WHITE (○)   = Unvisited, available
GREEN (●)   = Connected, part of path
CYAN (◉)    = Target dot (with glow)
```

### Line Types:
```
CYAN SOLID (━━━)      = Completed connection
CYAN DASHED (┄┄┄)     = Live line (hand to next dot)
```

### Animations:
```
Dot selected:
  WHITE ○ → scale 1.0
          ↓
  GREEN ● → scale 1.3
          ↓ (0.2s ease)
  GREEN ● → scale 1.0

Incorrect connection:
  Show "Incorrect" overlay (red)
          ↓
  Play error haptic (bzzt)
          ↓
  Wait 0.5s
          ↓
  Clear all dots → WHITE
          ↓
  Reset state
```

---

## 🔧 DEBUGGING TIPS

### Check Console Logs:

```
🌟 [ArmRaises] Starting constellation from dot #N
  → User picked starting point N

✅ [ArmRaises] Connected to dot #N
  → Valid connection accepted

❌ [ArmRaises] Incorrect connection detected
  → Validation failed, resetting

🌟 [ArmRaises] Pattern COMPLETED! All dots connected.
  → User successfully closed the pattern

🔄 [ArmRaises] Pattern reset - start again!
  → User must retry after error
```

---

## ✅ TESTING CHECKLIST

- [ ] Triangle: Try all 3 starting points
- [ ] Triangle: Verify closure required
- [ ] Square: Attempt all 4 possible diagonals (should fail)
- [ ] Square: Follow edges successfully
- [ ] Circle: Try skipping a dot (should fail)
- [ ] Circle: Go clockwise full circle
- [ ] Circle: Go counter-clockwise full circle
- [ ] All patterns: Verify dots never move position
- [ ] All patterns: Verify green color change
- [ ] All patterns: Verify lines persist

---

**End of Validation Diagram** 🎯