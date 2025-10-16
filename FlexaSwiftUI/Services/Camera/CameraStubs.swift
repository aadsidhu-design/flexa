import Foundation
import CoreGraphics
import AVFoundation

// CameraRepDetector is now implemented in CameraRepDetector.swift
// CameraROMCalculator is now implemented in CameraROMCalculator.swift  
// CameraSmoothnessAnalyzer is now implemented in CameraSmoothnessAnalyzer.swift
// (removed stubs to avoid duplicate class declarations)

// Bridge from SimpleMotionService.CameraJointPreference to the canonical
// top-level CameraJointPreference declared in `CameraJointPreference.swift`.
// We avoid declaring a duplicate enum here to prevent ambiguous type lookup.
extension CameraJointPreference {
    init(_ value: CameraJointPreference) {
        self = value
    }
}
