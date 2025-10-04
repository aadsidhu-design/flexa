import SwiftUI

struct TapTargetModifier: ViewModifier {
    let minSize: CGFloat
    func body(content: Content) -> some View {
        content
            .frame(minWidth: minSize, minHeight: minSize, alignment: .center)
            .contentShape(Rectangle())
    }
}

extension View {
    /// Ensures the view has at least a minimum tappable size (default 44pt), improving accessibility.
    /// Applies a content shape so taps within the padded frame register.
    func tapTarget(_ minSize: CGFloat = 44) -> some View {
        modifier(TapTargetModifier(minSize: minSize))
    }
}
