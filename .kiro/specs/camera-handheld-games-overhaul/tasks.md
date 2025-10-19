# Implementation Plan

- [x] 1. Fix Core Coordinate Mapping
  - Remove incorrect rotation and scaling logic from CoordinateMapper
  - MediaPipe already provides portrait-oriented, mirrored coordinates
  - Implement direct normalized-to-screen mapping
  - Add defensive checks for NaN, Inf, and zero dimensions
  - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5_

- [x] 2. Enhance Handheld ROM Calculator with 2D Plane Projection
  - [x] 2.1 Implement 2D plane selection algorithm
    - Calculate variance for X, Y, Z axes
    - Select plane with highest motion variance (XY, XZ, or YZ)
    - _Requirements: 9.1, 9.2, 9.3_
  
  - [x] 2.2 Implement 2D plane projection
    - Project 3D points onto selected 2D plane
    - Calculate arc length in 2D space
    - _Requirements: 9.3, 9.4_
  
  - [x] 2.3 Fix ROM calculation formulas
    - Pendulum: ROM = (arcLength / armLength) * (180 / π)
    - Circular: ROM = arcsin(radius / armLength) * (180 / π)
    - _Requirements: 1.4, 1.5, 1.6, 2.3, 2.4, 3.4, 3.5, 3.6_
  
  - [x] 2.4 Implement baseline reset after rep completion
    - Reset currentRepPositions array
    - Reset baselinePosition to nil
    - Reset repBaselinePosition to nil
    - Reset currentROM to 0.0
    - _Requirements: 1.7, 1.8, 2.5, 3.7, 10.1, 10.2, 10.3, 10.4, 10.5_

- [x] 3. Fix Handheld Rep Detection Algorithms
  - [x] 3.1 Implement direction change detection for Fruit Slicer
    - Calculate displacement vector between positions
    - Normalize to get direction vector
    - Compare with last direction using dot product
    - Detect change when dot product < -0.2
    - Enforce 0.3s cooldown between reps
    - _Requirements: 1.1, 1.2_
  
  - [x] 3.2 Implement direction change detection for Fan the Flame
    - Same algorithm as Fruit Slicer
    - Left fan = 1 rep, right fan = 1 rep
    - _Requirements: 3.1, 3.2_
  
  - [x] 3.3 Implement circle completion detection for Follow Circle
    - Establish circle center using moving average
    - Calculate angle from center for each position
    - Accumulate angle changes
    - Detect completion when accumulated angle >= 2π
    - Enforce 0.4s cooldown
    - _Requirements: 2.1, 2.6_

- [x] 4. Fix Camera ROM Calculation
  - [x] 4.1 Fix shoulder angle calculation for Wall Climbers
    - Calculate vector from shoulder to hip to elbow
    - Calculate angle from vertical (screen Y-axis)
    - Return absolute angle in degrees
    - _Requirements: 5.3, 5.4_
  
  - [x] 4.2 Fix shoulder angle calculation for Constellation
    - Same algorithm as Wall Climbers
    - Use 3-point angle calculation
    - _Requirements: 6.5_
  
  - [x] 4.3 Fix elbow angle calculation for Elbow Extension
    - Calculate upper arm vector (shoulder → elbow)
    - Calculate forearm vector (elbow → wrist)
    - Calculate angle between vectors using dot product
    - Return angle in degrees (0° = bent, 180° = extended)
    - _Requirements: 7.4_

- [x] 5. Fix Camera Rep Detection Algorithms
  - [x] 5.1 Implement upward motion detection for Wall Climbers
    - Track wrist Y position in screen pixels
    - Detect upward movement (deltaY < -threshold)
    - Enter "goingUp" phase, track peak Y position
    - Detect downward movement (deltaY > threshold)
    - Calculate distance traveled (startY - peakY)
    - Count rep if distance >= minimum (100px)
    - Record peak ROM angle
    - _Requirements: 5.1, 5.2, 5.5, 5.6, 5.7, 5.8_
  
  - [x] 5.2 Implement dot connection validation for Constellation
    - Triangle: allow any unconnected point, must close loop at end
    - Rectangle: only allow adjacent connections (no diagonals)
    - Circle: only allow left/right adjacent connections
    - Show "incorrect" feedback for invalid connections
    - Reset progress for that constellation on error
    - _Requirements: 6.1, 6.2, 6.3, 6.6, 6.7, 6.8, 6.9, 6.10, 6.11, 6.12_
  
  - [x] 5.3 Implement extension cycle detection for Elbow Extension
    - Track elbow angle continuously
    - Detect extension start (angle > 140°)
    - Track peak extension angle
    - Detect flexion return (angle < 90°)
    - Calculate ROM (peak - start)
    - Count rep if ROM >= threshold
    - _Requirements: 7.1, 7.2, 7.3, 7.9_

- [x] 6. Implement Gameplay Mechanics for Handheld Games
  - [x] 6.1 Update Fruit Slicer gameplay
    - Fruits spawn from edges toward center
    - Slicer follows IMU tilt (up/down motion)
    - Collision detection between slicer and fruits
    - Bombs end game after 3 hits
    - Score based on fruits sliced
    - Direction-based rep counting
    - _Requirements: 1.1, 1.2_
  
  - [x] 6.2 Update Follow Circle gameplay
    - White guide circle orbits in circular path
    - Green cursor follows ARKit 3D position
    - Score increases while touching guide circle
    - Streak multiplier for consecutive touches
    - Game ends after 2 minutes or losing contact
    - Circle completion rep counting
    - _Requirements: 2.1_
  
  - [x] 6.3 Update Fan the Flame gameplay
    - Animated flame with intensity meter
    - Each rep reduces flame intensity
    - Hand animation follows motion
    - Game ends when flame extinguished or 2 minutes
    - Direction-based rep counting
    - _Requirements: 3.1, 3.2_

- [x] 7. Implement Gameplay Mechanics for Camera Games
  - [x] 7.1 Update Wall Climbers gameplay
    - Vertical altitude meter on right side
    - Altitude increases with each rep
    - Altitude gain proportional to distance traveled
    - Game ends when altitude meter full
    - Upward motion rep counting
    - _Requirements: 5.1, 5.6, 5.7_
  
  - [x] 7.2 Update Constellation gameplay
    - Pattern 1: Triangle (3 dots, any start, must close loop)
    - Pattern 2: Rectangle (4 dots, no diagonals)
    - Pattern 3: Circle (8 dots, only adjacent)
    - Cyan circle follows hand position
    - Line draws from selected dot to hand
    - "Incorrect" feedback for invalid connections
    - Game ends after completing all 3 patterns
    - _Requirements: 6.1, 6.2, 6.3, 6.6, 6.7, 6.8, 6.9, 6.10, 6.11, 6.12_
  
  - [x] 7.3 Update Elbow Extension (Balloon Pop) gameplay
    - Balloons spawn at top of screen
    - Pin/dart follows wrist position
    - Collision detection between pin and balloons
    - One balloon at a time (spawns after pop)
    - 60-second timer (background, not displayed)
    - Score based on balloons popped
    - Extension cycle rep counting
    - _Requirements: 7.1, 7.2, 7.5, 7.6, 7.7, 7.8, 7.9_

- [x] 8. Enhance SPARC Smoothness Analysis
  - [x] 8.1 Add ARKit position input for handheld games
    - Feed ARKit 3D positions to SPARC service
    - Calculate smoothness from continuous trajectory
    - _Requirements: 4.1, 4.2_
  
  - [x] 8.2 Add wrist position input for camera games
    - Feed wrist screen positions to SPARC service
    - Calculate smoothness from 2D trajectory
    - _Requirements: 4.1, 4.2_
  
  - [x] 8.3 Fix smoothness graph rendering
    - Display as curved line representing movement quality
    - Remove repetitive up-and-down patterns
    - Show average smoothness over time
    - _Requirements: 4.3, 4.4, 4.5_

- [ ] 9. Add Error Handling and Validation
  - [ ] 9.1 Add ARKit tracking loss handling
    - Detect when ARKit stops providing transforms
    - Fallback to IMU-only mode for rep detection
    - Disable ROM calculation (requires ARKit)
    - Show warning overlay to user
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5_
  
  - [ ] 9.2 Add pose detection failure handling
    - Handle missing landmarks gracefully
    - Hide hand cursor when landmarks unavailable
    - Validate landmark confidence (threshold 0.5)
    - Ignore low-confidence landmarks
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5_
  
  - [ ] 9.3 Add ROM validation
    - Check ROM > 0 and ROM <= 360
    - Check ROM is finite (not NaN or Inf)
    - Reject invalid ROM values
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5_

- [ ]* 10. Write integration tests for game flows
  - Test Fruit Slicer: forward/backward swings count as separate reps
  - Test Follow Circle: complete circles count as reps
  - Test Fan Flame: left/right fans count as separate reps
  - Test Wall Climbers: upward arm raises count as reps
  - Test Constellation: pattern validation rules
  - Test Elbow Extension: extension cycles count as reps
  - Verify ROM doesn't accumulate across reps
  - Verify baseline resets after each rep
  - _Requirements: All requirements_
