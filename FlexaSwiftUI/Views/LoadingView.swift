import SwiftUI

struct LoadingView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.green)
                
                Text("Loading...")
                    .font(.title2)
                    .foregroundColor(.white)
            }
        }
    }
}

#Preview {
    LoadingView()
}
