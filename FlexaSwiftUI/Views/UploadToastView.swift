import SwiftUI

struct UploadToastView: View {
    let message: String
    let type: ToastType
    @Binding var isShowing: Bool
    
    enum ToastType {
        case uploading, success, error
        
        var color: Color {
            switch self {
            case .uploading: return .blue
            case .success: return .green
            case .error: return .red
            }
        }
        
        var icon: String {
            switch self {
            case .uploading: return "arrow.up.circle"
            case .success: return "checkmark.circle"
            case .error: return "xmark.circle"
            }
        }
    }
    
    var body: some View {
        if isShowing {
            HStack {
                Image(systemName: type.icon)
                    .foregroundColor(type.color)
                Text(message)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
            .cornerRadius(20)
            .shadow(radius: 4)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onAppear {
                if type != .uploading {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation {
                            isShowing = false
                        }
                    }
                }
            }
        }
    }
}
