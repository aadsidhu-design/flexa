Handheld ROM & Rep Cleanup

Summary:
- ARKit is now the canonical source of ROM for all handheld games (Fruit Slicer, Fan the Flame, Follow Circle, etc.).
- HandheldROMCalculator processes ARKit positions for all motion profiles including pendulum.
- IMU/Gyro is retained for low-latency rep detection for pendulum-style games (Fruit Slicer, Fan the Flame) and acts as a fallback for ROM when ARKit is unavailable.
 - Gyro-based rep detection now schedules ARKit-based rep completion to compute ROM. IMU-derived ROM is deprecated and will no longer be used.

Implementation Notes:
- HandheldROMCalculator: removed pendulum short-circuit so ARKit positions are processed for pendulum.
 - Fan the Flame uses pendulum-style arc ROM calculation in ARKit via HandheldROMCalculator (motionProfile = .pendulum).
- SimpleMotionService: GyroRepROMStateMachine.onRepDetected now increments rep counts immediately and schedules HandheldROMCalculator.completeRep() after a short (120ms) delay when ARKit tracking is normal.
- SPARC continues to be driven by ARKit positions for handheld games.

Testing / Validation:
- Build passed after changes. Unit/integration tests are mostly disabled in Tests.disabled; consider updating tests to reflect ARKit-first behavior if re-enabling.

Next Steps:
- Enable HandheldRepDetector for more games if desired (FollowCircle uses ARKit already).
- Deprecate IMU-only ROM code and add compatibility shims in SPARCCompatibility.swift if needed.
- Update telemetry to record which pipeline (ARKit vs IMU) produced rep ROM for analytics.
