import UIKit

class HapticFeedbackService: ObservableObject {
    static let shared = HapticFeedbackService()
    
    private init() {}
    
    // Light haptic for subtle interactions
    func lightHaptic() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    // Medium haptic for moderate interactions
    func mediumHaptic() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
    
    // Heavy haptic for strong interactions
    func heavyHaptic() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
    }
    
    // Success haptic for positive actions
    func successHaptic() {
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.success)
    }
    
    // Warning haptic for cautionary actions
    func warningHaptic() {
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.warning)
    }
    
    // Error haptic for negative actions
    func errorHaptic() {
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.error)
    }
    
    // Game-specific haptics
    func fruitSliceHaptic() {
        mediumHaptic()
    }
    
    func hammerHitHaptic() {
        heavyHaptic()
    }
    
    func repDetectedHaptic() {
        successHaptic()
    }
    
    func buttonTapHaptic() {
        lightHaptic()
    }
    
    // Bomb hit haptic for negative collisions in games
    func bombHitHaptic() {
        errorHaptic()
    }
    
    func destructiveActionHaptic() {
        warningHaptic()
    }
    
    func balloonPopHaptic() {
        successHaptic()
    }
    
    func targetHitHaptic() {
        mediumHaptic()
    }
}
