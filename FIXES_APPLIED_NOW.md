FollowCircle centering and compile fixes (2025-10-18)

- Fix: ARKit -> screen Y mapping in `FollowCircleGameView.swift`: use ARKit Y (relY) and negate for screen mapping so forward hand moves cursor UP.
- Fix: OSLog interpolation issue for `CGSize` in `FollowCircleGameView.swift` by formatting width/height.
- Fix: Safely compute neckPoint in `MediaPipePoseProvider.swift` by unwrapping optional shoulder points.

Build: Verified clean `xcodebuild` for generic iOS target.
