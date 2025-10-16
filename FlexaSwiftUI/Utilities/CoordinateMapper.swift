import Foundation
import UIKit

/// Utility to map Vision normalized coordinates into the app's preview / screen space.
/// COORDINATE SYSTEM EXPLANATION:
/// 1. Vision (BlazePose) returns (0-1) normalized coords in CAMERA FRAME (landscape: 1920x1080)
/// 2. Phone screen is PORTRAIT: 390x844
/// 3. Preview layer uses resizeAspectFill - scales to fill while maintaining aspect ratio
/// 4. Must rotate 90° AND handle front camera mirror AND account for scaling/centering
struct CoordinateMapper {
    
    static func mapVisionPointToScreen(
        _ point: CGPoint,
        cameraResolution: CGSize,
        previewSize: CGSize
    ) -> CGPoint {
        
        // DEFENSIVE CHECKS
        guard cameraResolution.width > 0, cameraResolution.height > 0 else {
            return .zero
        }
        
        guard previewSize.width > 0, previewSize.height > 0 else {
            return .zero
        }
        
        guard !point.x.isNaN, !point.x.isInfinite, !point.y.isNaN, !point.y.isInfinite else {
            return .zero
        }
        
        // VISION IS ALREADY IN PORTRAIT SPACE
        // The system automatically rotates Vision output to match screen orientation
        // So Vision coordinates (0-1) are already in portrait space, NOT landscape!
        // Example: Vision x=0.5 = 50% across portrait WIDTH (390px)
        //          Vision y=0.5 = 50% down portrait HEIGHT (844px)
        
        // STEP 1: Un-normalize Vision coords directly to screen space
        // Vision coordinates are already normalized (0-1 range) and already mirrored for front camera
        // NO rotation needed - Vision is already portrait!
        let screenX = point.x * previewSize.width
        let screenY = point.y * previewSize.height
        
        // STEP 2: Clamp to screen bounds (allows off-screen coordinates)
        // Note: Mirror is already applied in MediaPipePoseProvider.getNormalizedMirroredPoint()
        let finalX = max(0, min(previewSize.width, screenX))
        let finalY = max(0, min(previewSize.height, screenY))
        
        FlexaLog.game.debug("🎯 [COORDS-DEEP] vision(\(String(format: "%.3f", point.x)), \(String(format: "%.3f", point.y))) -> screen(\(String(format: "%.1f", finalX)), \(String(format: "%.1f", finalY)))")
        
        return CGPoint(x: finalX, y: finalY)
    }
}
