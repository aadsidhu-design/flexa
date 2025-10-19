import Foundation
import UIKit

/// Utility to map MediaPipe normalized coordinates to screen space.
///
/// MediaPipe provides coordinates that are:
/// - Already in portrait orientation (matching device screen)
/// - Already mirrored for front camera (handled in MediaPipePoseProvider)
/// - Normalized to 0-1 range
///
/// This mapper performs direct normalized-to-screen conversion with defensive validation.
struct CoordinateMapper {
    
    /// Maps a normalized MediaPipe point (0-1) to screen pixel coordinates.
    ///
    /// - Parameters:
    ///   - point: Normalized point from MediaPipe (0-1 range)
    ///   - cameraResolution: Camera frame resolution (used for validation)
    ///   - previewSize: Screen/preview size in pixels
    /// - Returns: Screen coordinates in pixels, or .zero if invalid input
    static func mapVisionPointToScreen(
        _ point: CGPoint,
        cameraResolution: CGSize,
        previewSize: CGSize,
        flipY: Bool = false
    ) -> CGPoint {
        
        // Defensive checks for invalid dimensions
        guard cameraResolution.width > 0, cameraResolution.height > 0 else {
            FlexaLog.vision.warning("⚠️ Invalid camera resolution: width=\(cameraResolution.width) height=\(cameraResolution.height)")
            return .zero
        }
        
        guard previewSize.width > 0, previewSize.height > 0 else {
            FlexaLog.vision.warning("⚠️ Invalid preview size: width=\(previewSize.width) height=\(previewSize.height)")
            return .zero
        }
        
        // Defensive checks for NaN and Inf values
        guard !point.x.isNaN, !point.x.isInfinite, !point.y.isNaN, !point.y.isInfinite else {
            FlexaLog.vision.warning("⚠️ Invalid point values: (\(point.x), \(point.y))")
            return .zero
        }
        
    // Direct mapping: normalized → screen pixels
    // MediaPipe coordinates are usually portrait-oriented and mirrored, but callers
    // can specify different orientations via helper which defaults to portrait.
    let screenX = point.x * previewSize.width
    // Optionally flip Y (mirror vertically) for camera-based exercises
    let screenY = (flipY ? (1.0 - point.y) : point.y) * previewSize.height
        
        // Clamp to screen bounds
        let finalX = max(0, min(previewSize.width, screenX))
        let finalY = max(0, min(previewSize.height, screenY))
        
        FlexaLog.game.debug("🎯 [COORDS] vision(\(String(format: "%.3f", point.x)), \(String(format: "%.3f", point.y))) -> screen(\(String(format: "%.1f", finalX)), \(String(format: "%.1f", finalY)))")
        
        return CGPoint(x: finalX, y: finalY)
    }

    /// Map a normalized vision point to screen with explicit camera orientation handling.
    /// - Parameters:
    ///   - point: normalized vision point (0..1)
    ///   - cameraResolution: resolution of camera frame
    ///   - previewSize: screen preview size
    ///   - isPortrait: whether the camera frame is portrait-oriented (default true)
    /// - Returns: mapped screen coordinate or .zero on invalid input
    static func mapVisionPointToScreen(_ point: CGPoint, cameraResolution: CGSize, previewSize: CGSize, isPortrait: Bool, flipY: Bool = false) -> CGPoint {
        if isPortrait {
            return mapVisionPointToScreen(point, cameraResolution: cameraResolution, previewSize: previewSize, flipY: flipY)
        }

        // If camera frame was landscape, swap axes accordingly
        let transformed = CGPoint(x: point.y, y: 1.0 - point.x)
        return mapVisionPointToScreen(transformed, cameraResolution: cameraResolution, previewSize: previewSize, flipY: flipY)
    }

    /// Convert a pixel-space point in a fixed reference resolution into normalized 0..1 coordinates.
    /// - Parameters:
    ///   - point: Pixel-space point in reference coordinate system (e.g., 480x640 used by Vision provider)
    ///   - referenceSize: The reference size used by the provider (width, height)
    ///   - isMirrored: Whether the point should be mirrored horizontally (front camera)
    /// - Returns: Normalized CGPoint in 0..1 range with top-left origin
    static func normalizePixelPointToNormalized(_ point: CGPoint, referenceSize: CGSize, isMirrored: Bool) -> CGPoint {
        guard referenceSize.width > 0, referenceSize.height > 0 else { return .zero }

        var x = point.x / referenceSize.width
        let y = point.y / referenceSize.height

        if isMirrored {
            x = 1.0 - x
        }

        // Clamp to 0..1 to avoid out-of-bounds values
        let nx = max(0.0, min(1.0, x))
        let ny = max(0.0, min(1.0, y))
        return CGPoint(x: nx, y: ny)
    }
}
