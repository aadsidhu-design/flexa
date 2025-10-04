import SwiftUI

struct CameraObstructionOverlay: View {
    let isObstructed: Bool
    let reason: String
    let isBackCamera: Bool
    
    var body: some View {
        if isObstructed {
            ZStack {
                // Semi-transparent background
                Color.black.opacity(0.8)
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    // Warning icon
                    Image(systemName: isBackCamera ? "camera.fill" : "camera.on.rectangle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.yellow)
                    
                    // Warning title
                    Text(isBackCamera ? "Back Camera Issue" : "Front Camera Issue")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    // Reason text
                    Text(reason)
                        .font(.headline)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                    
                    // Paused indicator
                    HStack {
                        Image(systemName: "pause.circle.fill")
                            .foregroundColor(.yellow)
                        Text("Game Paused")
                            .foregroundColor(.yellow)
                            .fontWeight(.semibold)
                    }
                    .font(.headline)
                    .padding(.top, 10)
                    
                    // Instructions
                    Text("Game will resume automatically when issue is resolved")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.top, 5)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.black.opacity(0.9))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.yellow, lineWidth: 2)
                        )
                )
                .padding()
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.3), value: isObstructed)
        }
    }
}

#Preview {
    CameraObstructionOverlay(
        isObstructed: true,
        reason: "Low light detected - please move to a brighter area",
        isBackCamera: true
    )
}
