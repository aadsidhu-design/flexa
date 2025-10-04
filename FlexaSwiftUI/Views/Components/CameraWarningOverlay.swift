import SwiftUI

struct CameraWarningOverlay: View {
    let isObstructed: Bool
    let reason: String
    
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        if isObstructed {
            VStack(spacing: 16) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.red)
                
                Text("Camera Issue")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text(reason)
                    .font(.body)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Text("Please ensure the camera is unobstructed and well-lit")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(themeManager.warningBackgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.red, lineWidth: 2)
                    )
            )
            .transition(.scale.combined(with: .opacity))
            .animation(.easeInOut(duration: 0.3), value: isObstructed)
        }
    }
}

#Preview {
    CameraWarningOverlay(
        isObstructed: true,
        reason: "Camera appears to be covered or in low light"
    )
    .background(Color.gray)
}
