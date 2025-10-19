# Requirements Document

## Introduction

This specification addresses a comprehensive overhaul of the camera-based and handheld game systems in the Flexa iOS application. The current implementation has critical issues with rep detection, ROM calculation, coordinate mapping, gameplay mechanics, and smoothness analysis. This overhaul will establish correct motion tracking, accurate ROM measurements, proper rep detection algorithms, and engaging gameplay mechanics for all six built-in exercise games.

## Glossary

- **ROM (Range of Motion)**: The angular measurement of movement during an exercise, measured in degrees
- **Rep (Repetition)**: A single complete cycle of an exercise movement
- **ARKit Tracker**: Apple's augmented reality framework used for 3D position tracking of the handheld device
- **MediaPipe Pose Provider**: Google's pose detection library used for camera-based body landmark detection
- **SPARC (Smoothness)**: Spectral Arc Length metric measuring movement quality and fluidity
- **Handheld Game**: Exercise game where the user holds the iPhone and moves it through space
- **Camera Game**: Exercise game where the iPhone is stationary and tracks the user's body via camera
- **Direction Change**: A reversal in movement direction used as a rep detection trigger
- **2D Plane Projection**: Mathematical reduction of 3D motion data to the best-fit 2D plane (XY, XZ, or YZ)
- **Arm Length**: User's calibrated arm length used for ROM angle calculations
- **Landmark**: A specific body point detected by MediaPipe (e.g., wrist, elbow, shoulder)
- **Altitude Meter**: Visual progress indicator in Wall Climbers showing vertical progress
- **Constellation Dot**: Interactive target point in the Constellation game that users connect

## Requirements

### Requirement 1: Handheld Fruit Slicer Game

**User Story:** As a physical therapy patient, I want to play Fruit Slicer by swinging my phone forward and backward, so that each directional swing counts as a rep with accurate ROM measurement.

#### Acceptance Criteria

1. WHEN the user swings the phone forward, THE Handheld_Rep_Detector SHALL register one repetition
2. WHEN the user swings the phone backward, THE Handheld_Rep_Detector SHALL register one repetition
3. WHILE tracking motion, THE ARKit_Tracker SHALL capture the complete 3D position trajectory
4. WHEN a rep is detected, THE ROM_Calculator SHALL project the 3D arc to the best-fit 2D plane among XY, XZ, or YZ
5. WHEN the 2D projection is complete, THE ROM_Calculator SHALL calculate arc length from the trajectory
6. WHEN arc length is determined, THE ROM_Calculator SHALL compute the ROM angle using arc length divided by arm length
7. WHEN a rep is completed, THE ROM_Tracker SHALL reset the baseline position for the next rep
8. THE Fruit_Slicer_Game SHALL NOT accumulate ROM across multiple reps

### Requirement 2: Handheld Follow Circle Game

**User Story:** As a physical therapy patient, I want to play Follow Circle by tracing circular motions with my phone, so that each complete circle counts as a rep with radius-based ROM measurement.

#### Acceptance Criteria

1. WHEN the user completes one full circular motion, THE Handheld_Rep_Detector SHALL register one repetition
2. WHILE tracking circular motion, THE ARKit_Tracker SHALL capture the complete 3D circular trajectory
3. WHEN a circle is completed, THE ROM_Calculator SHALL determine the largest radius of the circular path
4. WHEN the radius is determined, THE ROM_Calculator SHALL compute the ROM angle using the radius and arm length as triangle legs
5. WHEN a rep is completed, THE ROM_Tracker SHALL reset the baseline position for the next rep
6. THE Follow_Circle_Game SHALL detect circle completion based on path closure within tolerance

### Requirement 3: Handheld Fan the Flame Game

**User Story:** As a physical therapy patient, I want to play Fan the Flame by making fanning motions with my phone, so that each directional fan counts as a rep with accurate ROM measurement.

#### Acceptance Criteria

1. WHEN the user fans to the left, THE Handheld_Rep_Detector SHALL register one repetition
2. WHEN the user fans to the right, THE Handheld_Rep_Detector SHALL register one repetition
3. WHILE tracking fanning motion, THE ARKit_Tracker SHALL capture the complete 3D position trajectory
4. WHEN a rep is detected, THE ROM_Calculator SHALL project the 3D arc to the best-fit 2D plane among XY, XZ, or YZ
5. WHEN the 2D projection is complete, THE ROM_Calculator SHALL calculate arc length from the trajectory
6. WHEN arc length is determined, THE ROM_Calculator SHALL compute the ROM angle using arc length divided by arm length
7. WHEN a rep is completed, THE ROM_Tracker SHALL reset the baseline position for the next rep

### Requirement 4: Handheld Games Smoothness Analysis

**User Story:** As a physical therapy patient, I want my movement smoothness to be accurately measured during handheld games, so that I receive meaningful feedback on my movement quality.

#### Acceptance Criteria

1. WHILE tracking handheld motion, THE Smoothness_Analyzer SHALL use ARKit position data as input
2. WHEN calculating smoothness, THE Smoothness_Analyzer SHALL compute an average smoothness metric across the session
3. WHEN displaying smoothness, THE Smoothness_Graph SHALL render a curved line representing movement quality over time
4. THE Smoothness_Graph SHALL NOT display repetitive up-and-down patterns
5. THE Smoothness_Analyzer SHALL base calculations on the continuous trajectory curve

### Requirement 5: Camera Wall Climbers Game

**User Story:** As a physical therapy patient, I want to play Wall Climbers by raising my arms upward, so that each upward movement counts as a rep and fills an altitude meter.

#### Acceptance Criteria

1. WHEN the user raises their arm upward, THE Camera_Rep_Detector SHALL register one repetition upon downward return
2. WHILE tracking arm position, THE MediaPipe_Pose_Provider SHALL detect shoulder, elbow, and wrist landmarks
3. WHEN calculating ROM, THE ROM_Calculator SHALL compute the shoulder angle using three-point angle calculation
4. WHEN a rep is in progress, THE ROM_Tracker SHALL track the peak shoulder angle as the ROM for that rep
5. WHEN the user lowers their arm, THE Camera_Rep_Detector SHALL complete the rep and record the peak ROM
6. WHEN a rep is completed, THE Altitude_Meter SHALL increase by one increment
7. WHEN the altitude meter is full, THE Wall_Climbers_Game SHALL end the session
8. THE Wall_Climbers_Game SHALL track reps based on wrist position changes

### Requirement 6: Camera Constellation Game

**User Story:** As a physical therapy patient, I want to play Constellation by connecting dots with my hand movements, so that I complete three constellation patterns with accurate ROM tracking.

#### Acceptance Criteria

1. WHEN the user's hand circle collides with a constellation dot, THE Constellation_Game SHALL select that dot
2. WHEN a dot is selected, THE Constellation_Game SHALL draw a line from the dot to the user's hand circle
3. WHEN the user moves to another valid dot, THE Constellation_Game SHALL connect the dots
4. WHILE tracking arm position, THE MediaPipe_Pose_Provider SHALL detect shoulder, elbow, and wrist landmarks
5. WHEN calculating ROM, THE ROM_Calculator SHALL compute the shoulder angle using three-point angle calculation
6. WHERE the constellation is a triangle, THE Constellation_Game SHALL allow the user to start at any point
7. WHERE the constellation is a triangle, THE Constellation_Game SHALL require connection back to the starting point for completion
8. WHERE the constellation is a rectangle, THE Constellation_Game SHALL prevent diagonal connections
9. IF the user attempts a diagonal connection on the rectangle, THEN THE Constellation_Game SHALL display "incorrect" and reset progress for that constellation
10. WHERE the constellation is a circle, THE Constellation_Game SHALL only allow connections to adjacent left or right points
11. WHEN all three constellations are completed, THE Constellation_Game SHALL end the session
12. THE Constellation_Game SHALL NOT have a time limit

### Requirement 7: Camera Elbow Extension Game

**User Story:** As a physical therapy patient, I want to play Elbow Extension by extending my arm to pop balloons, so that each extension counts as a rep within a 60-second time limit.

#### Acceptance Criteria

1. WHEN the user extends their elbow upward, THE Camera_Rep_Detector SHALL register one repetition
2. WHEN the user lowers their arm, THE Camera_Rep_Detector SHALL NOT register a repetition
3. WHILE tracking arm position, THE MediaPipe_Pose_Provider SHALL detect shoulder, elbow, and wrist landmarks
4. WHEN calculating ROM, THE ROM_Calculator SHALL compute the elbow angle using three-point angle calculation
5. WHEN the user's hand pin collides with a balloon, THE Elbow_Extension_Game SHALL pop the balloon
6. WHEN a balloon is popped, THE Elbow_Extension_Game SHALL spawn a new balloon at the top of the screen
7. WHEN the game starts, THE Elbow_Extension_Game SHALL initialize a 60-second countdown timer
8. WHEN 60 seconds elapse, THE Elbow_Extension_Game SHALL end the session
9. THE Elbow_Extension_Game SHALL track the hand pin position following the user's wrist landmark

### Requirement 8: MediaPipe Coordinate Mapping

**User Story:** As a developer, I want MediaPipe pose landmarks to be correctly mapped to screen coordinates, so that camera games accurately track body positions.

#### Acceptance Criteria

1. WHEN MediaPipe detects a landmark, THE Coordinate_Mapper SHALL transform the landmark to screen coordinates
2. WHEN transforming coordinates, THE Coordinate_Mapper SHALL account for camera orientation and device rotation
3. WHEN transforming coordinates, THE Coordinate_Mapper SHALL normalize coordinates to the screen dimensions
4. THE Coordinate_Mapper SHALL ensure wrist, elbow, and shoulder landmarks align with visual body positions
5. THE Coordinate_Mapper SHALL apply consistent coordinate transformations across all camera games

### Requirement 9: ARKit 2D Plane Projection

**User Story:** As a developer, I want 3D ARKit trajectories to be projected onto the optimal 2D plane, so that ROM calculations minimize bias from wrist rotation and other artifacts.

#### Acceptance Criteria

1. WHEN a 3D trajectory is captured, THE Plane_Projector SHALL evaluate variance in XY, XZ, and YZ planes
2. WHEN evaluating planes, THE Plane_Projector SHALL select the plane with the highest motion variance
3. WHEN the optimal plane is selected, THE Plane_Projector SHALL project all 3D points onto that 2D plane
4. THE Plane_Projector SHALL minimize bias from wrist rotation and secondary movements
5. THE Plane_Projector SHALL provide the 2D trajectory to the ROM calculator

### Requirement 10: Rep Detection Baseline Reset

**User Story:** As a developer, I want ROM tracking to reset after each rep detection, so that ROM values do not accumulate across multiple reps.

#### Acceptance Criteria

1. WHEN a rep is detected, THE ROM_Tracker SHALL reset the baseline position
2. WHEN the baseline is reset, THE ROM_Tracker SHALL begin tracking from the new starting position
3. WHEN tracking a new rep, THE ROM_Tracker SHALL NOT include position data from previous reps
4. THE ROM_Tracker SHALL maintain independent ROM measurements for each rep
5. THE ROM_Tracker SHALL prevent ROM accumulation across rep boundaries
