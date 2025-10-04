import Foundation
import UIKit

/// Utility to map Vision 480x640 reference coordinates into the app's preview / screen space.
/// Handles aspect-fill scaling (center-crop) which is used by the preview layer so points
/// produced in the fixed reference space land correctly on the displayed camera view.
/// CRITICAL: Phone is held VERTICALLY, camera is front-facing with mirroring.
struct CoordinateMapper {
    /// Map a point expressed in the reference space (default 480x640) into screen coordinates
    /// taking into account aspect-fill scaling and center cropping.
    /// PHONE ORIENTATION: Vertical (portrait) - 390x844 screen typical
    /// CAMERA ORIENTATION: Front camera captures 640x480 (landscape), mirrored horizontally
    /// - Parameters:
    ///   - point: Point in reference space (x: 0..referenceWidth, y: 0..referenceHeight)
    ///   - referenceSize: The canonical vision reference size (default 480x640)
    ///   - previewSize: The size of the preview view (typically UIScreen.main.bounds - portrait)
    /// - Returns: CGPoint in preview/screen coordinates (clamped to preview bounds)
    static func mapVisionPointToScreen(_ point: CGPoint,
                                       referenceSize: CGSize = CGSize(width: 480, height: 640),
                                       previewSize: CGSize = UIScreen.main.bounds.size) -> CGPoint {
        guard referenceSize.width > 0 && referenceSize.height > 0 else { return .zero }

        // CRITICAL FIX: Vision coordinates come in 640x480 (landscape) but phone is vertical (portrait)
        // The camera feed is rotated 90° to fill the portrait screen
        // Vision X (0-640) maps to screen Y (top to bottom) BUT MUST BE INVERTED
        // Vision Y (0-480) maps to screen X (left to right), MIRRORED for front camera
        
        // Mirror horizontally for front-facing camera (left hand appears on right side)
        let mirroredX = referenceSize.width - point.x
        
        // Rotate 90° clockwise to match portrait orientation
        // Vision's X (horizontal in landscape) becomes screen's Y (vertical in portrait)
        // Vision's Y (vertical in landscape) becomes screen's X (horizontal in portrait)
        // CRITICAL: Invert Y so hand UP (small Vision X) = pin UP (small screen Y)
        let rotatedX = point.y  // Vision Y → Screen X (mirrored handles left/right)
        let rotatedY = referenceSize.width - mirroredX  // INVERTED: Hand up = pin up
        
        // Now map with rotated reference dimensions (swap width/height for rotation)
        let rotatedRefWidth = referenceSize.height  // 640
        let rotatedRefHeight = referenceSize.width   // 480
        
        // Determine aspect-fill scale
        let scaleX = previewSize.width / rotatedRefWidth
        let scaleY = previewSize.height / rotatedRefHeight
        let scale = max(scaleX, scaleY)

        // Size of the scaled image that is center-cropped to fill the preview
        let imageWidth = rotatedRefWidth * scale
        let imageHeight = rotatedRefHeight * scale

        // Offset of the image's origin relative to the preview (center crop)
        let offsetX = (imageWidth - previewSize.width) / 2.0
        let offsetY = (imageHeight - previewSize.height) / 2.0

        // Scale the rotated point
        let scaledX = rotatedX * scale
        let scaledY = rotatedY * scale

        // Translate into preview coordinates by subtracting the crop offset
        var previewX = scaledX - offsetX
        var previewY = scaledY - offsetY

        // Clamp to preview bounds to avoid off-screen UI coordinates
        previewX = max(0, min(previewX, previewSize.width))
        previewY = max(0, min(previewY, previewSize.height))

        return CGPoint(x: previewX, y: previewY)
    }
}
