import SwiftUI

struct CalibrationIntroView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingCalibration = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text("Calibrate ROM")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        
                        Text("This helps us track your exercises accurately")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)
                    
                    // Instructions
                    VStack(spacing: 16) {
                        // Step 1
                        instructionRow(
                            number: "1",
                            title: "Hold at chest",
                            description: "Hold the phone at your chest near your shoulder and keep still until it vibrates.",
                            icon: "figure.stand"
                        )
                        
                        // Step 2
                        instructionRow(
                            number: "2", 
                            title: "Hold in front",
                            description: "Extend your arm straight forward and keep still until it vibrates.",
                            icon: "ruler"
                        )
                        
                        // Step 3
                        instructionRow(
                            number: "3",
                            title: "That's it!",
                            description: "This sets your arm length so we can track ROM accurately.",
                            icon: "iphone"
                        )
                    }
                    .padding(.horizontal, 20)
                    
                    // Important note
                    HStack {
                        Image(systemName: "hand.point.right.fill")
                            .foregroundColor(.orange)
                        Text("Make sure your arm is straight during Step 2")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                            .fontWeight(.medium)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                    
                    // Continue button
                    Button(action: {
                        showingCalibration = true
                    }) {
                        Text("Start Calibration")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .fullScreenCover(isPresented: $showingCalibration) {
            CalibrationWizardView()
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CalibrationCompleted"))) { _ in
                    showingCalibration = false
                    // Update calibration check service
                    CalibrationCheckService.shared.checkCalibrationStatus()
                    dismiss()
                }
        }
    }
    
    private func instructionRow(number: String, title: String, description: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            // Number circle
            Text(number)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Color.blue)
                .clipShape(Circle())
            
            // Icon
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 30)
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

#Preview {
    CalibrationIntroView()
}
