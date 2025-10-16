import SwiftUI

#if canImport(UIKit)
extension View {
    /// Dismiss the iOS keyboard
    func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// Add a handler that dismisses keyboard when tapping anywhere in the view
    func dismissKeyboardOnTap() -> some View {
        self.onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
}
#endif
